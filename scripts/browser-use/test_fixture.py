#!/usr/bin/env python3
"""Linux-capable fixture/coverage checks. This does NOT execute Astra or WebKit."""
import hashlib
import importlib.util
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/browser-use/client'))
spec=importlib.util.spec_from_file_location('fixture',ROOT/'scripts/browser-use/site/server.py')
fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)
from page_cases import register as pages
from native_cases import register as natives
from extended_cases import register as extended
from run import native_order


def request(url,body=None,headers=None):
    try:
        with urllib.request.urlopen(urllib.request.Request(url,body,headers or {}),timeout=5) as response:
            return response.status,response.headers,response.read()
    except urllib.error.HTTPError as e:return e.code,e.headers,e.read()


def main():
    primary,peer=fixture.launch()
    try:
        base=f'http://127.0.0.1:{primary.server_port}'
        status,_,body=request(base+'/?run=self-test')
        assert status==200 and b'__PEER_PORT__' not in body and b'__FRAME__' not in body
        assert b'secret-sentinel-must-not-leak' in body
        status,_,body=request(base+'/frame?run=self-test')
        assert b'frame-button' in body and b'fixture-click' not in body,'frame selectors must not collide with main page'
        _,_,body=request(base+'/download')
        assert body==fixture.BINARY
        _,_,body=request(base+'/health');assert json.loads(body)['sha256']==hashlib.sha256(fixture.BINARY).hexdigest()
        request(base+'/state/self-test',json.dumps({'clicks':3,'password':'never-store'}).encode(),{'Content-Type':'application/json'})
        _,_,body=request(base+'/state/self-test');assert json.loads(body)=={'clicks':3}
        request(base+'/upload/self-test',fixture.BINARY)
        _,_,body=request(base+'/state/self-test');assert json.loads(body)['upload']['sha256']==hashlib.sha256(fixture.BINARY).hexdigest()
        assert request(base+'/authenticated')[0]==401
        status,_,body=request(base+'/authenticated',headers={'Cookie':'astra_fixture_session=fixture-user'})
        assert status==200 and json.loads(body)['authenticated'] is True
        # Registration must be executable without performing calls; actual runtime
        # tool discovery in run.py is the authoritative completeness assertion.
        cases={}
        context={'page':base+'/?run=self-test'}
        for register in [pages,natives,extended]:register(cases,context,lambda *a:None,lambda *a:None)
        assert all(callable(case) for case in cases.values())
        assert set(native_order)<=cases.keys(), sorted(set(native_order)-cases.keys())
        assert len(native_order)==len(set(native_order))
        assert len(cases)>=120,len(cases)
        print(f'PASS deterministic HTTP fixture and {len(cases)} registered expanded tool cases (no WebKit claim)')
    finally:
        primary.shutdown();peer.shutdown();primary.server_close();peer.server_close()


if __name__=='__main__':main()
