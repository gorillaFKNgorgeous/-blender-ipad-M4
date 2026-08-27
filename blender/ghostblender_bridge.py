# SPDX-License-Identifier: GPL-3.0-or-later

"""GhostBlender iPad outbound bridge.

Installed as a Blender startup script. It never listens for inbound network
traffic and does not expose arbitrary Python execution.
"""

import json
import math
import os
import platform
import queue
import re
import ssl
import sys
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request

import bpy
from bpy.props import StringProperty


BRIDGE_VERSION = "0.1.0"
POLL_TIMEOUT_SECONDS = 15
RESULT_TIMEOUT_SECONDS = 60
_COMMANDS = queue.Queue(maxsize=4)
_RESULTS = queue.Queue(maxsize=4)
_STOP = threading.Event()
_WORKER = None
_STATUS = "Disconnected"
_LAST_ERROR = ""


def _config_path():
    config_root = bpy.utils.user_resource("CONFIG", path="ghostblender", create=True)
    return os.path.join(config_root, "bridge.json")


def _load_config():
    try:
        with open(_config_path(), "r", encoding="utf-8") as handle:
            value = json.load(handle)
            return {
                "base_url": str(value.get("base_url", "")),
                "device_token": str(value.get("device_token", "")),
            }
    except (OSError, ValueError, TypeError):
        return {"base_url": "", "device_token": ""}


def _save_config(base_url, device_token):
    value = {"base_url": base_url.strip().rstrip("/"), "device_token": device_token.strip()}
    path = _config_path()
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle)
    os.replace(temporary, path)


def _set_status(status, error=""):
    global _STATUS, _LAST_ERROR
    _STATUS = status
    _LAST_ERROR = error[:300]


def _validate_config(base_url, token):
    parsed = urllib.parse.urlparse(base_url)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ValueError("Server must be a complete https:// address")
    if len(token) < 32:
        raise ValueError("Device token is incomplete")


def _request(base_url, token, path, method="GET", payload=None, timeout=20):
    url = base_url.rstrip("/") + path
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {
        "authorization": "Bearer " + token,
        "user-agent": "GhostBlender-iPad/" + BRIDGE_VERSION,
        "x-ghostblender-device": "Blender iPad",
    }
    if data is not None:
        headers["content-type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    return urllib.request.urlopen(request, timeout=timeout, context=ssl.create_default_context())


def _post_result(base_url, token, result):
    with _request(base_url, token, "/device/result", method="POST", payload=result, timeout=20):
        return


def _network_worker(base_url, token):
    _set_status("Connecting")
    while not _STOP.is_set():
        try:
            with _request(
                base_url,
                token,
                "/device/poll?timeout=10000",
                timeout=POLL_TIMEOUT_SECONDS,
            ) as response:
                if response.status == 204:
                    _set_status("Connected")
                    continue
                command = json.loads(response.read().decode("utf-8"))
            _set_status("Running " + str(command.get("type", "command")))
            _COMMANDS.put(command, timeout=2)
            result = _RESULTS.get(timeout=RESULT_TIMEOUT_SECONDS)
            _post_result(base_url, token, result)
            _set_status("Connected")
        except urllib.error.HTTPError as error:
            if error.code == 401:
                _set_status("Authentication failed", "Check the device token")
                _STOP.wait(5)
            else:
                _set_status("Network error", "HTTP " + str(error.code))
                _STOP.wait(2)
        except queue.Empty:
            _set_status("Command timed out", "Blender main thread did not answer")
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
            _set_status("Reconnecting", str(error))
            _STOP.wait(2)
        except Exception as error:
            _set_status("Bridge error", str(error))
            _STOP.wait(2)
    _set_status("Disconnected")


def _vector(value, default):
    if value is None:
        return list(default)
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError("Expected a three-number vector")
    result = [float(component) for component in value]
    if not all(math.isfinite(component) for component in result):
        raise ValueError("Vector contains a non-finite number")
    return result


def _object_snapshot(obj):
    return {
        "name": obj.name,
        "type": obj.type,
        "location": [round(float(value), 6) for value in obj.location],
        "rotationDegrees": [round(math.degrees(float(value)), 4) for value in obj.rotation_euler],
        "scale": [round(float(value), 6) for value in obj.scale],
        "visible": not obj.hide_get(),
        "selected": obj.select_get(),
    }


def _scene_summary(_args):
    scene = bpy.context.scene
    objects = list(scene.objects)
    active = bpy.context.view_layer.objects.active
    return {
        "blenderVersion": bpy.app.version_string,
        "scene": scene.name,
        "file": bpy.data.filepath or None,
        "frame": scene.frame_current,
        "renderEngine": scene.render.engine,
        "objectCount": len(objects),
        "selectedObjects": [obj.name for obj in bpy.context.selected_objects],
        "activeObject": active.name if active else None,
        "objects": [_object_snapshot(obj) for obj in objects[:250]],
        "truncated": len(objects) > 250,
    }


def _list_objects(args):
    requested_type = str(args.get("type", "")).upper().strip()
    objects = [obj for obj in bpy.context.scene.objects if not requested_type or obj.type == requested_type]
    return {
        "objects": [_object_snapshot(obj) for obj in objects[:500]],
        "count": len(objects),
        "truncated": len(objects) > 500,
    }


def _create_primitive(args):
    primitive = str(args.get("type", "")).upper()
    location = _vector(args.get("location"), (0.0, 0.0, 0.0))
    scale = _vector(args.get("scale"), (1.0, 1.0, 1.0))
    if any(value <= 0 for value in scale):
        raise ValueError("Scale values must be positive")

    operators = {
        "CUBE": bpy.ops.mesh.primitive_cube_add,
        "UV_SPHERE": bpy.ops.mesh.primitive_uv_sphere_add,
        "CYLINDER": bpy.ops.mesh.primitive_cylinder_add,
        "CONE": bpy.ops.mesh.primitive_cone_add,
        "TORUS": bpy.ops.mesh.primitive_torus_add,
    }
    operator = operators.get(primitive)
    if operator is None:
        raise ValueError("Unsupported primitive type")
    result = operator(location=location)
    if "FINISHED" not in result or bpy.context.object is None:
        raise RuntimeError("Blender did not create the primitive")

    obj = bpy.context.object
    requested_name = str(args.get("name", "")).strip()
    if requested_name:
        if not re.fullmatch(r"[\w .-]{1,63}", requested_name, flags=re.UNICODE):
            raise ValueError("Object name contains unsupported characters")
        obj.name = requested_name
    obj.scale = scale
    bpy.context.view_layer.update()
    return {"object": _object_snapshot(obj)}


def _set_object_transform(args):
    name = str(args.get("name", ""))
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise ValueError("Object not found: " + name)
    if "location" in args:
        obj.location = _vector(args.get("location"), obj.location)
    if "rotationDegrees" in args:
        obj.rotation_euler = [math.radians(value) for value in _vector(args.get("rotationDegrees"), (0, 0, 0))]
    if "scale" in args:
        scale = _vector(args.get("scale"), obj.scale)
        if any(value <= 0 for value in scale):
            raise ValueError("Scale values must be positive")
        obj.scale = scale
    bpy.context.view_layer.update()
    return {"object": _object_snapshot(obj)}


def _documents_directory():
    path = os.path.realpath(os.path.expanduser("~/Documents"))
    os.makedirs(path, exist_ok=True)
    return path


def _save_blend_file(args):
    filename = str(args.get("filename", "")).strip()
    if not filename.lower().endswith(".blend"):
        filename += ".blend"
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._-]{0,94}\.blend", filename):
        raise ValueError("Use a simple filename without folders or special characters")
    documents = _documents_directory()
    path = os.path.realpath(os.path.join(documents, filename))
    if os.path.dirname(path) != documents:
        raise ValueError("Save path escaped the Documents directory")
    if os.path.exists(path):
        raise FileExistsError("The file already exists; choose a new filename")
    result = bpy.ops.wm.save_as_mainfile(filepath=path, check_existing=False)
    if "FINISHED" not in result:
        raise RuntimeError("Blender did not save the file")
    return {"filename": filename, "path": path}


def _capability_tests(_args):
    tests = {}
    for module_name in ("socket", "ssl", "select"):
        try:
            __import__(module_name)
            tests["pythonModule." + module_name] = "PASS"
        except Exception as error:
            tests["pythonModule." + module_name] = "FAIL: " + str(error)

    test_path = None
    descriptor = None
    try:
        descriptor, test_path = tempfile.mkstemp(prefix="ghostblender-", suffix=".tmp", dir=_documents_directory())
        os.write(descriptor, b"ghostblender")
        os.close(descriptor)
        descriptor = None
        with open(test_path, "rb") as handle:
            tests["documentsReadWrite"] = "PASS" if handle.read() == b"ghostblender" else "FAIL"
    except Exception as error:
        tests["documentsReadWrite"] = "FAIL: " + str(error)
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if test_path:
            try:
                os.unlink(test_path)
            except OSError:
                pass

    return {
        "bridgeVersion": BRIDGE_VERSION,
        "blenderVersion": bpy.app.version_string,
        "pythonVersion": sys.version.split()[0],
        "platform": platform.platform(),
        "background": bpy.app.background,
        "tests": tests,
    }


_HANDLERS = {
    "scene_summary": _scene_summary,
    "list_objects": _list_objects,
    "create_primitive": _create_primitive,
    "set_object_transform": _set_object_transform,
    "save_blend_file": _save_blend_file,
    "capability_tests": _capability_tests,
}


def _process_commands():
    try:
        command = _COMMANDS.get_nowait()
    except queue.Empty:
        return 0.1

    command_id = str(command.get("id", ""))
    command_type = str(command.get("type", ""))
    try:
        handler = _HANDLERS.get(command_type)
        if handler is None:
            raise ValueError("Unsupported command: " + command_type)
        result = handler(command.get("args") or {})
        response = {"id": command_id, "ok": True, "result": result}
    except Exception as error:
        response = {"id": command_id, "ok": False, "error": f"{type(error).__name__}: {error}"}
    try:
        _RESULTS.put_nowait(response)
    except queue.Full:
        _set_status("Bridge error", "Result queue is full")
    return 0.1


class GHOSTBLENDER_OT_save_config(bpy.types.Operator):
    bl_idname = "ghostblender.save_config"
    bl_label = "Save Bridge Settings"
    bl_options = {"INTERNAL"}

    def execute(self, context):
        try:
            _validate_config(context.window_manager.ghostblender_base_url, context.window_manager.ghostblender_device_token)
            _save_config(context.window_manager.ghostblender_base_url, context.window_manager.ghostblender_device_token)
            self.report({"INFO"}, "GhostBlender settings saved in the app sandbox")
            return {"FINISHED"}
        except Exception as error:
            self.report({"ERROR"}, str(error))
            return {"CANCELLED"}


class GHOSTBLENDER_OT_connect(bpy.types.Operator):
    bl_idname = "ghostblender.connect"
    bl_label = "Connect GhostBlender"
    bl_options = {"INTERNAL"}

    def execute(self, context):
        global _WORKER
        if _WORKER is not None and _WORKER.is_alive():
            self.report({"INFO"}, "GhostBlender is already connected")
            return {"FINISHED"}
        if not bpy.app.online_access:
            self.report({"ERROR"}, "Enable Online Access in Blender Preferences before connecting")
            return {"CANCELLED"}
        base_url = context.window_manager.ghostblender_base_url.strip().rstrip("/")
        token = context.window_manager.ghostblender_device_token.strip()
        try:
            _validate_config(base_url, token)
            _save_config(base_url, token)
        except Exception as error:
            self.report({"ERROR"}, str(error))
            return {"CANCELLED"}
        _STOP.clear()
        _WORKER = threading.Thread(
            target=_network_worker,
            args=(base_url, token),
            name="GhostBlenderBridge",
            daemon=True,
        )
        _WORKER.start()
        return {"FINISHED"}


class GHOSTBLENDER_OT_disconnect(bpy.types.Operator):
    bl_idname = "ghostblender.disconnect"
    bl_label = "Disconnect GhostBlender"
    bl_options = {"INTERNAL"}

    def execute(self, _context):
        _STOP.set()
        _set_status("Disconnecting")
        return {"FINISHED"}


class GHOSTBLENDER_OT_self_test(bpy.types.Operator):
    bl_idname = "ghostblender.self_test"
    bl_label = "Run Local Self-Test"
    bl_options = {"INTERNAL"}

    def execute(self, _context):
        result = _capability_tests({})
        failures = [name for name, value in result["tests"].items() if not value.startswith("PASS")]
        if failures:
            self.report({"ERROR"}, "Self-test failures: " + ", ".join(failures))
            return {"CANCELLED"}
        self.report({"INFO"}, "GhostBlender local self-test passed")
        return {"FINISHED"}


class GHOSTBLENDER_PT_bridge(bpy.types.Panel):
    bl_label = "GhostBlender"
    bl_idname = "GHOSTBLENDER_PT_bridge"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "GhostBlender"

    def draw(self, context):
        layout = self.layout
        layout.label(text="Status: " + _STATUS)
        if _LAST_ERROR:
            layout.label(text=_LAST_ERROR, icon="ERROR")
        layout.prop(context.window_manager, "ghostblender_base_url")
        layout.prop(context.window_manager, "ghostblender_device_token")
        row = layout.row(align=True)
        row.operator("ghostblender.connect", icon="LINKED")
        row.operator("ghostblender.disconnect", icon="UNLINKED")
        layout.operator("ghostblender.save_config", icon="FILE_TICK")
        layout.operator("ghostblender.self_test", icon="CHECKMARK")
        layout.label(text="Bridge " + BRIDGE_VERSION)


_CLASSES = (
    GHOSTBLENDER_OT_save_config,
    GHOSTBLENDER_OT_connect,
    GHOSTBLENDER_OT_disconnect,
    GHOSTBLENDER_OT_self_test,
    GHOSTBLENDER_PT_bridge,
)


def _apply_loaded_config():
    config = _load_config()
    if bpy.context.window_manager:
        bpy.context.window_manager.ghostblender_base_url = config["base_url"]
        bpy.context.window_manager.ghostblender_device_token = config["device_token"]
    return None


def register():
    for cls in _CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.WindowManager.ghostblender_base_url = StringProperty(
        name="Server",
        description="GhostBlender Cloud Run base URL",
        default="",
    )
    bpy.types.WindowManager.ghostblender_device_token = StringProperty(
        name="Device Token",
        description="Private token issued for this Blender iPad bridge",
        default="",
        subtype="PASSWORD",
    )
    bpy.app.timers.register(_process_commands, first_interval=0.5, persistent=True)
    bpy.app.timers.register(_apply_loaded_config, first_interval=1.0)


def unregister():
    _STOP.set()
    if bpy.app.timers.is_registered(_process_commands):
        bpy.app.timers.unregister(_process_commands)
    for property_name in ("ghostblender_base_url", "ghostblender_device_token"):
        if hasattr(bpy.types.WindowManager, property_name):
            delattr(bpy.types.WindowManager, property_name)
    for cls in reversed(_CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
