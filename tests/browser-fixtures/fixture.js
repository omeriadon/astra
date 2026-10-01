const output = document.querySelector('#result');
const streams = [];
let audioContext;
let oscillator;
function report(value) {
    output.textContent = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
}
function action(id, callback) {
    document.getElementById(id).addEventListener('click', async () => {
        try {
            report(await callback());
        } catch (error) {
            report({ error: error.name, message: error.message });
        }
    });
}
action('alert', () => {
    alert('Fixture alert');
    return 'Alert completed';
});
action('confirm', () => confirm('Fixture confirmation'));
action('prompt', () => prompt('Fixture input', 'Test'));
action('popup', () => {
    const child = window.open('/popup', 'fixture-popup', 'width=480,height=320');
    return { popupCreated: Boolean(child) };
});
window.addEventListener('message', event => {
    if (event.origin === location.origin) report(event.data);
});
action('history', () => {
    history.pushState({ fixture: true }, '', '?state=fixture');
    return location.href;
});
action('storage', () => {
    const value = crypto.randomUUID();
    localStorage.setItem('astra-fixture', value);
    sessionStorage.setItem('astra-fixture', value);
    return value;
});
action('read-storage', () => ({ local: localStorage.getItem('astra-fixture'), session: sessionStorage.getItem('astra-fixture') }));
action('worker', async () => {
    const registration = await navigator.serviceWorker.register('/sw.js');
    await navigator.serviceWorker.ready;
    return { scope: registration.scope, controlled: Boolean(navigator.serviceWorker.controller) };
});
action('unregister', async () => {
    for (const registration of await navigator.serviceWorker.getRegistrations()) await registration.unregister();
    for (const key of await caches.keys()) await caches.delete(key);
    return 'Workers and caches removed';
});
action('cache', async () => await (await fetch('/cache')).text());
action('request-info', async () => await (await fetch('/request-info', { cache: 'no-store' })).json());
action('camera', async () => {
    const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
    streams.push(stream);
    document.querySelector('#capture').srcObject = stream;
    return stream.getTracks().map(track => ({ kind: track.kind, state: track.readyState }));
});
action('screen', async () => {
    const stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: true });
    streams.push(stream);
    document.querySelector('#capture').srcObject = stream;
    return stream.getTracks().map(track => ({ kind: track.kind, state: track.readyState }));
});
action('stop', () => {
    for (const stream of streams) for (const track of stream.getTracks()) track.stop();
    streams.length = 0;
    return 'Capture stopped';
});
action('location', () => new Promise((resolve, reject) => navigator.geolocation.getCurrentPosition(
    value => resolve({ accuracy: value.coords.accuracy, received: true }), reject
)));
action('notification', async () => await Notification.requestPermission());
action('passkey', async () => {
    const credential = await navigator.credentials.create({ publicKey: {
        challenge: crypto.getRandomValues(new Uint8Array(32)),
        rp: { name: 'Astra localhost fixture' },
        user: { id: crypto.getRandomValues(new Uint8Array(16)), name: 'fixture', displayName: 'Fixture' },
        pubKeyCredParams: [{ type: 'public-key', alg: -7 }],
        timeout: 60000,
        attestation: 'none'
    } });
    return { created: Boolean(credential) };
});
action('spatial', async () => {
    if (audioContext) await audioContext.close();
    audioContext = new AudioContext();
    const panner = new PannerNode(audioContext, { panningModel: 'HRTF', positionX: 2, positionZ: -1 });
    const gain = new GainNode(audioContext, { gain: 0.05 });
    oscillator = new OscillatorNode(audioContext, { frequency: 440 });
    oscillator.connect(gain).connect(panner).connect(audioContext.destination);
    oscillator.start();
    await audioContext.resume();
    panner.positionX.linearRampToValueAtTime(-2, audioContext.currentTime + 5);
    return 'HRTF sound moves from right to left over five seconds';
});
action('spatial-stop', async () => {
    if (audioContext) await audioContext.close();
    audioContext = undefined;
    return 'Positional audio stopped';
});
action('capabilities', () => ({
    secureContext: isSecureContext,
    serviceWorker: 'serviceWorker' in navigator,
    notifications: typeof Notification !== 'undefined',
    push: typeof PushManager !== 'undefined',
    mediaDevices: Boolean(navigator.mediaDevices),
    mediaSession: 'mediaSession' in navigator,
    webAudio: typeof AudioContext !== 'undefined',
    webAuthentication: typeof PublicKeyCredential !== 'undefined',
    globalPrivacyControl: navigator.globalPrivacyControl
}));
