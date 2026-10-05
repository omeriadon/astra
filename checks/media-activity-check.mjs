import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../astra/Web/Navigation/BrowserController.swift', import.meta.url), 'utf8');
const activity = source.match(/private static let activityScript = """([\s\S]*?)"""/)[1];
const snapshot = source.match(/func refreshActivity\(\)[\s\S]*?let script = """([\s\S]*?)"""/)[1];
const events = new Map();
const reports = [];
new Function('document', 'window', activity)(
  { addEventListener: (name, callback) => events.set(name, callback) },
  { webkit: { messageHandlers: { pageActivityChanged: { postMessage: value => reports.push(value) } } } },
);
events.get('playing')({ target: { muted: true } });
assert.notEqual(reports.at(-1), 'playing');

function state(media) {
  return new Function('document', 'navigator', `return (${snapshot})`)(
    { querySelectorAll: () => media }, { mediaSession: null },
  );
}
const video = {
  tagName: 'VIDEO', muted: false, volume: 1, paused: false, ended: false,
  readyState: 4, currentTime: 1, videoWidth: 640, videoHeight: 360, webkitAudioDecodedByteCount: 0,
};
assert.equal(state([]).playing, false);
assert.equal(state([video]).playing, false);
assert.equal(state([video]).videoPlaying, true);
assert.equal(state([{ ...video, muted: true, webkitAudioDecodedByteCount: 100 }]).playing, false);
assert.equal(state([{ ...video, volume: 0, webkitAudioDecodedByteCount: 100 }]).playing, false);
assert.equal(state([{ ...video, webkitAudioDecodedByteCount: 100 }]).playing, true);
assert.equal(state([{ ...video, tagName: 'AUDIO' }]).playing, true);
assert.equal(state([{ ...video, tagName: 'AUDIO', paused: true }]).paused, true);
assert.equal(state([{ ...video, tagName: 'AUDIO', paused: true, currentTime: 0 }]).paused, false);
assert.equal(state([{ ...video, tagName: 'AUDIO', ended: true }]).playing, false);
console.log('Media activity production-script checks passed');
