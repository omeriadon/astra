// Run: bun --install=fallback checks/reader-mode-check.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';

const directory = new URL('../astra/Web/Reader/', import.meta.url);
const source = ['Readability.js', 'Readability-readerable.js', 'Reader.js']
    .map(name => readFileSync(new URL(name, directory), 'utf8')).join('\n');
const paragraph = 'A reader should preserve the article paragraphs, headings, and useful links while removing page controls. '.repeat(8);
const original = `<html><head><title>Reader fixture</title></head><body><nav>Navigation</nav><article><h1>Reader fixture</h1>
    <p>${paragraph}</p><h2>Details</h2><p>${paragraph}</p>
    <p><a href="/related">Related article</a><a href="javascript:alert(1)">Unsafe link</a>
    <a href="https://user:password@example.org/">Credentials</a></p>
    <img src="/photo.jpg" alt="Article photo" onerror="alert(1)"><img alt="No URL">
    <iframe src="https://www.youtube.com/embed/example"></iframe><script>alert(1)</script></article></body></html>`;
function page(html) {
    const dom = new JSDOM(html, { url: 'https://example.org/article' });
    const messages = [];
    dom.window.webkit = { messageHandlers: { readerAvailabilityChanged: { postMessage: value => messages.push(value) } } };
    const run = new Function('document', 'window', 'globalThis', 'location', 'MutationObserver',
        'addEventListener', 'setTimeout', 'clearTimeout', source);
    run(dom.window.document, dom.window, dom.window, dom.window.location, dom.window.MutationObserver,
        dom.window.addEventListener.bind(dom.window), dom.window.setTimeout.bind(dom.window), dom.window.clearTimeout.bind(dom.window));
    return { dom, messages };
}
const { dom, messages } = page(original);
const before = dom.window.document.documentElement.outerHTML;
dom.window.astraProbeReader(true);
assert.equal(messages.at(-1).available, true);
const article = dom.window.astraExtractReader();
assert.ok(article);
assert.ok(article.content.includes('Details'));
assert.ok(article.content.includes('https://example.org/related'));
assert.ok(article.content.includes('https://example.org/photo.jpg'));
assert.ok(article.content.includes('alt="Article photo"'));
assert.ok(!/<script|<iframe|onerror|javascript:|user:password|src="null"/.test(article.content));
assert.equal(dom.window.document.documentElement.outerHTML, before, 'extraction must preserve the live page');
dom.window.history.pushState({}, '', '/next');
dom.window.astraProbeReader(true);
assert.equal(messages.at(-1).url, 'https://example.org/next');
dom.window.close();
const short = page('<html><body><h1>Home</h1><a href="/news">News</a></body></html>');
short.dom.window.astraProbeReader(true);
assert.equal(short.messages.at(-1).available, false);
assert.equal(short.dom.window.astraExtractReader(), null);
short.dom.window.close();
console.log('Reader detection, extraction, sanitization, page preservation, and route checks passed.');
