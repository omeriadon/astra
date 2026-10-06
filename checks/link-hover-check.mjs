import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../astra/Web/Navigation/BrowserController.swift', import.meta.url), 'utf8');
const script = source.match(/private static let linkHoverScript = """([\s\S]*?)"""/)[1];
const events = new Map();
const reports = [];
const document = { addEventListener: (name, handler) => events.set(name, handler), elementFromPoint: () => null };
const window = {
  addEventListener: (name, handler) => events.set(name, handler),
  webkit: { messageHandlers: { linkHoverChanged: { postMessage: value => reports.push(value) } } },
};
new Function('document', 'window', 'innerWidth', 'innerHeight', script)(document, window, 1000, 800);
const attributes = new Map();
const anchor = { matches: () => true, getAttribute: () => '../target', baseURI: 'https://example.com/page/', removeAttribute: key => attributes.delete(key), setAttribute: (key, value) => attributes.set(key, value), getBoundingClientRect: () => ({left: 100, top: 200, width: 80, height: 20}) };
const hover = (x, y) => events.get('pointermove')({ clientX: x, clientY: y, composedPath: () => [{}, anchor] });
hover(500, 300);
assert.equal(reports.at(-1).href, 'https://example.com/target');
assert.equal(reports.at(-1).trailing, false);
assert.equal(reports.at(-1).width, 80);
hover(501, 300);
assert.equal(reports.length, 1, 'Repeated moves on the same link do not update SwiftUI');
hover(10, 790);
assert.equal(reports.at(-1).trailing, true);
events.get('mouseleave')();
assert.equal(reports.at(-1).href, '');
hover(500, 300);
events.get('blur')();
assert.equal(reports.at(-1).href, '');
hover(500, 300);
events.get('scroll')();
assert.equal(reports.at(-1).href, '');
const invalid = { ...anchor, getAttribute: () => 'https://%' };
events.get('pointermove')({ clientX: 500, clientY: 300, composedPath: () => [invalid] });
assert.equal(reports.at(-1).href, '');
document.getElementById = () => ({});
globalThis.astraAIHoverEnabled = true;
hover(500, 300);
assert.equal(attributes.has('data-astra-ai-preview-hover'), true);
events.get('mouseleave')();
assert.equal(attributes.has('data-astra-ai-preview-hover'), false);
console.log('Link hover URL, deduplication, corner avoidance and clearing checks passed');
