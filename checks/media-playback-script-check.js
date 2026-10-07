// Run: bun checks/media-playback-script-check.js
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../astra/Web/Navigation/BrowserController.swift", import.meta.url), "utf8");
const activity = source.split("func refreshActivity() async {")[1].match(/let script = """\n([\s\S]*?)\n\t\t"""/)[1];
const eligibility = source.split("private func refreshPictureInPictureEligibility")[1].match(/let script = """\n([\s\S]*?)\n\t\t"""/)[1];
const entry = source.split("func enterPictureInPicture() {")[1].match(/callAsyncJavaScript\("""\n([\s\S]*?)\n\t\t"""/)[1];
const observation = source.match(/private static let pictureInPictureScript = """\n([\s\S]*?)\n\t"""/)[1];
const video = {
    tagName: "VIDEO",
    paused: false,
    ended: false,
    readyState: 4,
    videoWidth: 1280,
    videoHeight: 720,
    currentTime: 10,
    muted: false,
    volume: 1,
    disablePictureInPicture: true,
    webkitPresentationMode: "inline",
    webkitSupportsPresentationMode: () => true,
    webkitSetPresentationMode: () => { video.webkitPresentationMode = "picture-in-picture"; },
    addEventListener: () => {},
    removeEventListener: () => {},
};
const context = {
    document: { querySelectorAll: () => [video], pictureInPictureEnabled: true },
    navigator: { mediaSession: { metadata: { title: "YouTube video", artist: "Channel" } } },
    setTimeout: callback => { callback(); return 1; },
    clearTimeout: () => {},
};
const state = () => runInNewContext(activity, context);
assert.equal(state().playing, true, "Playing video without audio counters must appear");
video.muted = true;
assert.equal(state().playing, true, "Muted playback must remain controllable");
video.paused = true;
assert.equal(state().paused, true);
video.ended = true;
assert.equal(state().paused, false);
assert.equal(state().playing, false);
video.ended = false;
video.paused = false;
const messages = [];
context.document.addEventListener = () => {};
context.window = {
    webkit: { messageHandlers: { pictureInPictureChanged: { postMessage: value => messages.push(value) } } },
};
runInNewContext(observation, context);
assert.equal(messages.at(-1).eligible, true, "Injected PiP observation must agree with polling");
assert.equal(runInNewContext(eligibility, context).eligible, true, "Explicit browser PiP must ignore the page hint");
assert.equal(await runInNewContext(`(async () => { ${entry} })()`, context), true);
assert.equal(video.disablePictureInPicture, true, "Restore the page's PiP hint after entry");
video.webkitSupportsPresentationMode = () => false;
video.webkitPresentationMode = "inline";
video.requestPictureInPicture = async () => {
    assert.equal(video.disablePictureInPicture, false);
    return {};
};
assert.equal(runInNewContext(eligibility, context).eligible, true, "Standard PiP must remain a fallback");
assert.equal(await runInNewContext(`(async () => { ${entry} })()`, context), true);
video.requestPictureInPicture = async () => { throw new Error("Not supported"); };
assert.equal(await runInNewContext(`(async () => { ${entry} })()`, context), false);
assert.equal(video.disablePictureInPicture, true);
video.readyState = 0;
assert.equal(runInNewContext(eligibility, context).eligible, false);
assert.equal(await runInNewContext(`(async () => { ${entry} })()`, context), false);
console.log("Media playback script checks passed");
