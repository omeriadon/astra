import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const delegate = readFileSync('astra/App/AppDelegate.swift', 'utf8');
const mini = readFileSync('astra/UI/Shell/MiniAstraWindowController.swift', 'utf8');

function between(source, begin, end) {
  const start = source.indexOf(begin);
  const stop = source.indexOf(end, start + begin.length);
  assert(start >= 0 && stop > start, `Could not find ${begin}`);
  return source.slice(start, stop);
}

const urlHandler = between(
  delegate,
  'private func openAfterStartupRestoration(',
  'private func finishStartupWindowRestoration()'
);
assert.match(urlHandler, /restoreExternalFocusForMiniAstra\(force: wasQueuedAtStartup\)/);
assert.match(urlHandler, /openMiniAstra\(url: url, floatsOverSourceApplication: true\)/);
assert.doesNotMatch(urlHandler, /NSApp\.activate\(\)/);
assert.match(urlHandler, /\} else \{\s*open\(url\)/);

const startup = between(
  delegate,
  'func applicationDidFinishLaunching(',
  'private func scheduleDeferredStartupServices('
);
assert.match(startup, /let launchIntoMini = Defaults\[\.miniAstraEnabled\] && !queuedStartupURLs\.isEmpty/);
assert.match(startup, /if launchIntoMini \{\s*foreground\.window\.orderBack\(nil\)\s*\} else \{\s*foreground\.showWindow\(\)\s*NSApp\.activate\(\)/);

const restoration = between(
  delegate,
  'private func finishStartupWindowRestoration()',
  'func requestQuit()'
);
assert.match(restoration, /shouldReopenAfterStartup && !openingQueuedMini/);
assert.match(restoration, /openAfterStartupRestoration\(url, wasQueuedAtStartup: true\)/);

const focus = between(
  delegate,
  'private func restoreExternalFocusForMiniAstra(',
  '@objc private func applicationWillSleep('
);
assert.match(focus, /!application\.isTerminated/);
assert.match(focus, /NSApp\.isActive/);
assert.match(focus, /BrowserLog\.clock\(\) - lastActivationUptime < 2/);
assert.match(focus, /NSApp\.yieldActivation\(to: application\)/);

assert.match(mini, /\.nonactivatingPanel/);
assert.match(mini, /func windowDidResignKey\(_: Notification\) \{[\s\S]*?window\.level = \.normal/);
console.log('Mini Astra external-link activation regression checks passed');
