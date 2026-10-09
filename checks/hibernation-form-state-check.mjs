import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../astra/Web/Navigation/BrowserController.swift', import.meta.url), 'utf8');
const safety = source.split('func refreshHibernationSafety()')[1];
const script = safety.match(/let script = """\n([\s\S]*?)\n\t\t"""/)[1];
const dirty = fields => runInNewContext(script, { document: { querySelectorAll: () => fields } });
assert.equal(dirty([]), false);
assert.equal(dirty([{ tagName: 'INPUT', type: 'text', value: '', defaultValue: '' }]), false);
assert.equal(dirty([{ tagName: 'INPUT', type: 'text', value: 'draft', defaultValue: '' }]), true);
assert.equal(dirty([{ tagName: 'INPUT', type: 'password', value: 'autofilled', defaultValue: '' }]), true);
assert.equal(dirty([{ tagName: 'INPUT', type: 'checkbox', checked: true, defaultChecked: false }]), true);
assert.equal(dirty([{ tagName: 'SELECT', options: [{ selected: true, defaultSelected: false }] }]), true);
assert.equal(dirty([{ tagName: 'SELECT', multiple: false, size: 0, selectedIndex: 0, options: [{ selected: true, defaultSelected: false, disabled: false }] }]), false);
assert.equal(dirty([{ tagName: 'SELECT', multiple: false, size: 0, selectedIndex: 1, options: [{ selected: false, defaultSelected: false, disabled: false }, { selected: true, defaultSelected: false, disabled: false }] }]), true);
assert.equal(dirty([{ tagName: 'TEXTAREA', value: 'draft', defaultValue: '' }]), true);
assert.match(safety, /in: \.defaultClient/);
assert.match(safety, /value == false/);
console.log('Hibernation form-state checks passed');

const activity = source.match(/private static let activityScript = """\n([\s\S]*?)\n\t"""/)[1];
const handlers = new Map();
const reports = [];
runInNewContext(activity, {
    document: { addEventListener: (name, handler) => handlers.set(name, handler) },
    window: { webkit: { messageHandlers: { pageActivityChanged: { postMessage: value => reports.push(value) } } } },
});
handlers.get('drop')({ isTrusted: true, dataTransfer: { files: [1] } });
handlers.get('pointerdown')({ isTrusted: true, target: { closest: () => ({}) } });
assert.deepEqual(reports, ['dirty', 'dirty']);
handlers.get('drop')({ isTrusted: false, dataTransfer: { files: [1] } });
handlers.get('pointerdown')({ isTrusted: false, target: { closest: () => ({}) } });
assert.equal(reports.length, 2);
