// Extraction runs in WebKit's isolated client world. Readability 0.6.0 is bundled locally.
(() => {
    // ponytail: skip documents above 20,000 elements; raise the cap if large articles need support.
    const maximumElements = 20000;
    const allowed = new Set('p div section article h1 h2 h3 h4 h5 h6 blockquote pre code ul ol li strong b em i u s del sub sup br hr figure figcaption img a table thead tbody tfoot tr th td caption span'.split(' '));
    const discarded = new Set('script style iframe object embed form input button textarea select svg math audio video template noscript'.split(' '));
    const safeURL = value => {
        if (!value) return null;
        try {
            const url = new URL(value, document.baseURI);
            return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password ? url.href : null;
        } catch {
            return null;
        }
    };
    const clean = (node, target, depth = 0) => {
        if (depth > 100) return;
        if (node.nodeType === 3) {
            target.appendChild(document.createTextNode(node.textContent));
            return;
        }
        if (node.nodeType !== 1) return;
        const tag = node.localName.toLowerCase();
        if (discarded.has(tag)) return;
        const output = allowed.has(tag) ? document.createElement(tag) : target;
        if (output !== target) {
            if (tag === 'a') {
                const href = safeURL(node.getAttribute('href'));
                if (href) output.setAttribute('href', href);
            }
            if (tag === 'img') {
                const src = safeURL(node.getAttribute('src'));
                if (!src) return;
                output.setAttribute('src', src);
                output.setAttribute('alt', node.getAttribute('alt') || '');
                output.setAttribute('loading', 'lazy');
                output.setAttribute('referrerpolicy', 'no-referrer');
            }
            if (['ltr', 'rtl'].includes(node.getAttribute('dir'))) output.setAttribute('dir', node.getAttribute('dir'));
            target.appendChild(output);
        }
        for (const child of node.childNodes) clean(child, output, depth + 1);
    };
    globalThis.astraExtractReader = () => {
        if (!document.body || document.getElementsByTagName('*').length > maximumElements) return null;
        const article = new Readability(document.cloneNode(true), {
            maxElemsToParse: maximumElements,
            serializer: element => element
        }).parse();
        if (!article || article.length < 500 || article.length > 2000000) return null;
        const body = document.createElement('article');
        clean(article.content, body);
        if (body.innerHTML.length > 5000000) return null;
        return { title: article.title || document.title, byline: article.byline || '',
            content: body.innerHTML, dir: article.dir === 'rtl' ? 'rtl' : 'ltr' };
    };
    let timer;
    let previous;
    globalThis.astraProbeReader = (force = false) => {
        const available = ['http:', 'https:'].includes(location.protocol)
            && document.body !== null && document.getElementsByTagName('*').length <= maximumElements
            && isProbablyReaderable(document);
        const key = location.href + ':' + available;
        if (force || key !== previous) {
            previous = key;
            window.webkit.messageHandlers.readerAvailabilityChanged.postMessage({ available, url: location.href });
        }
    };
    const schedule = () => {
        clearTimeout(timer);
        timer = setTimeout(globalThis.astraProbeReader, 500);
    };
    new MutationObserver(schedule).observe(document, { childList: true, subtree: true });
    addEventListener('DOMContentLoaded', schedule);
    addEventListener('popstate', schedule);
    schedule();
})();
