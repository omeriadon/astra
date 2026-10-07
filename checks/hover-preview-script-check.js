// Run: bun checks/hover-preview-script-check.js
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../astra/Web/Navigation/BrowserController.swift", import.meta.url), "utf8");
const script = source.match(/private static let linkHoverScript = """\n([\s\S]*?)\n\t"""/)[1];
const documentEvents = new Map();
const windowEvents = new Map();
const messages = [];
const attributes = new Map();
const link = {
    baseURI: "https://example.com",
    getAttribute: () => "/article",
    matches: () => true,
    setAttribute: (name, value) => attributes.set(name, value),
    removeAttribute: name => attributes.delete(name),
    getBoundingClientRect: () => ({ left: 10, top: 20, width: 60, height: 20 }),
};
let style;
const context = {
    URL,
    innerWidth: 1000,
    innerHeight: 800,
    document: {
        getElementById: () => style,
        createElement: () => ({}),
        head: { append: value => { style = value; } },
        addEventListener: (name, handler) => documentEvents.set(name, handler),
        elementFromPoint: () => ({ closest: () => link }),
    },
    window: {
        webkit: { messageHandlers: { linkHoverChanged: { postMessage: value => messages.push(value) } } },
        addEventListener: (name, handler) => windowEvents.set(name, handler),
    },
};
runInNewContext(script, context);
documentEvents.get("pointermove")({ clientX: 30, clientY: 25, shiftKey: false, composedPath: () => [link] });
assert.equal(messages.at(-1).href, "https://example.com/article");
assert.equal(messages.at(-1).width, 60);
documentEvents.get("keydown")({ shiftKey: true });
assert.equal(messages.at(-1).shift, true);
documentEvents.get("keyup")({ shiftKey: false });
assert.equal(messages.at(-1).shift, false);
context.astraSetAIHover(true, true);
assert.equal(attributes.get("data-astra-ai-preview-hover"), "thinking");
assert.match(style.textContent, /@keyframes astra-ai-thinking/);
assert.match(style.textContent, /prefers-reduced-motion/);
windowEvents.get("blur")();
assert.equal(messages.at(-1).href, "");
assert.equal(attributes.get("data-astra-ai-preview-hover"), "thinking");
context.astraSetAIHover(true, false);
assert.equal(attributes.get("data-astra-ai-preview-hover"), "");
context.astraSetAIHover(false, false);
assert.equal(attributes.has("data-astra-ai-preview-hover"), false);
documentEvents.get("scroll")();
assert.equal(messages.some(message => message.dismissPreview === true), true);
console.log("Hover preview script checks passed");
