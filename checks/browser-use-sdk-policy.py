#!/usr/bin/env python3
"""Compatible SDK range, reproducible resolution, and optional update discovery."""
import argparse
import json
import re
import urllib.request
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--check-latest', action='store_true', help='query the upstream stable release for scheduled update detection')
args = parser.parse_args()
project = Path('astra.xcodeproj/project.xcproj').read_text()
start = project.index('"repository": "https://github.com/modelcontextprotocol/swift-sdk"')
block = project[start:project.index('\n    }, {', start)]
match = re.search(r'"up-to-next-minor-version": "([0-9.]+)"', block)
assert match, 'SDK must use an explicit compatible pre-1.0 minor range'
minimum = match.group(1)
lock = next(Path('astra.xcodeproj').rglob('Package.resolved'))
pins = json.loads(lock.read_text())['pins']
pin = next(p for p in pins if p['identity'] == 'swift-sdk')
resolved = pin['state'].get('version')
assert resolved and len(pin['state'].get('revision', '')) == 40, 'SDK exact resolution must be reproducible'
assert resolved.split('.')[:2] == minimum.split('.')[:2] and tuple(map(int, resolved.split('.'))) >= tuple(map(int, minimum.split('.'))), 'resolved SDK must be within the reviewed compatible minor range'
print(f'PASS swift-sdk minimum {minimum}, resolved {resolved}; lockfile is reproducible')

if args.check_latest:
    request = urllib.request.Request('https://api.github.com/repos/modelcontextprotocol/swift-sdk/releases/latest', headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'Astra-SDK-policy-check'})
    with urllib.request.urlopen(request, timeout=15) as response:
        latest = json.load(response).get('tag_name', '').removeprefix('v')
    assert re.fullmatch(r'\d+\.\d+\.\d+', latest), f'unexpected latest stable SDK version: {latest!r}'
    print(f'Upstream latest stable: {latest}; reviewed minimum: {minimum}; resolved: {resolved}')
    if tuple(map(int, latest.split('.'))) > tuple(map(int, resolved.split('.'))):
        print('::notice title=Swift SDK update available::Review MCP protocol compatibility, update the package pin, and open a normal PR.')
        summary = Path(__import__('os').environ.get('GITHUB_STEP_SUMMARY', '/dev/null'))
        with summary.open('a') as output:
            output.write(f'### Swift MCP SDK update available\n\nLatest stable is `{latest}`; Astra currently resolves `{resolved}` (minimum `{minimum}`). Review compatibility and update through a normal PR.\n')
