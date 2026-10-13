import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

// Extract the actual WKUserScript templates rather than duplicating the runtime.
const source = fs.readFileSync("astra/Web/Boosts/BrowserBoost.swift", "utf8");
const templates = [...source.matchAll(/return Self\.scriptMarker \+ """\n([\s\S]*?)\n        """/g)]
  .map((match) => match[1]);
assert.equal(templates.length, 2, "Boost JavaScript and CSS templates must exist");
const [javascriptTemplate, cssTemplate] = templates;

function makePage(hostname, protocol = "https:") {
  const styles = [];
  const root = {
    appendChild(style) {
      style.isConnected = true;
      styles.push(style);
    },
  };
  const document = {
    documentElement: root,
    createElement(tagName) {
      assert.equal(tagName, "style");
      return {
        textContent: "",
        isConnected: false,
        setAttribute() {},
        remove() { this.isConnected = false; },
      };
    },
    addEventListener() {},
  };
  const window = {};
  const context = vm.createContext({
    window,
    document,
    location: { hostname, protocol },
    console,
  });
  return { context, styles, window };
}

function applyStyles(page, boosts) {
  const script = cssTemplate.replaceAll("\\(json)", JSON.stringify(boosts));
  assert.doesNotMatch(script, /\\\(json\)/);
  vm.runInContext(script, page.context);
}

function applyJavaScript(page, domain, id, signature, code) {
  const script = javascriptTemplate
    .replaceAll("\\(encodedHost)", JSON.stringify(domain))
    .replaceAll("\\(id)", id)
    .replaceAll("\\(boost.javascript.hashValue)", String(signature))
    .replaceAll("\\(source)", code);
  assert.doesNotMatch(script, /\\\([a-zA-Z]/);
  vm.runInContext(script, page.context);
}

// CSS targets exact domain and subdomains but not lookalike domains.
for (const domain of ["example.com", "docs.example.com"]) {
  const page = makePage(domain);
  applyStyles(page, [{ id: "first", domain: "example.com", css: "body{color:red}" }]);
  assert.equal(page.window.__astraBoostState.first.style.textContent, "body{color:red}");
  applyStyles(page, [{ id: "first", domain: "example.com", css: "body{color:blue}" }]);
  assert.equal(page.window.__astraBoostState.first.style.textContent, "body{color:blue}");
  applyStyles(page, []); // delete, disable or domain change
  assert.equal(page.window.__astraBoostState.first, undefined);
  assert.equal(page.styles[0].isConnected, false);
}
for (const domain of ["notexample.com", "attackerexample.com"]) {
  const page = makePage(domain);
  applyStyles(page, [{ id: "first", domain: "example.com", css: "body{color:red}" }]);
  assert.equal(page.window.__astraBoostState, undefined);
}
const global = makePage("unrelated.org");
applyStyles(global, [{ id: "global", domain: null, css: "body{display:grid}" }]);
assert.equal(global.window.__astraBoostState.global.style.textContent, "body{display:grid}");

// Script executes once per version, updates without navigating, and respects
// domain restrictions. The generated source contains executable JS, not eval().
assert.doesNotMatch(javascriptTemplate, /\beval\s*\(/);
const page = makePage("docs.example.com");
const snippet = "window.count = (window.count || 0) + 1;";
applyStyles(page, [{ id: "example", domain: "example.com", css: "" }]);
applyJavaScript(page, "example.com", "example", "v1", snippet);
applyJavaScript(page, "example.com", "example", "v1", snippet);
assert.equal(page.window.count, 1);
applyJavaScript(page, "example.com", "example", "v2", snippet);
assert.equal(page.window.count, 2);
applyStyles(page, []);
applyStyles(page, [{ id: "example", domain: "example.com", css: "" }]);
applyJavaScript(page, "example.com", "example", "v2", snippet);
assert.equal(page.window.count, 3);

const offsite = makePage("offsite.org");
applyJavaScript(offsite, "example.com", "example", "v1", snippet);
assert.equal(offsite.window.count, undefined);

const local = makePage("example.com", "file:");
applyStyles(local, [{ id: "global", domain: null, css: "body{display:none}" }]);
applyJavaScript(local, "", "global", "v1", snippet);
assert.equal(local.window.count, undefined);
assert.equal(local.window.__astraBoostState, undefined);

console.log("Boosts runtime: CSS hot-swap/removal, domain scoping, global scope, JS versioning and private URL guards passed");
