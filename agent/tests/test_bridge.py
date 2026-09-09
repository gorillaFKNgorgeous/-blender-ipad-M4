import base64
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import sys
import tempfile
import threading
import time
import unittest
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request, urlopen

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'relay'))
sys.path.insert(0,str(ROOT/'runtime'))
from server import App, Server
from runtime import AgentRuntime, ExecutionContext, MemoryJournal, RuntimeErrorSafe


def heartbeat(scene='scene_one',boot='boot_one'):
    return {'boot_id':boot,'scene_id':scene,'blender_version':'5.2.0','native':{'foreground':True},'memory':{'rss_bytes':1}}


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.db=Path(self.tmp.name)/'relay.sqlite3'
        self.app=App(str(self.db),'https://relay.example','ipad','d'*40,'a'*40,'client','c'*40,'o'*40,['https://client.example/callback'])
        self.server=Server(('127.0.0.1',0),self.app)
        self.port=self.server.server_address[1]
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True); self.thread.start()

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(timeout=2); self.tmp.cleanup()

    def request(self,path,body=None,token=None,method='POST',headers=None,form=False):
        url=f'http://127.0.0.1:{self.port}{path}'
        data=None
        req_headers={'Host':'relay.example','Accept':'application/json, text/event-stream'}
        if body is not None:
            if form:
                data=urlencode(body).encode(); req_headers['Content-Type']='application/x-www-form-urlencoded'
            else:
                data=json.dumps(body).encode(); req_headers['Content-Type']='application/json'
        if token: req_headers['Authorization']='Bearer '+token
        req_headers.update(headers or {})
        req=Request(url,data=data,method=method,headers=req_headers)
        try:
            with urlopen(req,timeout=3) as r:
                raw=r.read(); return r.status,(json.loads(raw) if raw else None),dict(r.headers)
        except HTTPError as e:
            raw=e.read(); return e.code,(json.loads(raw) if raw else None),dict(e.headers)

    def test_store_duplicate_and_scene_guard(self):
        self.app.store.exchange('ipad',heartbeat())
        a=self.app.call('inspect_scene',{'request_id':'inspect_01','scene_id':'scene_one'})
        b=self.app.call('inspect_scene',{'request_id':'inspect_01','scene_id':'scene_one'})
        self.assertEqual(a['job_id'],b['job_id'])
        with self.assertRaises(ValueError): self.app.call('inspect_scene',{'request_id':'inspect_01','scene_id':'other'})

    def test_issued_is_not_reissued(self):
        self.app.store.exchange('ipad',heartbeat())
        job=self.app.call('inspect_scene',{'request_id':'inspect_02','scene_id':'scene_one'})
        first=self.app.store.exchange('ipad',heartbeat())
        self.assertEqual(first['job']['job_id'],job['job_id'])
        second=self.app.store.exchange('ipad',heartbeat())
        self.assertIsNone(second['job'])

    def test_result_completion_ack(self):
        self.app.store.exchange('ipad',heartbeat())
        job=self.app.call('inspect_scene',{'request_id':'inspect_03','scene_id':'scene_one'})
        self.app.store.exchange('ipad',heartbeat())
        done={'job_id':job['job_id'],'boot_id':'boot_one','result':{'ok':True,'value':{'objects':[]}}}
        reply=self.app.store.exchange('ipad',heartbeat(),done)
        self.assertEqual(reply['ack'],job['job_id'])
        result=self.app.call('job_result',{'job_id':job['job_id']})
        self.assertEqual(result['state'],'completed')

    def test_scene_change_expires_queued(self):
        self.app.store.exchange('ipad',heartbeat())
        job=self.app.call('inspect_scene',{'request_id':'inspect_04','scene_id':'scene_one'})
        self.app.store.exchange('ipad',heartbeat(scene='scene_two'))
        self.assertEqual(self.app.call('job_result',{'job_id':job['job_id']})['state'],'expired')

    def test_mcp_rejects_bad_origin(self):
        rpc={'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'test','version':'1'}}}
        self.assertEqual(self.request('/mcp',rpc,token='a'*40,headers={'Origin':'https://evil.example'})[0],403)

    def test_mcp_handshake_notification_and_pending_job(self):
        message={'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'test','version':'1'}}}
        status,result,_=self.request('/mcp',message,token='a'*40)
        self.assertEqual(status,200); self.assertEqual(result['result']['protocolVersion'],'2025-11-25')
        self.assertEqual(self.request('/mcp',{'jsonrpc':'2.0','method':'notifications/initialized'},token='a'*40)[0],202)
        self.assertEqual(self.request('/mcp',token='a'*40,method='GET')[0],405)
        self.request('/device/exchange',{'protocol':1,'device_id':'ipad','heartbeat':heartbeat()},token='d'*40)
        value=self.app.call('inspect_scene',{'request_id':'inspect_01','scene_id':'scene_one'})
        rpc={'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'job_result','arguments':{'job_id':value['job_id']}}}
        status,reply,_=self.request('/mcp',rpc,token='a'*40)
        self.assertEqual(status,200); self.assertFalse(reply['result']['isError'])

    def test_capture_is_returned_as_mcp_image(self):
        self.app.store.exchange('ipad',heartbeat())
        job=self.app.call('capture',{'request_id':'capture_01','scene_id':'scene_one'})
        self.app.store.exchange('ipad',heartbeat())
        data=base64.b64encode(b'fixture').decode()
        self.app.store.exchange('ipad',heartbeat(),{'job_id':job['job_id'],'boot_id':'boot_one',
            'result':{'ok':True,'value':{'mime_type':'image/png','data':data,'source':'screenshot'}}})
        reply=self.app.rpc({'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'job_result','arguments':{'job_id':job['job_id']}}})
        self.assertEqual(reply['result']['content'][1]['type'],'image')
        self.assertEqual(reply['result']['content'][1]['data'],data)

    def test_oauth_pkce_single_use_and_refresh_rotation(self):
        oauth=self.app.oauth
        verifier='v'*64
        challenge=base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
        params={'client_id':'client','response_type':'code','redirect_uri':'https://client.example/callback',
                'resource':'https://relay.example/mcp','code_challenge_method':'S256','code_challenge':challenge,'state':'original-state'}
        page=oauth.authorize_form(params)
        ticket=re.search('name="ticket" value="([^"]+)"',page)[1]
        with self.assertRaises(ValueError): oauth.approve(ticket,'wrong')
        redirect=oauth.approve(ticket,'o'*40)
        self.assertEqual(oauth.approve(ticket,'o'*40),redirect)
        query=parse_qs(urlsplit(redirect).query)
        self.assertEqual(query['state'],['original-state'])
        self.assertEqual(query['iss'],[oauth.origin])
        token_params={'client_id':'client','client_secret':'c'*40,'resource':oauth.resource,
                      'grant_type':'authorization_code','code':query['code'][0],
                      'redirect_uri':params['redirect_uri'],'code_verifier':verifier}
        tokens=oauth.token(token_params)
        self.assertTrue(oauth.authenticate(tokens['access_token']))
        with self.assertRaises(ValueError): oauth.token(token_params)
        refresh={**token_params,'grant_type':'refresh_token','refresh_token':tokens['refresh_token']}
        newer=oauth.token(refresh)
        self.assertTrue(oauth.authenticate(newer['access_token']))
        with self.assertRaises(ValueError): oauth.token(refresh)
        oauth.revision='changed'
        self.assertFalse(oauth.authenticate(newer['access_token']))
        with self.assertRaises(ValueError): oauth.authorize_form({**params,'redirect_uri':'https://evil.example'})


if __name__ == '__main__':
    unittest.main()
