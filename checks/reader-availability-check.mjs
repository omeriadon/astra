import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const source = readFileSync('astra/Web/Reader/Reader.js', 'utf8');
const parse = source.indexOf('(() => {');
const script = source.slice(parse);

const textNode = value => ({ nodeType: 3, textContent: value });
const makeContext = parseResult => {
    const listeners = new Map();
    const timers = [];
    let mutationHandler;
    let posts = [];
    const makeElement = (name = 'article') => {
        const children = [];
        return {
            nodeType: 1,
            localName: name,
            childNodes: [],
            append(node) { children.push(node); },
            appendChild(node) { children.push(node); },
            getAttribute() { return null; },
            setAttribute() {},
            get innerHTML() { return children.length ? 'x'.repeat(600) : ''; }
        };
    };
    const document = {
        body: {},
        baseURI: 'https://example.test/article',
        title: 'Article',
        cloneNode() { return document; },
        createTextNode: textNode,
        createElement: makeElement,
        getElementsByTagName() { return [{}, {}]; },
        addEventListener(name, handler) { listeners.set(name, handler); }
    };
    class MutationObserver {
        constructor(handler) { mutationHandler = handler; }
        observe() {}
    }
    const context = {
        document,
        location: { href: 'https://example.test/article', protocol: 'https:' },
        Readability: class { parse() { return parseResult(); } },
        MutationObserver,
        setTimeout(handler) { timers.push(handler); return timers.length; },
        clearTimeout() {},
        addEventListener(name, handler) { listeners.set(name, handler); },
        window: { webkit: { messageHandlers: {
            readerAvailabilityChanged: { postMessage(value) { posts.push(value); } }
        } } }
    };
    runInNewContext(script, context);
    const flush = () => { while (timers.length) timers.shift()(); };
    return { context, flush, mutate: () => mutationHandler(), posts };
};

const unavailable = makeContext(() => null);
unavailable.flush();
assert.equal(unavailable.posts.at(-1).available, false);

const empty = makeContext(() => ({
    title: 'Empty', byline: '', length: 600,
    content: { nodeType: 1, localName: 'script', childNodes: [], getAttribute() { return null; } }
}));
empty.flush();
assert.equal(empty.posts.at(-1).available, false);

let shouldParse = true;
    const available = makeContext(() => shouldParse ? {
    title: 'Article', byline: '', length: 600,
    content: { nodeType: 1, localName: 'p', childNodes: [textNode('content')], getAttribute() { return null; } }
} : null);
available.flush();
assert.equal(available.posts.at(-1).available, true);
shouldParse = false;
available.mutate();
assert.ok(available.context.astraExtractReader(), 'A proven article remains usable before debounce');
available.context.location.href = 'https://example.test/other';
assert.equal(available.context.astraExtractReader(), null, 'A cached article cannot cross URLs');
available.context.location.href = 'https://example.test/article';
available.flush();
assert.equal(available.posts.at(-1).available, false);
console.log('Reader availability checks passed');
