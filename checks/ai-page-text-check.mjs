import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../astra/AI/BrowserAIPageText.swift', import.meta.url), 'utf8');
const script = source.match(/static let extractionScript = #"""([\s\S]*?)"""#/)[1];
const ownerDocument = { defaultView: { getComputedStyle: node => ({ display: 'block', visibility: 'visible', contentVisibility: 'visible', opacity: '1', ...node.style }) } };
const text = value => ({ nodeType: 3, nodeValue: value });
function element(tagName, children = [], extra = {}) {
  return { nodeType: 1, tagName, childNodes: children, ownerDocument, getAttribute: name => extra.attributes?.[name], closest: () => null, ...extra };
}
const shadow = { nodeType: 11, childNodes: [element('P', [text('Shadow content')])] };
const document = {
  title: '  Specific Page Title  ',
  body: element('BODY', [
    element('NAV', [text('Home')]),
    element('H1', [text('A specific heading')]),
    element('P', [text('Meaningful   text'), text('with extra whitespace')]),
    element('SCRIPT', [text('Secret script instructions')]),
    element('STYLE', [text('Raw CSS')]),
    element('P', [text('Hidden text')], { hidden: true }),
    element('P', [text('Invisible text')], { style: { display: 'none' } }),
    element('P', [text('Aria hidden')], { attributes: { 'aria-hidden': 'true' } }),
    element('TEXTAREA', [text('Unsubmitted private draft')]),
    element('DIV', [text('Editable draft')], { isContentEditable: true }),
    element('DIV', [], { shadowRoot: shadow }),
    element('IFRAME', [], { contentDocument: { body: element('BODY', [element('P', [text('Frame content')])]) } }),
    element('P', [text('Repeated fact')]),
    element('P', [text('Repeated fact')]),
  ]),
};
const page = new Function('document', 'location', script)(document, { href: 'https://example.com/article' });
assert.equal(page.title, 'Specific Page Title');
assert.equal(page.url, 'https://example.com/article');
assert.ok(page.text.includes('A specific heading\nMeaningful text with extra whitespace'));
assert.ok(page.text.includes('Shadow content'));
assert.ok(page.text.includes('Frame content'));
assert.equal(page.text.match(/Repeated fact/g).length, 2, 'Repeated meaningful content is not discarded');
for (const excluded of ['Secret', 'Raw CSS', 'Hidden text', 'Invisible', 'Aria hidden', 'private draft', 'Editable']) {
  assert.ok(!page.text.includes(excluded), excluded);
}
assert.ok(!page.text.includes('<'), 'No raw HTML is serialized');
console.log('Readable page extraction, hidden/form exclusions, shadow roots, frames, and repeated facts passed');
