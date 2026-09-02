#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match in {path}, found {count}")
    if new in text:
        raise RuntimeError(f"{label}: replacement already present in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"Applied {label}: {path}")


def require_once(path: Path, needle: str, label: str) -> None:
    count = path.read_text(encoding="utf-8").count(needle)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match in {path}, found {count}")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: apply-ios-files-scene.py BLENDER_SOURCE_DIR")

    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        raise RuntimeError(f"Blender source directory does not exist: {root}")

    picker = root / "intern/ghost/intern/GHOST_FilePickerIOS.mm"
    replace_once(
        picker,
        """      /* Open in place. Copy-mode leaves the picker on screen while a provider copies a large
       * .blend file into the app container, which looks like the tap was ignored. Blender already
       * brackets its reads with security-scoped access, so in-place URLs are the correct model. */
      picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes
                                                                           asCopy:NO];
""",
        """      /* Import a sandbox-readable copy. Build 73's open-in-place path presented correctly on
       * device but never produced a selection callback. Copy mode uses UIKit's provider transaction
       * and returns a local URL that Blender can read without relying on provider open-in-place state. */
      picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes
                                                                           asCopy:YES];
""",
        "native Files open picker copy mode",
    )

    system = root / "intern/ghost/intern/GHOST_SystemIOS.mm"
    replace_once(
        system,
        """static NSMutableArray<NSURL *> *s_pendingOpenURLs = nil;

static void blender_ios_queueOpenURL(NSURL *url, NSString *source)
""",
        """static NSMutableArray<NSURL *> *s_pendingOpenURLs = nil;
static BOOL s_blenderBootstrapped = NO;

static void blender_ios_queueOpenURL(NSURL *url, NSString *source)
""",
        "scene bootstrap guard",
    )

    replace_once(
        system,
        """@interface IOSAppDelegate : UIResponder <UIApplicationDelegate>

@property(strong, nonatomic) UIWindow *window;

@end
""",
        """@interface IOSSceneDelegate : UIResponder <UIWindowSceneDelegate>

@property(strong, nonatomic) UIWindow *window;
- (void)retainBlenderWindowForScene:(UIWindowScene *)windowScene;

@end

@interface IOSAppDelegate : UIResponder <UIApplicationDelegate>

@property(strong, nonatomic) UIWindow *window;

@end
""",
        "Blender UIWindowScene delegate declaration",
    )

    replace_once(
        system,
        """- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  GHOST_ios_resetFileLog();
  GHOST_ios_logFileEvent(
      (__bridge void *)@\"FILES_LIFECYCLE_V2 launch began; diagnostic log reset\");

  NSURL *launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
  if (launchURL) {
    blender_ios_queueOpenURL(launchURL, @\"cold launch\");
  }
  else {
    GHOST_ios_logFileEvent((__bridge void *)@\"cold launch has no document URL\");
  }

  main_ios_callback(argc, argv);

  GHOST_ios_logFileEvent((__bridge void *)@\"Blender context initialization returned\");
  dispatch_async(dispatch_get_main_queue(), ^{
    blender_ios_deliverPendingOpenURLs();
  });

  return YES;
}
""",
        """- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  GHOST_ios_resetFileLog();
  GHOST_ios_logFileEvent(
      (__bridge void *)@\"FILES_LIFECYCLE_V2 + FILES_SCENE_V3 app launch began; waiting for UIWindowScene\");

  /* A scene-based launch normally supplies document URLs through UISceneConnectionOptions. Keep
   * this legacy application-level URL only as a compatibility fallback. */
  NSURL *launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
  if (launchURL) {
    blender_ios_queueOpenURL(launchURL, @\"application launch fallback\");
  }
  else {
    GHOST_ios_logFileEvent((__bridge void *)@\"application launch has no legacy document URL\");
  }

  /* Do not create Blender's Metal window here. At this point UIKit has not yet handed us the
   * UIWindowScene that owns the document lifecycle. IOSSceneDelegate bootstraps Blender from
   * scene:willConnectToSession:options: instead. */
  return YES;
}
""",
        "defer Blender bootstrap to UIWindowScene",
    )

    replace_once(
        system,
        """  return YES;
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
""",
        """  return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options
{
  GHOST_ios_logFileEvent((__bridge void *)@\"configuring Blender UIWindowScene delegate\");
  UISceneConfiguration *configuration =
      [[[UISceneConfiguration alloc] initWithName:@\"Blender Scene\"
                                      sessionRole:connectingSceneSession.role] autorelease];
  configuration.delegateClass = [IOSSceneDelegate class];
  return configuration;
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
""",
        "programmatic UIWindowScene configuration",
    )

    replace_once(
        system,
        """@end

@implementation GHOST_IOSMetalRenderer
""",
        """@end

@implementation IOSSceneDelegate

- (void)retainBlenderWindowForScene:(UIWindowScene *)windowScene
{
  GHOST_SystemIOS *system = static_cast<GHOST_SystemIOS *>(GHOST_ISystem::getSystem());
  GHOST_WindowIOS *blenderWindow = system ? system->current_active_window : nullptr;
  if (!blenderWindow || !system->validWindow(blenderWindow)) {
    GHOST_ios_logFileEvent(
        (__bridge void *)@\"scene delegate could not retain a valid Blender window yet\");
    return;
  }

  self.window = blenderWindow->rootWindow;
  NSString *message = [NSString
      stringWithFormat:@\"scene delegate retained Blender window; scene-match=%@ key=%@ level=%.0f\",
                       self.window.windowScene == windowScene ? @\"yes\" : @\"no\",
                       self.window.isKeyWindow ? @\"yes\" : @\"no\",
                       self.window.windowLevel];
  GHOST_ios_logFileEvent((__bridge void *)message);
}

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions
{
  if (![scene isKindOfClass:[UIWindowScene class]]) {
    GHOST_ios_logFileEvent((__bridge void *)@\"scene connection rejected non-window scene\");
    return;
  }

  NSString *connectMessage = [NSString
      stringWithFormat:@\"scene willConnect; delegate=%@ URL count=%lu\",
                       NSStringFromClass([self class]),
                       (unsigned long)connectionOptions.URLContexts.count];
  GHOST_ios_logFileEvent((__bridge void *)connectMessage);

  for (UIOpenURLContext *context in connectionOptions.URLContexts) {
    NSString *source = [NSString
        stringWithFormat:@\"scene cold open (open-in-place=%@)\",
                         context.options.openInPlace ? @\"yes\" : @\"no\"];
    blender_ios_queueOpenURL(context.URL, source);
  }

  if (!s_blenderBootstrapped) {
    s_blenderBootstrapped = YES;
    GHOST_ios_logFileEvent(
        (__bridge void *)@\"bootstrapping Blender inside scene:willConnectToSession:options:\");
    main_ios_callback(argc, argv);
    GHOST_ios_logFileEvent(
        (__bridge void *)@\"Blender context initialization returned inside UIWindowScene\");
  }

  [self retainBlenderWindowForScene:(UIWindowScene *)scene];
  dispatch_async(dispatch_get_main_queue(), ^{
    blender_ios_deliverPendingOpenURLs();
  });
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts
{
  NSString *callback = [NSString
      stringWithFormat:@\"scene openURLContexts callback, URL count=%lu\",
                       (unsigned long)URLContexts.count];
  GHOST_ios_logFileEvent((__bridge void *)callback);

  for (UIOpenURLContext *context in URLContexts) {
    NSString *source = [NSString
        stringWithFormat:@\"scene warm open (open-in-place=%@)\",
                         context.options.openInPlace ? @\"yes\" : @\"no\"];
    blender_ios_queueOpenURL(context.URL, source);
  }
  blender_ios_deliverPendingOpenURLs();
}

- (void)sceneDidBecomeActive:(UIScene *)scene
{
  GHOST_ios_logFileEvent((__bridge void *)@\"scene became active; retaining window and flushing URL queue\");
  if ([scene isKindOfClass:[UIWindowScene class]]) {
    [self retainBlenderWindowForScene:(UIWindowScene *)scene];
  }
  blender_ios_deliverPendingOpenURLs();
}

@end

@implementation GHOST_IOSMetalRenderer
""",
        "scene URL receiver and window retention",
    )

    info = root / "release/ios/Blender.app/Info.plist"
    replace_once(
        info,
        """    <key>LSSupportsOpeningDocumentsInPlace</key>
    <true/>
\t<key>UISupportedInterfaceOrientations</key>
""",
        """    <key>LSSupportsOpeningDocumentsInPlace</key>
    <true/>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
        <key>UISceneConfigurations</key>
        <dict>
            <key>UIWindowSceneSessionRoleApplication</key>
            <array>
                <dict>
                    <key>UISceneConfigurationName</key>
                    <string>Blender Scene</string>
                    <key>UISceneClassName</key>
                    <string>UIWindowScene</string>
                    <key>UISceneDelegateClassName</key>
                    <string>IOSSceneDelegate</string>
                </dict>
            </array>
        </dict>
    </dict>
\t<key>UISupportedInterfaceOrientations</key>
""",
        "Info.plist UIWindowScene manifest",
    )

    require_once(picker, "asCopy:YES", "copy-mode open picker")
    require_once(picker, "asCopy:NO", "in-place save-folder picker")
    require_once(system, "FILES_SCENE_V3", "scene lifecycle marker")
    require_once(system, "@interface IOSSceneDelegate : UIResponder <UIWindowSceneDelegate>",
                 "scene delegate declaration")
    require_once(system, "configuration.delegateClass = [IOSSceneDelegate class];",
                 "scene delegate configuration")
    require_once(system, "willConnectToSession:(UISceneSession *)session",
                 "cold scene URL receiver")
    require_once(system, "openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts",
                 "warm scene URL receiver")
    require_once(system, "self.window = blenderWindow->rootWindow;",
                 "scene window retention")
    require_once(info, "<string>IOSSceneDelegate</string>", "scene delegate plist entry")

    print("iOS Files scene lifecycle transform completed successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
