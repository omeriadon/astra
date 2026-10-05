import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../astra/Web/Navigation/BrowserController.swift', import.meta.url), 'utf8');
const script = source.match(/private static let findScript = #"""([\s\S]*?)"""#/)[1];
const node = { textContent: 'alpha Beta alpha beta', parentElement: { closest: () => null, getClientRects: () => [1] } };
let selected;
const window = {
  getSelection: () => ({ removeAllRanges() { selected = null; }, addRange(range) { selected = range; } }),
  scrollBy() {},
};
const document = {
  body: {},
  createTreeWalker() {
    let pending = true;
    return { nextNode() { if (!pending) return null; pending = false; return node; } };
  },
  createRange: () => ({
    setStart(node, offset) { this.start = offset; },
    setEnd(node, offset) { this.end = offset; },
    getBoundingClientRect: () => ({ top: 0, bottom: 10 }),
  }),
};
function find(query, backwards = false) {
  return new Function('document', 'window', 'NodeFilter', 'query', 'backwards', 'innerHeight', script)(
    document, window, { SHOW_TEXT: 4 }, query, backwards, 100,
  );
}
assert.deepEqual(find('alpha'), { count: 2, index: 1 });
assert.equal(selected.start, 0);
assert.deepEqual(find('alpha'), { count: 2, index: 2 });
assert.equal(selected.start, 11);
assert.deepEqual(find('alpha'), { count: 2, index: 1 });
assert.deepEqual(find('alpha', true), { count: 2, index: 2 });
assert.deepEqual(find('BETA'), { count: 2, index: 1 });
node.textContent = 'İ alpha Alpha';
assert.deepEqual(find('alpha'), { count: 2, index: 1 });
assert.equal(selected.start, 2);
assert.deepEqual(find('alpha'), { count: 2, index: 2 });
assert.equal(selected.start, 8);
node.textContent = 'a+ a+';
assert.deepEqual(find('a+'), { count: 2, index: 1 });
assert.deepEqual(find('missing'), { count: 0, index: 0 });
assert.deepEqual(find(''), { count: 0, index: 0 });
console.log('Find count, current match, wrap and reset production-script checks passed');
