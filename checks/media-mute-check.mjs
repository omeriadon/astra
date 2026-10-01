import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const controller = await readFile("astra/Web/Navigation/BrowserController.swift", "utf8");
const match = controller.match(
	/func toggleMediaElementsMuted\(\) \{[\s\S]*?let script = """([\s\S]*?)\n\t\t"""/
);
assert.ok(match, "production media mute script is present");
const muteScript = match[1].replaceAll("\\(shouldMute)", "true");
const unmuteScript = match[1].replaceAll("\\(shouldMute)", "false");

class FakeElement {
	constructor(tagName, children = [], muted = false) {
		this.tagName = tagName;
		this.children = children;
		this.muted = muted;
		this.isConnected = true;
	}

	matches(selector) {
		return selector.split(", ").includes(this.tagName);
	}

	querySelectorAll(selector) {
		return this.children.flatMap(child => [
			...(child.matches(selector) ? [child] : []),
			...child.querySelectorAll(selector)
		]);
	}
}

class FakeMutationObserver {
	constructor(callback) {
		this.callback = callback;
		this.isDisconnected = false;
	}

	observe() {}

	disconnect() {
		this.isDisconnected = true;
	}
}

const originalPlayer = new FakeElement("audio");
const root = new FakeElement("html", [originalPlayer]);
const window = {};
const document = {
	documentElement: root,
	querySelectorAll: selector => root.querySelectorAll(selector)
};
originalPlayer.ownerDocument = document;
const run = script => new Function("window", "document", "Element", "MutationObserver", script)(
	window,
	document,
	FakeElement,
	FakeMutationObserver
);

run(muteScript);
const muteState = window.__astraMediaMute;
assert.equal(originalPlayer.muted, true);

const removedPlayer = new FakeElement("video", [], true);
removedPlayer.ownerDocument = document;
root.children.push(removedPlayer);
muteState.observer.callback([{ addedNodes: [removedPlayer], removedNodes: [] }]);
assert.equal(removedPlayer.muted, true);
assert.equal(muteState.elements.size, 2);

removedPlayer.isConnected = false;
root.children = root.children.filter(node => node !== removedPlayer);
muteState.observer.callback([{ addedNodes: [], removedNodes: [removedPlayer] }]);
assert.equal(muteState.elements.size, 1);

removedPlayer.isConnected = true;
root.children.push(removedPlayer);
muteState.observer.callback([{ addedNodes: [removedPlayer], removedNodes: [] }]);
assert.equal(removedPlayer.muted, true);
assert.equal(muteState.elements.size, 2);

removedPlayer.ownerDocument = {};
muteState.observer.callback([{ addedNodes: [], removedNodes: [removedPlayer] }]);
assert.equal(muteState.elements.size, 1);
removedPlayer.ownerDocument = document;
root.children.push(removedPlayer);
muteState.observer.callback([{ addedNodes: [removedPlayer], removedNodes: [] }]);
assert.equal(muteState.elements.size, 2);

run(unmuteScript);
assert.equal(originalPlayer.muted, false);
assert.equal(removedPlayer.muted, true);
assert.equal(muteState.observer.isDisconnected, true);
