import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

// Execute the exact script embedded in FaviconStore, not a separately
// maintained copy that could accidentally diverge from production.
const source = readFileSync('astra/Storage/FaviconStore.swift', 'utf8');
const marker = 'private static let observationScript = """';
const start = source.indexOf(marker);
assert.ok(start >= 0, 'Favicon observation script must exist');
const bodyStart = start + marker.length;
const bodyEnd = source.indexOf('"""', bodyStart);
assert.ok(bodyEnd > bodyStart);
const script = source.slice(bodyStart, bodyEnd);

let callback;
let observerCount = 0;
const timers = [];
let posts = 0;
const listeners = new Map();
const document = {
    head: {},
    hidden: false,
    addEventListener(name, listener) { listeners.set(name, listener); }
};
class MutationObserver {
    constructor(handler) { callback = handler; observerCount++; }
    observe(node) { assert.equal(node, document.head); }
}
const context = {
    document, MutationObserver,
    setTimeout(handler) { timers.push(handler); return timers.length; },
    window: { webkit: { messageHandlers: { faviconChanged: {
        postMessage() { posts++; }
    } } } }
};
const fireIconChange = () => callback([{
    type: 'attributes',
    attributeName: 'href',
    target: { tagName: 'LINK', matches: () => true }
}]);
function flushTimers() {
    while (timers.length) timers.shift()();
}

runInNewContext(script, context);
runInNewContext(script, context);
assert.equal(observerCount, 1, 'Only one observer may exist per document');
fireIconChange();
fireIconChange();
fireIconChange();
assert.equal(timers.length, 1, 'Rapid icon mutations must be coalesced');
flushTimers();
assert.equal(posts, 1);
callback([{ type: 'childList', addedNodes: [], removedNodes: [] }]);
assert.equal(timers.length, 0, 'Unrelated DOM changes must not trigger work');

document.hidden = true;
fireIconChange();
fireIconChange();
assert.equal(timers.length, 0, 'Hidden pages must not schedule messages');
document.hidden = false;
listeners.get('visibilitychange')();
assert.equal(timers.length, 1);
flushTimers();
assert.equal(posts, 2, 'Hidden mutations must be delivered once upon visibility');

fireIconChange();
document.hidden = true;
flushTimers();
assert.equal(posts, 2, 'Pending messages must not fire after hiding');
document.hidden = false;
listeners.get('visibilitychange')();
flushTimers();
assert.equal(posts, 3);
console.log('Favicon observer lifecycle checks passed');
