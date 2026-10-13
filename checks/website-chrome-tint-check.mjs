import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

// Exercise the actual injected JavaScript, not a rewritten approximation.
const controller = readFileSync('astra/Web/Navigation/BrowserController.swift', 'utf8');
const marker = 'private static let pageTintScript = """';
const from = controller.indexOf(marker);
assert.ok(from >= 0, 'Website page-tint script must exist');
const start = from + marker.length;
const end = controller.indexOf('"""', start);
assert.ok(end > start, 'Website page-tint script must terminate');
const script = controller.slice(start, end);

function environment({ headerColor = 'rgb(18, 32, 54)', headerImage = 'none',
                       bodyColor = 'rgb(248, 249, 250)', hasHeader = true } = {}) {
    const timers = [];
    const posts = [];
    const listeners = new Map();
    let mutation;
    let now = 0;
    const element = (name, background, image, parent, isHeader = false) => ({
        name, parentElement: parent, isHeader,
        style: { backgroundColor: background, backgroundImage: image, opacity: '1',
                 visibility: 'visible', position: 'static' },
        matches: () => isHeader,
        getBoundingClientRect: () => isHeader
            ? { width: 1000, height: 70, top: 0, bottom: 70 }
            : { width: 1000, height: 800, top: 0, bottom: 800 }
    });
    const body = element('body', bodyColor, 'none', null);
    const header = element('header', headerColor, headerImage, body, true);
    const child = element('span', 'rgba(0, 0, 0, 0)', 'none', header);
    const context = {
        fillStyle: 'rgb(0, 0, 0)',
        clearRect() {}, fillRect() {},
        getImageData() {
            const numbers = [...this.fillStyle.matchAll(/[\d.]+/g)].map(match => Number(match[0]));
            if (numbers.length < 3) return { data: [0, 0, 0, 0] };
            const alpha = numbers.length > 3 ? Math.round(numbers[3] * 255) : 255;
            return { data: [...numbers.slice(0, 3), alpha] };
        }
    };
    const document = {
        hidden: false, body, documentElement: {},
        createElement(type) {
            assert.equal(type, 'canvas');
            return { getContext() { return context; } };
        },
        elementFromPoint(_, y) { return hasHeader && y <= 56 ? child : body; },
        addEventListener(name, fn) { listeners.set(name, fn); }
    };
    class MutationObserver {
        constructor(fn) { mutation = fn; }
        observe() {}
        disconnect() {}
    }
    const state = { hasHeader, header, body, document, posts };
    const sandbox = {
        document, MutationObserver,
        performance: { now: () => now },
        innerWidth: 1000, innerHeight: 800,
        location: { href: 'https://example.test/page' },
        getComputedStyle: node => node.style,
        addEventListener(name, fn) { listeners.set(name, fn); },
        matchMedia: () => ({ addEventListener() {} }),
        setTimeout(fn) { timers.push(fn); return timers.length; },
        window: { webkit: { messageHandlers: {
            pageTintChanged: { postMessage(message) { posts.push(message); } }
        } } }
    };
    runInNewContext(script, sandbox);
    state.flush = () => {
        while (timers.length) {
            now += 800;
            timers.shift()();
        }
    };
    state.mutate = () => mutation();
    state.listeners = listeners;
    state.timers = timers;
    state.reinstall = () => runInNewContext(script, sandbox);
    return state;
}

const withHeader = environment();
withHeader.flush();
assert.equal(withHeader.posts.length, 1);
assert.equal(withHeader.posts[0].source, 'chrome');
assert.equal(JSON.stringify(withHeader.posts[0].rgb), '[18,32,54]');
withHeader.mutate();
withHeader.mutate();
assert.equal(withHeader.timers.length, 1, 'Mutations must be coalesced');
withHeader.flush();
assert.equal(withHeader.posts.length, 1, 'Unchanged tint must not update SwiftUI');
withHeader.header.style.backgroundColor = 'rgb(210, 95, 45)';
withHeader.mutate();
withHeader.flush();
assert.equal(JSON.stringify(withHeader.posts.at(-1).rgb), '[210,95,45]');
assert.equal(withHeader.posts.length, 2, 'SPA theme changes must propagate');
withHeader.header.style.backgroundColor = 'rgb(45, 85, 155)';
withHeader.listeners.get('load')();
withHeader.flush();
assert.equal(JSON.stringify(withHeader.posts.at(-1).rgb), '[45,85,155]',
    'Late-loading CSS should trigger a resample');
withHeader.header.style.backgroundColor = 'rgb(40, 100, 180)';
withHeader.listeners.get('pageshow')();
withHeader.flush();
assert.equal(JSON.stringify(withHeader.posts.at(-1).rgb), '[40,100,180]',
    'Back-forward cache restoration must trigger a fresh tint');
withHeader.document.hidden = true;
withHeader.mutate();
assert.equal(withHeader.timers.length, 0, 'Hidden tab must do no sampling');
withHeader.document.hidden = false;
withHeader.listeners.get('visibilitychange')();
withHeader.flush();
withHeader.reinstall();
assert.equal(withHeader.posts.length, 4, 'Duplicate installation must not duplicate events');

const bodyOnly = environment({ hasHeader: false });
bodyOnly.flush();
assert.equal(bodyOnly.posts[0].source, 'surface');
assert.equal(JSON.stringify(bodyOnly.posts[0].rgb), '[248,249,250]');

const transparent = environment({ headerColor: 'rgba(0, 0, 0, 0)' });
transparent.flush();
assert.equal(transparent.posts[0].source, 'surface',
    'A fully transparent header must not outrank declared page metadata');

const translucent = environment({ headerColor: 'rgba(0, 0, 0, 0.8)' });
translucent.flush();
assert.equal(translucent.posts[0].source, 'chrome');
assert.equal(JSON.stringify(translucent.posts[0].rgb), '[50,50,50]',
    'Alpha-composite a translucent sticky header against the body surface');

const gradient = environment({ headerImage: 'linear-gradient(red, blue)' });
gradient.flush();
assert.equal(gradient.posts[0].source, 'none', 'Do not pretend a gradient is a solid colour');

const loading = readFileSync('astra/UI/Chrome/BrowserLoadingBar.swift', 'utf8');
const shell = readFileSync('astra/UI/Shell/BrowserShellControls.swift', 'utf8');
assert.ok(!loading.includes('theme.progressColor'), 'Never use space chroma for web loading progress');
assert.match(shell, /controller\.themeColorIsLight \?\? theme\.tabColorIsLight/);
assert.match(controller, /\.luminance > 0\.179/);
console.log('Website tint sampling and progress-contrast checks passed');
