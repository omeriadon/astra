import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

// Exercise the actual injected JavaScript, not a rewritten approximation.
const controller = readFileSync('astra/Web/Navigation/BrowserController.swift', 'utf8');
const marker = 'private static let pageTintScript = #"""';
const from = controller.indexOf(marker);
assert.ok(from >= 0, 'Website page-tint script must exist');
const start = from + marker.length;
const end = controller.indexOf('"""', start);
assert.ok(end > start, 'Website page-tint script must terminate');
const script = controller.slice(start, end);

function environment({ headerColor = 'rgb(18, 32, 54)', headerImage = 'none',
                       headerOpacity = '1', bodyColor = 'rgb(248, 249, 250)',
                       bodyImage = 'none', hasHeader = true, tileColor = null,
                       cssVars = {}, headerVariants = null, supportsIdle = false,
                       readyState = 'complete' } = {}) {
    const timers = [];
    const posts = [];
    const listeners = new Map();
    let mutation;
    let now = 0;
    let nextTimerId = 0;
    let nextIdleId = 0;
    let styleReads = 0;
    let geometryReads = 0;
    let hitTests = 0;
    const idleRequests = [];
    const element = (name, background, image, parent, isHeader = false) => ({
        name, parentElement: parent, isHeader,
        style: { backgroundColor: background, backgroundImage: image, opacity: '1',
                 visibility: 'visible', position: 'static',
                 getPropertyValue: key => cssVars[key] ?? '' },
        matches: () => isHeader,
        getBoundingClientRect: () => {
            geometryReads++;
            return isHeader
                ? { left: 0, width: 1000, height: 70, top: 0, bottom: 70 }
                : { left: 0, width: 1000, height: 800, top: 0, bottom: 800 };
        }
    });
    const html = element('html', 'rgba(0, 0, 0, 0)', 'none', null);
    const body = element('body', bodyColor, bodyImage, html);
    const header = element('header', headerColor, headerImage, body, true);
    header.style.opacity = headerOpacity;
    const child = element('span', 'rgba(0, 0, 0, 0)', 'none', header);
    const variants = headerVariants?.map((color, i) => {
        const bar = element('header-' + i, color, 'none', body, true);
        return element('child-' + i, 'rgba(0, 0, 0, 0)', 'none', bar);
    });
    const context = {
        fillStyle: 'rgb(0, 0, 0)',
        clearRect() {}, fillRect() {},
        getImageData() {
            const hex = /^#([a-f0-9]{3}|[a-f0-9]{6})$/i.exec(this.fillStyle);
            if (hex) {
                let digits = hex[1];
                if (digits.length === 3) digits = [...digits].map(ch => ch + ch).join('');
                return { data: [0, 2, 4].map(i => parseInt(digits.slice(i, i + 2), 16)).concat(255) };
            }
            const named = { red: [255, 0, 0, 255], blue: [0, 0, 255, 255],
                            transparent: [0, 0, 0, 0] }[this.fillStyle];
            if (named) return { data: named };
            const numbers = [...this.fillStyle.matchAll(/[\d.]+/g)].map(match => Number(match[0]));
            if (numbers.length < 3) return { data: [0, 0, 0, 0] };
            const alpha = numbers.length > 3 ? Math.round(numbers[3] * 255) : 255;
            return { data: [...numbers.slice(0, 3), alpha] };
        }
    };
    const document = {
        hidden: false, readyState, body, documentElement: html,
        querySelector() { return tileColor ? { content: tileColor } : null; },
        createElement(type) {
            assert.equal(type, 'canvas');
            return { getContext() { return context; } };
        },
        elementFromPoint(x, y) {
            hitTests++;
            if (!hasHeader || y > 56) return body;
            return variants ? variants[Math.min(variants.length - 1, Math.floor(x / (1000 / variants.length)))] : child;
        },
        addEventListener(name, fn) { listeners.set(name, fn); }
    };
    class MutationObserver {
        constructor(fn) { mutation = fn; }
        observe() {}
        disconnect() {}
    }
    const state = {
        hasHeader, header, body, html, document, posts,
        get styleReads() { return styleReads; },
        get geometryReads() { return geometryReads; },
        get hitTests() { return hitTests; },
        get pendingIdle() { return idleRequests.length; }
    };
    const sandbox = {
        document, MutationObserver,
        performance: { now: () => now },
        innerWidth: 1000, innerHeight: 800,
        location: { href: 'https://example.test/page' },
        getComputedStyle: node => { styleReads++; return node.style; },
        addEventListener(name, fn) { listeners.set(name, fn); },
        matchMedia: () => ({ addEventListener() {} }),
        setTimeout(fn, delay = 0) {
            const id = ++nextTimerId;
            timers.push({ id, at: now + Math.max(0, delay), fn });
            return id;
        },
        clearTimeout(id) {
            const index = timers.findIndex(timer => timer.id === id);
            if (index >= 0) timers.splice(index, 1);
        },
        window: { webkit: { messageHandlers: {
            pageTintChanged: { postMessage(message) { posts.push(message); } }
        } } }
    };
    if (supportsIdle) {
        sandbox.requestIdleCallback = fn => {
            const id = ++nextIdleId;
            idleRequests.push({ id, fn });
            return id;
        };
        sandbox.cancelIdleCallback = id => {
            const index = idleRequests.findIndex(item => item.id === id);
            if (index >= 0) idleRequests.splice(index, 1);
        };
    }
    runInNewContext(script, sandbox);
    state.advance = elapsed => {
        const until = now + elapsed;
        let iterations = 0;
        while (timers.length) {
            timers.sort((a, b) => a.at - b.at || a.id - b.id);
            if (timers[0].at > until) break;
            assert.ok(++iterations < 100, 'Tint timers must not spin');
            const timer = timers.shift();
            now = Math.max(now, timer.at);
            timer.fn();
        }
        now = until;
    };
    state.flush = () => {
        let iterations = 0;
        while (timers.length) {
            assert.ok(++iterations < 100, 'Tint scheduling must eventually settle');
            const next = Math.min(...timers.map(timer => timer.at));
            state.advance(Math.max(0, next - now));
        }
    };
    state.flushIdle = () => {
        while (idleRequests.length) idleRequests.shift().fn();
    };
    state.mutate = () => mutation?.();
    state.listeners = listeners;
    state.timers = timers;
    state.reinstall = () => runInNewContext(script, sandbox);
    return state;
}

const withHeader = environment();
withHeader.flush();
assert.equal(withHeader.posts.length, 1, 'Exactly one sample per loaded document');
assert.equal(withHeader.posts[0].source, 'chrome');
assert.equal(JSON.stringify(withHeader.posts[0].rgb), '[18,32,54]');
assert.ok(withHeader.styleReads <= 3 && withHeader.geometryReads <= 2,
    'Only painted elements should trigger geometry reads');
assert.equal(withHeader.hitTests, 16,
    'Uniform header should use the 16-point fast path');
assert.equal(withHeader.timers.length, 0, 'Sampling should not leave a timer running');

// Subsequent changes in page style and visibility must not resample.
const initialHits = withHeader.hitTests;
withHeader.header.style.backgroundColor = 'rgb(210, 95, 45)';
withHeader.mutate();
withHeader.listeners.get('visibilitychange')();
withHeader.flush();
withHeader.reinstall();
assert.equal(withHeader.hitTests, initialHits,
    'Visibility changes, DOM changes and duplicate installation must not resample');
assert.equal(withHeader.posts.length, 1,
    'One document must send exactly one native tint message');
for (const name of [
    'scroll', 'resize', 'click', 'pageshow', 'popstate',
    'transitionend', 'transitioncancel', 'animationend', 'animationcancel'
]) {
    assert.ok(!withHeader.listeners.has(name),
        'Do not register repeat tint sampling for ' + name);
}

// At documentEnd, wait until the page has finished loading.
const delayedLoad = environment({ readyState: 'loading' });
delayedLoad.flush();
assert.equal(delayedLoad.hitTests, 0,
    'Do not force early layout before the complete page load');
delayedLoad.header.style.backgroundColor = 'rgb(45, 85, 155)';
delayedLoad.listeners.get('load')();
delayedLoad.flush();
assert.equal(JSON.stringify(delayedLoad.posts[0].rgb), '[45,85,155]');
assert.equal(delayedLoad.posts.length, 1);
delayedLoad.listeners.get('load')();
delayedLoad.flush();
assert.equal(delayedLoad.hitTests, 16, 'Repeated load events must not resample');

// Four nearby colours fall into distinct 12-RGB buckets but remain
// one perceptual painted header; the old quantisation missed consensus.
const dithered = environment({ headerVariants: [
    'rgb(18, 30, 52)', 'rgb(23, 34, 56)',
    'rgb(28, 38, 60)', 'rgb(33, 42, 64)'
] });
dithered.flush();
assert.equal(dithered.posts[0].source, 'chrome',
    'CIELAB should merge near-identical flat headers across RGB bucket boundaries');

// Only uncertain page edges should pay for all 40 probes.
const mixedHeaders = environment({ headerVariants: [
    'rgb(240, 30, 30)', 'rgb(30, 240, 30)',
    'rgb(30, 30, 240)', 'rgb(240, 240, 30)'
] });
mixedHeaders.flush();
assert.equal(mixedHeaders.hitTests, 40,
    'Heterogeneous headers should trigger the full grid without repeating probes');

// A single idle callback is preferred over immediately sampling on load.
const idle = environment({ supportsIdle: true });
idle.advance(0);
assert.equal(idle.pendingIdle, 1);
assert.equal(idle.hitTests, 0, 'Idle sampling must not run synchronously');
idle.flushIdle();
assert.equal(idle.hitTests, 16);
assert.equal(idle.posts.length, 1);
idle.listeners.get('visibilitychange')();
idle.flushIdle();
assert.equal(idle.hitTests, 16, 'No later idle sample is allowed');

// Tabs loaded in the background can defer their only sample until visible.
const hiddenIdle = environment({ supportsIdle: true });
hiddenIdle.advance(0);
hiddenIdle.document.hidden = true;
hiddenIdle.flushIdle();
assert.equal(hiddenIdle.hitTests, 0);
hiddenIdle.document.hidden = false;
hiddenIdle.listeners.get('visibilitychange')();
assert.equal(hiddenIdle.pendingIdle, 1);
hiddenIdle.flushIdle();
assert.equal(hiddenIdle.posts.length, 1);
assert.equal(hiddenIdle.hitTests, 16);
hiddenIdle.listeners.get('visibilitychange')();
hiddenIdle.flushIdle();
assert.equal(hiddenIdle.hitTests, 16, 'Repeated foreground events must not resample');

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

const gradient = environment({ headerImage: 'linear-gradient(90deg, rgb(0, 0, 255), rgb(255, 0, 0))' });
gradient.flush();
assert.equal(gradient.posts[0].source, 'chrome', 'Linear gradient headers should yield a sampled tint');
assert.equal(JSON.stringify(gradient.posts[0].rgb), '[128,0,128]',
    'Average the CSS gradient across the top edge, not just its first stop');

const verticalGradient = environment({ headerImage: 'linear-gradient(to bottom, #102030, #b0c0d0)' });
verticalGradient.flush();
assert.equal(verticalGradient.posts[0].source, 'chrome');
assert.ok(verticalGradient.posts[0].rgb[0] < 100,
    'For vertical gradients, use the first visible pixels instead of the far-bottom stop');

const imageHeader = environment({ headerImage: 'url(https://example.test/cover.webp)' });
imageHeader.flush();
assert.equal(imageHeader.posts[0].source, 'none',
    'A photographic or unknown CSS image must not be mistaken for a solid tint');

const brandFallback = environment({ hasHeader: false, bodyImage: 'url(hero.jpg)',
                                    cssVars: { '--brand-color': '#3c50dc' } });
brandFallback.flush();
assert.equal(brandFallback.posts[0].source, 'brand',
    'Use a bounded known CSS brand token only if no painted colour exists');
assert.equal(JSON.stringify(brandFallback.posts[0].rgb), '[60,80,220]');

const tileFallback = environment({ hasHeader: false, bodyImage: 'url(hero.jpg)',
                                   tileColor: '#12a3b4', cssVars: { '--brand-color': '#3c50dc' } });
tileFallback.flush();
assert.equal(JSON.stringify(tileFallback.posts[0].rgb), '[18,163,180]',
    'OpenBrand-style tile metadata must precede heuristic CSS variables');

const fadedHeader = environment({ headerColor: 'rgb(0, 0, 0)', headerOpacity: '0.5' });
fadedHeader.flush();
assert.equal(fadedHeader.posts[0].source, 'chrome');
assert.ok(fadedHeader.posts[0].rgb[0] > 110,
    'Composite CSS element opacity with the opaque body behind the header');

const loading = readFileSync('astra/UI/Chrome/BrowserLoadingBar.swift', 'utf8');
const shell = readFileSync('astra/UI/Shell/BrowserShellControls.swift', 'utf8');
const favicons = readFileSync('astra/Storage/FaviconStore.swift', 'utf8');
assert.ok(!loading.includes('theme.progressColor'), 'Never use space chroma for web loading progress');
assert.match(shell, /controller\.themeColorIsLight \?\? theme\.tabColorIsLight/);
assert.match(controller, /\.luminance > 0\.179/);
assert.match(controller, /const lab = rgb =>/, 'Colour grouping must use perceptual Lab clustering');
assert.match(controller, /sampledBrandColor\s*\?\? sampledFaviconColor/,
    'Cached image branding must remain behind explicit CSS brand colours');
assert.match(controller, /sampledFaviconColor\s*\?\? webView\.underPageBackgroundColor/,
    'Favicon accent is a last resort before WebKit default background');
assert.match(controller, /generation == navigationGeneration/,
    'Do not apply a late favicon colour to a different navigation');
assert.match(controller, /pageTintHandledGeneration != navigationGeneration/,
    'Reject duplicate native samples for the same full navigation');
assert.match(controller, /pageTintHandledGeneration = navigationGeneration/,
    'Record when the one-shot native sample is applied');
assert.ok(!script.includes('MutationObserver'),
    'Page tint must not observe continuous page mutations');
assert.ok(!script.includes("addEventListener('scroll'"),
    'Page tint must not subscribe to scrolling');
assert.match(favicons, /Task\.detached\(priority: \.utility\)/,
    'Favicon quantisation must not decode on the browser main actor');
assert.match(favicons, /kCGImageSourceThumbnailMaxPixelSize: 32/,
    'Palette decoding should be downsampled to a small thumbnail');
assert.match(favicons, /faviconAccentMisses\.insert\(key\)/,
    'Cache neutral favicons without repeating decode work');
console.log('Website tint sampling and progress-contrast checks passed');
