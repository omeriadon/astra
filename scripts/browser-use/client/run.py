#!/usr/bin/env python3
"""External MCP client against a real isolated Astra process and WebKit fixture."""
import argparse
import concurrent.futures
import uuid
from page_cases import register as register_page
from native_cases import register as register_native
from extended_cases import register as register_extended
import json
import os
import signal
import time
import urllib.error
import urllib.request
from pathlib import Path


def check(condition, description, actual=None):
    if not condition:
        raise AssertionError(f"{description}; actual={actual!r}")


class Client:
    def __init__(self, endpoint, token, version="2025-11-25"):
        self.endpoint, self.token, self.version, self.sequence = endpoint, token, version, 0

    def request(self, method, params=None, *, token=None, origin=None, version=None):
        self.sequence += 1
        body = json.dumps({"jsonrpc": "2.0", "id": self.sequence, "method": method,
                           "params": params or {}}).encode()
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                   "Authorization": "Bearer " + (token if token is not None else self.token),
                   "MCP-Protocol-Version": version or self.version}
        if origin:
            headers["Origin"] = origin
        if version == "2026-07-28":
            params = json.loads(body)["params"]
            params["_meta"] = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
                               "io.modelcontextprotocol/clientCapabilities": {},
                               "io.modelcontextprotocol/clientInfo": {"name": "astra-e2e", "version": "1"}}
            body = json.dumps({"jsonrpc": "2.0", "id": self.sequence, "method": method,
                               "params": params}).encode()
            headers["MCP-Method"] = method
            if method == "tools/call":
                headers["MCP-Name"] = params["name"]
        request = urllib.request.Request(self.endpoint, body, headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=320) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            try:
                return error.code, json.load(error)
            except (ValueError, UnicodeError):
                return error.code, {}

    def call(self, name, arguments=None):
        status, envelope = self.request("tools/call", {"name": name, "arguments": arguments or {}})
        check(status == 200 and "result" in envelope, f"{name} transport", envelope)
        result = envelope["result"]
        check(not result.get("isError"), f"{name} operation", result)
        if any(item.get("type") == "image" for item in result.get("content", [])):
            return result
        if result.get("structuredContent") is not None:
            return result["structuredContent"]
        text = next((item.get("text") for item in result.get("content", []) if item.get("type") == "text"), None)
        if text is None:
            return result
        try:
            return json.loads(text)
        except ValueError:
            return text


def read_json(url):
    with urllib.request.urlopen(url, timeout=5) as response:
        return json.load(response)


def eventually(callback, label, timeout=8):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = callback()
            if last:
                return
        except (OSError, ValueError):
            pass
        time.sleep(.05)
    raise AssertionError(f"Timed out waiting for {label}; last={last!r}")


def control(c, action, **fields):
    nonce = str(uuid.uuid4())
    path = Path(c['handshakePath'] + '.control')
    path.write_text(json.dumps({'nonce':nonce,'action':action,**fields}))
    path.chmod(0o600)
    os.kill(c['pid'],signal.SIGUSR1)
    result_path = Path(c['handshakePath'] + '.control-result')
    eventually(lambda: result_path.exists() and json.loads(result_path.read_text()).get('nonce')==nonce,'test process control acknowledgement')
    return json.loads(result_path.read_text())


def failure_and_auth_tests(c, check, eventually):
    client=c['client']
    def failure(name, args):
        status, response=client.request('tools/call',{'name':name,'arguments':args})
        check(status==200 and response.get('result',{}).get('isError') is True,name+' rejects invalid operation',response)
    failure('navigate',{'tabID':c['tab'],'url':'file:///etc/passwd'})
    failure('read_page',{'tabID':str(uuid.uuid4())})
    failure('open_tab',{'url':c['page'],'windowID':str(uuid.uuid4())})
    failure('fill',{'tabID':c['tab'],'selector':'#fixture-readonly','value':'bad'})
    failure('wait_for_text',{'tabID':c['tab'],'text':'never-present-marker','timeout':.1})
    # Independent clients issue concurrent reads, without sharing request IDs.
    def read(_):return Client(client.endpoint,client.token).call('get_tab',{'tabID':c['tab']})
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        check(all(x['tabID']==c['tab'] for x in pool.map(read,range(12))),'concurrent client identity')
    # Normal browsing session is shared by agent-created tabs. Login on one tab,
    # then verify the HttpOnly cookie through the server in a second actual tab.
    client.call('navigate',{'tabID':c['tab'],'url':c['page']})
    client.call('wait_for_element',{'tabID':c['tab'],'selector':'#fixture-login','timeout':8})
    for selector,value in [('#fixture-username','fixture-user'),('#fixture-password','fixture-password')]:
        client.call('fill',{'tabID':c['tab'],'selector':selector,'value':value})
    client.call('submit_form',{'tabID':c['tab'],'selector':'#fixture-login'})
    client.call('wait_for_url',{'tabID':c['tab'],'url':'/authenticated','timeout':8})
    second=client.call('open_tab',{'url':c['page'].split('/?')[0]+'/authenticated','windowID':c['window']})['tabID']
    client.call('wait_for_text',{'tabID':second,'text':'fixture-user','timeout':8})
    check('"authenticated": true' in str(client.call('read_page',{'tabID':second})),'normal session authentication shared')
    control(c,'revoke',tabID=second)
    failure('read_page',{'tabID':second})
    old_token=client.token
    restarted=control(c,'restart')
    check(restarted['token']!=old_token,'credential rotation')
    rotated=Client(restarted['endpoint'],restarted['token'])
    check(rotated.request('ping',token=old_token)[0]==401,'old credential rejected after restart')
    check(rotated.call('list_tabs')==[],'restart revokes all grants')
    print('PASS invalid inputs, timeout, concurrent clients, shared authentication, revocation and rotation',flush=True)


native_order = [
    'list_windows','get_tab','get_tab_state','get_active_tab','select_tab','duplicate_tab','close_tab',
    'get_navigation_history','reload_tab','go_back','go_forward','create_space','list_spaces',
    'select_space','get_current_space','rename_space','move_tab_to_space','get_space','list_space_tabs',
    'pin_tab','set_favourite','create_pinned_folder','list_pinned_folders','list_space_folders',
    'create_space_folder','rename_space_folder','move_tab_to_folder','move_tab','rename_tab',
    'unpin_tab','favourite_tab','unfavourite_tab','get_media_state','get_resource_info',
    'mute_tab','unmute_tab','get_tab_resource_usage','get_tab_media_state','hibernate_tab','wake_tab',
    'add_bookmark','list_bookmarks','create_bookmark','search_bookmarks','update_bookmark',
    'create_bookmark_folder','list_bookmark_folders','move_bookmark','delete_bookmark','remove_bookmark',
    'add_to_reading_list','list_reading_list','open_reading_list_item','remove_reading_list_item','remove_from_reading_list',
    'create_easel','list_easels','get_easel','open_easel','get_easel_contents','add_easel_text','add_easel_link','add_easel_quote',
    'create_boost','list_boosts','get_boost','update_boost','set_boost_enabled','toggle_boost','delete_boost',
    'list_history','search_history','get_history_entry','open_history_entry','list_downloads','cancel_download',
    'get_download','wait_for_download','open_download','reveal_download','delete_download',
    'get_browser_status','get_download_summary','get_active_media_tabs','search_web','delete_space'
]

def main():
    parser = argparse.ArgumentParser()
    for name in ("handshake", "site", "run", "profile", "pid"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--upload-scope", required=True)
    args = parser.parse_args()
    handshake = json.loads(Path(args.handshake).read_text())
    site = json.loads(Path(args.site).read_text())
    check(os.stat(args.handshake).st_mode & 0o077 == 0, "private handshake permissions")
    for key, expected in (("runID", args.run), ("profileID", args.profile), ("pid", int(args.pid))):
        check(handshake[key] == expected, f"isolated process {key}", handshake.get(key))
    client = Client(handshake["endpoint"], handshake["token"])
    status, response = client.request("initialize", {"protocolVersion": client.version,
        "capabilities": {}, "clientInfo": {"name": "astra-e2e", "version": "1"}})
    check(status == 200 and response.get("result", {}).get("protocolVersion") == client.version,
          "legacy negotiation", response)
    status, response = client.request("server/discover", version="2026-07-28")
    check(status == 200 and "2026-07-28" in response.get("result", {}).get("supportedVersions", []),
          "modern discovery", response)
    status, response = client.request("tools/list")
    check(status == 200, "tool discovery", response)
    tools = {item["name"] for item in response["result"]["tools"]}
    check(len(tools) == len(response["result"]["tools"]), "unique tool names")
    check(client.request("ping", token="invalid")[0] == 401, "unauthorized request")
    check(client.request("ping", origin="https://evil.example")[0] == 403, "invalid origin")
    bad_status, bad_response = client.request("ping", version="2099-01-01")
    check(bad_status == 400 and "error" in bad_response, "unsupported protocol", bad_response)
    page = site["url"] + "/?run=" + args.run
    state_url = site["url"] + "/state/" + args.run
    context = {"handshakePath": args.handshake, "pid": int(args.pid), "client": client, "page": page, "state": lambda: read_json(state_url),
               "uploadScope": args.upload_scope, "uploadSHA256": site["downloadSHA256"], "tab": None, "window": handshake["windowID"]}

    def open_tab(c):
        before = c["client"].call("list_tabs")
        opened = c["client"].call("open_tab", {"url": c["page"], "windowID": c["window"]})
        c["tab"] = opened["tabID"]
        check(opened["windowID"] == c["window"], "opened in designated window", opened)
        after = c["client"].call("list_tabs")
        check(any(tab["tabID"] == c["tab"] for tab in after), "opened tab exists", after)
        check(len(after) == len(before) + 1, "exactly one tab created", after)
        eventually(lambda: c["state"]().get("ready"), "real WebKit page load")

    def list_tabs(c):
        tabs = c["client"].call("list_tabs")
        check(any(t["tabID"] == c["tab"] for t in tabs), "listed granted tab", tabs)

    def wait(c):
        c["client"].call("wait", {"tabID": c["tab"], "text": "Astra fixture", "timeout": 8})
        check(c["state"]().get("ready"), "wait page loaded")

    def read_page(c):
        page_text = c["client"].call("read_page", {"tabID": c["tab"]})
        check("Astra fixture" in str(page_text), "read actual fixture", page_text)
        check("secret-sentinel-must-not-leak" not in str(page_text), "password omitted", page_text)

    def snapshot(c):
        result = c["client"].call("snapshot", {"tabID": c["tab"]})
        check("Increment counter" in str(result), "semantic button visible", result)
        check("secret-sentinel-must-not-leak" not in str(result), "password omitted", result)

    def action(c, name, args, state_key, expected):
        c["client"].call(name, {"tabID": c["tab"], **args})
        eventually(lambda: c["state"]().get(state_key) == expected,
                   f"{name}: expected fixture {state_key}={expected!r}")

    def click(c):
        action(c, "click", {"selector": "#fixture-click"}, "clicks", 1)

    def fill(c):
        action(c, "fill", {"selector": "#fixture-text", "value": "Astra filled"}, "text", "Astra filled")

    def select_option(c):
        action(c, "select_option", {"selector": "#fixture-select", "value": "two"}, "select", "two")

    def navigate(c):
        for fragment in ("#navigated", "#second-fragment", "", "#navigated"):
            destination = c["page"] + fragment
            c["client"].call("navigate", {"tabID": c["tab"], "url": destination})
            eventually(lambda: c["state"]().get("route") == fragment, "SPA navigation to " + destination)
            ready = c["client"].call("wait_for_load_state", {"tabID": c["tab"], "state": "complete", "timeout": 8})
            check(ready.get("matched") is True, "fragment navigation restores document readiness", ready)
            result = c["client"].call("evaluate_javascript", {"tabID": c["tab"], "contentWorld": "page",
                "expression": "({url:location.href,text:document.querySelector('#fixture-text').value})"})
            value = result.get("result", result)
            check(value == {"url": destination, "text": "Astra filled"}, "fragment navigation preserves the live document", value)

    cases = {"open_tab": open_tab, "list_tabs": list_tabs, "wait": wait,
             "read_page": read_page, "snapshot": snapshot, "click": click,
             "fill": fill, "select_option": select_option, "navigate": navigate}
    register_page(cases, context, check, eventually)
    context["control"] = lambda action, **fields: control(context, action, **fields)
    register_native(cases, context, check, eventually)
    register_extended(cases, context, check, eventually)
    missing = sorted(tools - cases.keys())
    check(not missing, "every discovered tool requires an executable postcondition test", missing)
    order = ["open_tab", "list_tabs", "wait", "read_page", "snapshot", "click", "fill", "select_option", "navigate"]
    order += [name for name in cases if name not in order and name not in native_order]
    order += native_order
    for name in order:
        check(name in tools, "required legacy tool is exposed", name)
        try:
            started = time.monotonic()
            cases[name](context)
        except Exception as error:
            raise AssertionError(f"Tool {name} failed against {page}: {error}") from error
        print(f"PASS {name} duration_ms={(time.monotonic()-started)*1000:.2f}", flush=True)
    failure_and_auth_tests(context, check, eventually)
    print(f"PASS {len(tools)} discovered tool cases; supported operations assert effects, explicit limitations assert honest output", flush=True)


if __name__ == "__main__":
    main()
