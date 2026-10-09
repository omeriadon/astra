import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const manager = readFileSync(new URL('../astra/Models/Core/BrowserHibernationManager.swift', import.meta.url), 'utf8');
const tab = readFileSync(new URL('../astra/Models/Tabs/BrowserTab.swift', import.meta.url), 'utf8');
const appDelegate = readFileSync(new URL('../astra/App/AppDelegate.swift', import.meta.url), 'utf8');

assert.match(manager, /30 \* 60/);
assert.match(manager, /5 \* 60/);
assert.match(manager, /lastInteractionAt/);
assert.match(manager, /isVisible/);
assert.match(manager, /isPinned/);
assert.match(manager, /tab\.canHibernate/);
assert.match(manager, /reclaimSequentially/);
assert.match(manager, /max\(seconds, 60\)/);
assert.match(manager, /tab\.peeks\.isEmpty/);
assert.match(manager, /activeProgress == nil/);
assert.match(manager, /webViewIfLoaded\?\.window == nil/);
assert.match(tab, /func markInteraction\(\)/);
assert.match(appDelegate, /handleMemoryPressure\(level\)/);
assert.match(appDelegate, /\[\.normal, \.warning, \.critical\]/);
console.log('Automatic hibernation policy checks passed');
