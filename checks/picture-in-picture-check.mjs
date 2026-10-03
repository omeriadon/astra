import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../astra/Web/Navigation/BrowserController.swift', import.meta.url), 'utf8');
const observation = source.match(/private static let pictureInPictureScript = """([\s\S]*?)"""/)[1];
const poll = source.match(/private func refreshPictureInPictureEligibility[\s\S]*?let script = """([\s\S]*?)"""/)[1];
const action = source.match(/func enterPictureInPicture\(\)[\s\S]*?callAsyncJavaScript\("""([\s\S]*?)"""/)[1];
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

function environment(videos = [], properties = {}) {
  const events = new Map();
  const reports = [];
  const document = {
    querySelectorAll: () => videos,
    addEventListener: (name, callback) => events.set(name, callback),
    ...properties,
  };
  const window = { webkit: { messageHandlers: { pictureInPictureChanged: {
    postMessage: value => reports.push(value),
  } } } };
  return { document, window, reports, events };
}

function video(properties = {}) {
  return {
    readyState: 4,
    videoWidth: 640,
    videoHeight: 360,
    ended: false,
    disablePictureInPicture: false,
    addEventListener() {},
    removeEventListener() {},
    ...properties,
  };
}

function state(context) {
	new Function('document', 'window', observation)(context.document, context.window);
  const result = new Function('document', 'window', `return (${poll})`)(context.document, context.window);
  assert.deepEqual(context.reports.at(-1), result);
  return result;
}

async function enter(context) {
  state(context);
  return new AsyncFunction('document', 'window', 'setTimeout', action)(
    context.document, context.window, callback => queueMicrotask(callback),
  );
}

assert.deepEqual(state(environment()), { active: false, eligible: false });
assert.equal(await enter(environment()), false);

const standard = video({ requestPictureInPicture: async () => true });
assert.equal(state(environment([standard], { pictureInPictureEnabled: true })).eligible, true);
assert.equal(await enter(environment([standard], { pictureInPictureEnabled: true })), true);
assert.equal(state(environment([standard], { pictureInPictureEnabled: false })).eligible, false);

const rejected = video({ requestPictureInPicture: async () => { throw new Error('gesture required'); } });
assert.equal(await enter(environment([rejected], { pictureInPictureEnabled: true })), false);

const webkitVideo = video({
  webkitPresentationMode: 'inline',
  webkitSupportsPresentationMode: () => true,
  webkitSetPresentationMode(mode) { this.webkitPresentationMode = mode; },
});
const webkitContext = environment([webkitVideo]);
assert.equal(state(webkitContext).eligible, true);
assert.equal(await enter(webkitContext), true);
assert.equal(state(webkitContext).active, true);
webkitVideo.webkitPresentationMode = 'inline';
assert.equal(state(webkitContext).active, false);

const unsupported = video({
  webkitSupportsPresentationMode: () => false,
  webkitSetPresentationMode() { throw new Error('ineligible'); },
  requestPictureInPicture() { throw new Error('ineligible'); },
});
assert.equal(state(environment([unsupported], { pictureInPictureEnabled: true })).eligible, false);
assert.equal(await enter(environment([unsupported], { pictureInPictureEnabled: true })), false);

const missingSetter = video({ webkitSupportsPresentationMode: () => true });
assert.equal(state(environment([missingSetter])).eligible, false);
assert.equal(await enter(environment([missingSetter])), false);

for (const properties of [
  { videoWidth: 0 }, { videoHeight: 0 }, { readyState: 1 },
  { ended: true }, { disablePictureInPicture: true },
]) {
  const ineligible = video({ ...standard, ...properties });
  const context = environment([ineligible], { pictureInPictureEnabled: true });
  assert.equal(state(context).eligible, false);
  assert.equal(await enter(context), false);
}

let requests = 0;
const eligible = video({ requestPictureInPicture: async () => { requests += 1; return true; } });
assert.equal(await enter(environment([unsupported, eligible], { pictureInPictureEnabled: true })), true);
assert.equal(requests, 1);
console.log('picture-in-picture production JavaScript checks passed');
