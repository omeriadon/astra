import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// Execute the exact WebKit programs with a small fixture DOM. Native WebKit
// integration (content rules, ephemeral store and peek presentation) needs macOS.
const source = fs.readFileSync('astra/AI/BrowserWebsiteAugment.swift', 'utf8');
function script(name) {
  const match = source.match(new RegExp('static let ' + name + ' = #"""\\n([\\s\\S]*?)\\n[\\t ]*"""#'));
  assert.ok(match, name);
  return match[1];
}
const transform = script('transformScript');
const finalize = script('finalizeScript');
for (const name of ['captureScript', 'structureScript', 'transformScript', 'finalizeScript']) {
  new vm.Script('(function(){' + script(name) + '})');
}
class Element {
  constructor(tag, text = '', attrs = {}) { this.tag = tag; this.textContent = text; this.attrs = {...attrs}; this.isConnected = true; this.children = []; }
  set httpEquiv(v) { this.attrs['http-equiv'] = v; }
  set content(v) { this.attrs.content = v; }
  set name(v) { this.attrs.name = v; }
  set href(v) { this.attrs.href = v; }
  get attributes() { return Object.entries(this.attrs).map(([name,value]) => ({name,value})); }
  get outerHTML() { return `<${this.tag}${Object.entries(this.attrs).map(([k,v]) => ` ${k}="${v}"`).join('')}>${this.children.map(n => n.outerHTML).join('')}${this.textContent}</${this.tag}>`; }
  hasAttribute(k) { return k in this.attrs; }
  getAttribute(k) { return this.attrs[k] ?? null; }
  setAttribute(k,v) { this.attrs[k] = v; }
  matches(selector) { return selector.split(',').some(s => s === this.tag || s === '[style]' && this.hasAttribute('style') || s === 'link[rel~="stylesheet"]' && this.tag === 'link' && this.attrs.rel === 'stylesheet'); }
  querySelectorAll(selector) { return this.children.filter(n => n.isConnected).flatMap(n => [...(selector === '*' || n.matches(selector) ? [n] : []), ...n.querySelectorAll(selector)]); }
  querySelector(s) { return this.querySelectorAll(s)[0] ?? null; }
  remove() { this.isConnected = false; }
  prepend(n) { this.children.unshift(n); n.parentElement = this; }
}
function page(rows = ['Apple red', 'Pear green', 'Apple gold']) {
  const style = new Element('style', 'li{color:red}');
  const elements = rows.map(text => new Element('li', text, {class:'existing'}));
  const doc = {
    head: new Element('head'), body: new Element('body'),
    querySelectorAll(s) { return [this.documentElement,...this.documentElement.querySelectorAll('*')].filter(n => n.isConnected && (s === '*' || n.matches(s))); },
    querySelector(s) { return this.querySelectorAll(s)[0] ?? null; },
    createElement(tag) { return new Element(tag); },
  };
  doc.head.children = [style]; doc.body.children = elements;
  doc.documentElement = new Element('html'); doc.documentElement.children = [doc.head,doc.body];
  for (const parent of [doc.documentElement,doc.head,doc.body]) for (const child of parent.children) child.parentElement = parent;
  // Serialized output only: disconnected nodes are omitted, like native DOM.
  for (const parent of [doc.documentElement,doc.head,doc.body]) Object.defineProperty(parent,'outerHTML',{get(){return `<${this.tag}>${this.children.filter(n=>n.isConnected).map(n=>n.outerHTML).join('')}</${this.tag}>`;}});
  return {doc,elements,style};
}
function run(ops, fixture = page()) {
  const context = {html:'original',source:'https://example.com/articles/',operations:ops,URL,DOMParser:class{parseFromString(){return fixture.doc;}}};
  return {result: vm.runInNewContext('(function(){'+transform+'})()',context),...fixture};
}
assert.equal(run([{action:'filter',selector:'li',contains:'apple'}]).elements.filter(n=>n.isConnected).length,2);
const longList = page(Array.from({length: 838}, (_, i) => i === 700 ? 'Philosophy' : 'Other unit'));
assert.equal(run([{action:'filter',selector:'li',contains:'philosophy'}], longList).elements.filter(n=>n.isConnected).length,1);
assert.equal(longList.elements[700].isConnected, true);
assert.equal(run([{action:'filter',selector:'li',contains:'APPLE',exclude:true}]).elements.filter(n=>n.isConnected).length,1);
assert.equal(run([{action:'remove',selector:'li'}]).elements.filter(n=>n.isConnected).length,0);
assert.ok(run([{action:'replace',selector:'li',text:'Updated'}]).elements.every(n=>n.textContent==='Updated'));
assert.ok(run([{action:'javascript',code:"document.querySelector('li').textContent = 'Changed';"}]).result.includes('Changed'));
assert.throws(()=>run([{action:'javascript',code:"document.querySelector('li').setAttribute('style','display:none');"}]), /CSS/);
assert.throws(()=>run([{action:'javascript',code:"document.querySelector('style').textContent = 'body{display:none}';"}]), /CSS/);
assert.throws(()=>run([{action:'javascript',code:"document.querySelector('li').setAttribute('onclick','fetch(123)');"}]), /Active/);
assert.throws(()=>run([{action:'javascript',code:"document.querySelector('li').setAttribute('href','javascript:alert(1)');"}]), /Unsafe/);
assert.throws(()=>run([{action:'unknown',selector:'li'}]), /Unknown/);
assert.throws(()=>run([{action:'remove',selector:'missing'}]), /matched no/);
assert.throws(()=>run([{action:'filter',selector:'li'}]), /contains/);

function validate(edited, original = page()) {
  return vm.runInNewContext('(function(){'+finalize+'})()',{
    html:'original',result:'edited',source:'https://example.com/articles/',URL,
    DOMParser:class{parseFromString(value){return value === 'original' ? original.doc : edited.doc;}},
  });
}
assert.ok(validate(page()).includes('Content-Security-Policy'));
const forged = page(); forged.style.textContent = 'body{display:none}';
assert.throws(()=>validate(forged),/CSS/);
const active = page(); active.doc.body.children.push(new Element('script','fetch("/mutate")'));
assert.throws(()=>validate(active), /Active/);
const styled = page(); styled.elements[0].setAttribute('style','color:red');
assert.throws(()=>validate(styled), /CSS/);
const unsafe = page(); unsafe.elements[0].setAttribute('href','javascript:alert(1)');
assert.throws(()=>validate(unsafe), /Unsafe/);
assert.match(source,/websiteDataStore = \.nonPersistent\(\)/);
assert.match(source,/"type":"block"/);
assert.match(source,/allowsContentJavaScript = false/);
assert.match(source,/\.world\(name: "AstraAugmentValidation"\)/);
assert.match(source,/Task\.sleep\(for: \.seconds\(12\)\)/);
// Browser.configure(peek) can replace navigationIntercept; the snapshot policy
// must survive that callback wiring and run before external or popup handlers.
const controller = fs.readFileSync('astra/Web/Navigation/BrowserController.swift', 'utf8');
assert.match(source, /controller\.snapshotNavigationOnly = true/);
assert.match(controller, /var snapshotNavigationOnly = false/);
function guardedBefore(start, boundary, guard, sideEffect) {
  const body = controller.slice(controller.indexOf(start), controller.indexOf(boundary, controller.indexOf(start)));
  assert.ok(body.includes(guard), start + ' must enforce snapshot navigation');
  assert.ok(body.indexOf(guard) < body.indexOf(sideEffect), start + ' must guard before side effects');
}
guardedBefore('private func load(_ url: URL,', 'func loadWebArchive', '!snapshotNavigationOnly', 'handleExternalLink(');
guardedBefore('func navigate(_ request:', 'func goBack', '!snapshotNavigationOnly', 'historyVisitPolicy.userInitiatedNavigation()');
guardedBefore('decidePolicyFor navigationAction:', 'decidePolicyFor navigationResponse:', 'if snapshotNavigationOnly', 'handleExternalLink(');
guardedBefore('createWebViewWith configuration:', 'private func newWindowSource', '!snapshotNavigationOnly', 'handleExternalLink(');
console.log('Website augment mutation and independent validation checks passed.');

// Regression: focusing an 838-row tbody must retain usable row selectors,
// and text discovery must search all rows rather than only the first samples.
function structureFixture() {
  const body = new Element('body');
  const table = new Element('table', '', {id: 'courses'});
  const tbody = new Element('tbody');
  const rows = Array.from({length: 838}, (_, i) => new Element('tr', i === 700 ? 'PHIL2001 Philosophy of mind' : 'Unit ' + i));
  body.children = [table]; table.parentElement = body;
  table.children = [tbody]; tbody.parentElement = table;
  tbody.children = rows;
  for (const row of rows) row.parentElement = tbody;
  for (const el of [body, table, tbody, ...rows]) {
    el.localName = el.tag; el.id = el.attrs.id || ''; el.classList = [];
    el.closest = () => null;
  }
  const doc = {
    body, title: 'Electives',
    querySelectorAll(selector) {
      if (selector === 'tbody') return [tbody];
      if (selector === 'tr') return rows;
      throw new Error('Unsupported fixture selector');
    },
    createTreeWalker(el) {
      const texts = [el, ...el.querySelectorAll('*')].map(n => ({nodeValue: n.textContent}));
      return {nextNode() { return texts.shift(); }};
    },
  };
  return {doc, rows};
}
function inspectFixture(selector, contains = '', offset = 0, limit = 12) {
  const {doc} = structureFixture();
  return JSON.parse(vm.runInNewContext('(function(){' + script('structureScript') + '})()', {
    document: doc, selector, contains, offset, limit,
    CSS: {escape: value => value}, NodeFilter: {SHOW_ELEMENT: 1, SHOW_TEXT: 4},
    getComputedStyle: () => ({display: 'block', visibility: 'visible'}),
    location: {origin: 'https://example.com', pathname: '/electives'},
  }));
}
const tableBody = inspectFixture('tbody');
assert.equal(tableBody.items[0].itemCount, 838);
assert.equal(tableBody.items[0].samples.length, 3);
assert.equal(tableBody.items[0].samples[0].selector, '#courses > tbody > tr:nth-of-type(1)');
assert.equal(tableBody.items[0].itemSelector, '#courses > tbody :is(li,tr,[role="listitem"],[role="row"])');
const philosophy = inspectFixture('tr', 'PHILOSOPHY');
assert.equal(philosophy.totalBeforeFilter, 838);
assert.equal(philosophy.total, 1);
assert.equal(philosophy.items[0].selector, '#courses > tbody > tr:nth-of-type(701)');
assert.match(philosophy.items[0].text, /Philosophy/);
assert.equal(philosophy.nextOffset, null);
const nextRows = inspectFixture('tr', '', 30, 12);
assert.equal(nextRows.items.length, 12);
assert.equal(nextRows.nextOffset, 42);
assert.equal(nextRows.items[0].selector, '#courses > tbody > tr:nth-of-type(31)');
console.log('Website structure large-table discovery checks passed.');
