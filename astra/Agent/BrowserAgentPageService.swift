#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER
import AppKit
import Foundation
import MCP
import WebKit

/// Browser-owned WebKit operations. Image encoding is isolated in a background actor.
@MainActor
enum BrowserAgentPageService {
    private static let inspectionScript = #"""
const safe = value => {try {return String(value ?? '').slice(0,500);}catch{return '[unserializable]';}};
const output = value => JSON.stringify(value);
const select = () => {
    let nodes;
    try { nodes = document.querySelectorAll(selector || 'html'); }
    catch { throw Error('invalid_selector: Invalid CSS selector.'); }
    if (nodes.length !== 1) throw Error('ambiguous_selector: Expected exactly one element.');
    return nodes[0];
};
const state = globalThis.__astraAgentInspection;
if (operation === 'get_console_messages' || operation === 'get_javascript_errors') {
    if (enable && !state) {
        const data = {console: [], errors: [], enabledAt: Date.now(), dropped: 0, originals: {}, wrappers: {}};
        const record = (bucket, entry) => {
            const list = data[bucket];
            if (list.length >= 200) { list.shift(); data.dropped++; }
            list.push(entry);
        };
        for (const method of ['log', 'info', 'warn', 'error', 'debug']) {
            const original = console[method];
            data.originals[method] = original;
            data.wrappers[method] = console[method] = function (...items) {
                record('console', {type: method, time: Date.now(), message: safe(items.map(safe).join(' '))});
                return Reflect.apply(original, this, items);
            };
        }
        data.errorHandler = event => record('errors', {type:'error', time:Date.now(), message:safe(event.message), source:safe(event.filename), line:event.lineno});
        data.rejectionHandler = event => record('errors', {type:'unhandledrejection', time:Date.now(), message:safe(event.reason)});
        addEventListener('error', data.errorHandler);
        addEventListener('unhandledrejection', data.rejectionHandler);
        globalThis.__astraAgentInspection = data;
    }
    const current = globalThis.__astraAgentInspection;
    const key = operation === 'get_console_messages' ? 'console' : 'errors';
    const records = current?.[key]?.slice() || [];
    if (clear && current) current[key].length = 0;
    return output({records, enabled:!!current, enabledAt:current?.enabledAt || null, dropped:current?.dropped || 0,
        coverage:'main-frame events after enablement; page scripts may alter the instrumentation'});
}
if (operation === 'get_network_requests') {
    const entries = performance.getEntriesByType('resource').slice(-200).map(e => ({
        name:safe(e.name), initiatorType:safe(e.initiatorType), startTime:e.startTime,
        duration:e.duration, transferSize:e.transferSize || 0, encodedBodySize:e.encodedBodySize || 0
    }));
    const truncated=performance.getEntriesByType('resource').length>200;
    if (clear) performance.clearResourceTimings();
    return output({entries, source:'Resource Timing', coverage:'main-frame exposed timing entries only; no status, headers or bodies',
        truncated});
}
if (operation === 'inspect_css') {
    const node=select(), style=getComputedStyle(node);
    const allowed = ['display','visibility','opacity','color','background-color','font-size','font-family','font-weight',
        'position','z-index','width','height','margin','padding','overflow','transform','border','border-radius'];
    const requested=properties.length ? properties : allowed;
    if (requested.length>64 || requested.some(p=>!/^[-a-z]{1,64}$/.test(p))) throw Error('invalid_argument: CSS property list is invalid.');
    return output({selector, properties:Object.fromEntries(requested.map(p=>[p,safe(style.getPropertyValue(p))]))});
}
if (operation === 'inspect_dom') {
    const root=select(), nodes=[root], walker=document.createTreeWalker(root,NodeFilter.SHOW_ELEMENT);
    while(nodes.length<500) {const next=walker.nextNode();if(!next)break;nodes.push(next);}
    return output({selector:selector||'html', count:nodes.length, truncated:!!walker.nextNode(),
        nodes:nodes.map(n=>({tag:n.tagName.toLowerCase(), role:safe(n.getAttribute('role')), id:safe(n.id),
            className:safe(n.getAttribute('class')), childCount:n.children.length}))});
}
if (operation === 'get_selected_page_text') {
    const active=document.activeElement;
    const protectedSelection=active?.matches('input,textarea');
    const selected=protectedSelection ? '' : String(getSelection()?.toString() || '');
    return output({text:selected.slice(0,32000),truncated:selected.length>32000,
        redacted:!!protectedSelection,coverage:'main-frame document selection; form-control selections excluded'});
}
if (operation === 'get_page_metadata') {
    const publicURL=value=>{try {const u=new URL(value,location.href);u.username='';u.password='';return safe(u.href);}catch{return null;}};
    return output({title:safe(document.title),url:publicURL(location.href),language:safe(document.documentElement.lang),
        characterSet:safe(document.characterSet),description:safe(document.querySelector('meta[name="description"]')?.content),
        canonicalURL:document.querySelector('link[rel="canonical"]') ? publicURL(document.querySelector('link[rel="canonical"]').href) : null,
        viewport:safe(document.querySelector('meta[name="viewport"]')?.content),coverage:'main-frame public document metadata'});
}
if (operation === 'get_performance_metrics') {
    const navigation=performance.getEntriesByType('navigation')[0];
    return output({navigation:navigation?{duration:navigation.duration,domContentLoadedEventEnd:navigation.domContentLoadedEventEnd,
        loadEventEnd:navigation.loadEventEnd, transferSize:navigation.transferSize}:null,
        resourceCount:performance.getEntriesByType('resource').length, domElementCount:document.getElementsByTagName('*').length,
        cpu:null, heap:null, coverage:'Web Performance API exposed to main frame; native CPU and heap unavailable'});
}
throw Error('unsupported_operation: Unknown page inspection.');
"""#
    nonisolated static let tools: [Tool] = {
        let string: Value = .object(["type": .string("string")])
        let number: Value = .object(["type": .string("number")])
        let boolean: Value = .object(["type": .string("boolean")])
        let definitions: [(String, String, [String: Value], [String], Bool)] = [
            ("screenshot", "Capture viewport, visible element or region; full_page uses public WebKit PDF rendering. Bounded PNG/JPEG encoding off main actor.", ["mode": string, "selector": string, "x": number, "y": number, "width": number, "height": number, "maxWidth": number, "format": string, "quality": number], [], true),
            ("get_console_messages", "Read bounded console records collected since explicit instrumentation enablement. Main frame only; page code can modify instrumentation.", ["enable": boolean, "clear": boolean], [], true),
            ("get_javascript_errors", "Read bounded error/rejection records since explicit instrumentation enablement. Main frame only.", ["enable": boolean, "clear": boolean], [], true),
            ("get_network_requests", "Read bounded Resource Timing entries already exposed by the page. No bodies/status/headers or guaranteed cross-origin timing.", ["clear": boolean], [], true),
            ("inspect_css", "Inspect selected computed CSS properties of exactly one element without reading input values.", ["selector": string, "properties": .object(["type": .string("array"), "items": string])], ["selector"], true),
            ("inspect_dom", "Inspect a bounded DOM summary excluding input values and executable content.", ["selector": string], [], true),
            ("get_selected_page_text", "Read bounded main-frame selected page text, excluding selections inside form controls.", [:], [], true),
            ("get_page_metadata", "Read bounded title, description, language, canonical URL and viewport metadata without input values.", [:], [], true),
            ("get_performance_metrics", "Report measured Navigation/Resource Timing and DOM counts; unavailable native CPU/heap metrics are explicit.", [:], [], true),
            ("evaluate_javascript", "Separately permissioned JavaScript expression in explicit page or isolated content world. Cancellation cannot interrupt already executing JavaScript.", ["expression": string, "contentWorld": string], ["expression", "contentWorld"], false),
            ("upload_file", "Select user-approved files through a trusted native click and the public WebKit upload delegate. Reports file selection, not server upload completion.", ["scopeToken": string, "ref": string], ["scopeToken", "ref"], false)
        ]
        return definitions.map { name, description, extra, required, readOnly in
            var properties = extra
            properties["tabID"] = string
            return Tool(name: name, description: description, inputSchema: .object([
                "type": .string("object"), "properties": .object(properties),
                "required": .array((required + ["tabID"]).map { .string($0) }), "additionalProperties": .bool(false)
            ]), annotations: .init(readOnlyHint: readOnly, destructiveHint: !readOnly, openWorldHint: true))
        }
    }()


    /// Remove page-world listeners and restore only console methods still owned by us.
    static func disableDiagnostics(controller: BrowserController) {
        guard let view = controller.webViewIfLoaded else { return }
        Task { @MainActor [weak view] in
            _ = try? await view?.callAsyncJavaScript(#"""
            const data = globalThis.__astraAgentInspection;
            if (data) {
                for (const method of Object.keys(data.originals || {})) {
                    if (console[method] === data.wrappers[method]) console[method] = data.originals[method];
                }
                removeEventListener('error', data.errorHandler);
                removeEventListener('unhandledrejection', data.rejectionHandler);
                data.console.length = 0; data.errors.length = 0;
                delete globalThis.__astraAgentInspection;
            }
            """#, arguments: [:], in: nil, contentWorld: .page)
        }
    }

    static func execute(name: String, arguments: [String: Value], controller: BrowserController,
                 authorizeJavaScript: () throws -> Void, validate: @escaping @MainActor () throws -> Void,
                 uploadTrigger: (@MainActor (String) async throws -> Void)? = nil) async throws -> CallTool.Result {
        try validate()
        try Task.checkCancellation()
        guard let view = controller.webViewIfLoaded, controller.hasCurrentPageDocument, !controller.isInvalidated else {
            throw PageError("page_unavailable", "The shared tab has no live document.")
        }
        let documentID = controller.navigationIdentifier
        if name == "upload_file" {
            let token = try text(arguments, "scopeToken", maximum: 128)
            let ref = try text(arguments, "ref", maximum: 512)
            guard let uploadTrigger else { throw PageError("unsupported_capability", "Trusted native file-input activation is unavailable.") }
            try BrowserAgentUploadScopes.shared.arm(token: token, controller: controller, validate: validate)
            do { try await uploadTrigger(ref) }
            catch { BrowserAgentUploadScopes.shared.cancel(controller: controller); throw error }
            let selected = await BrowserAgentUploadScopes.shared.waitForSelection(controller: controller)
            try Task.checkCancellation()
            try validate()
            guard selected else { throw PageError("upload_cancelled", "File selection was cancelled, revoked, or did not complete within 30 seconds.") }
            let encoded = try await BrowserAgentResultEncoder.shared.encode(.object([
                "status": .string("selected"), "uploadComplete": .bool(false),
                "coverage": .string("Files were handed to WebKit; the website controls subsequent upload and submission.")]))
            try validate()
            try Task.checkCancellation()
            guard controller.navigationIdentifier == documentID else { throw PageError("document_changed", "Navigation invalidated the upload selection result.") }
            return encoded
        }
        if name == "screenshot" {
            let output = try await screenshot(arguments, view: view, validate: validate)
            try validate()
            guard documentID == controller.navigationIdentifier else { throw PageError("document_changed", "Navigation invalidated the capture.") }
            return output
        }
        let script: String
        let world: WKContentWorld
        var scriptArguments: [String: Any] = [:]
        if name == "evaluate_javascript" {
            try authorizeJavaScript()
            let expression = try text(arguments, "expression", maximum: 65_536)
            let selection = try text(arguments, "contentWorld", maximum: 32)
            guard selection == "page" || selection == "isolated" else { throw PageError("invalid_argument", "contentWorld must be page or isolated.") }
            world = selection == "page" ? .page : .defaultClient
            // Source is deliberately evaluated only after the separate permission check.
            script = "const value = await (async () => (\(expression)))(); return JSON.stringify({result: value === undefined ? null : value});"
        } else {
            world = name.hasPrefix("get_console") || name == "get_javascript_errors" || name == "get_network_requests" ? .page : .defaultClient
            script = inspectionScript
            scriptArguments = ["operation": name, "enable": flag(arguments, "enable"), "clear": flag(arguments, "clear"),
                               "selector": optionalText(arguments, "selector") ?? "", "properties": try stringArray(arguments["properties"])]
        }
        guard let raw = try await view.callAsyncJavaScript(script, arguments: scriptArguments, in: nil, contentWorld: world) as? String,
              raw.utf8.count <= 1_048_576 else { throw PageError("output_limit", "Inspection result exceeded the output limit or was not serializable.") }
        try validate()
        try Task.checkCancellation()
        guard controller.navigationIdentifier == documentID else { throw PageError("document_changed", "The inspected document changed; retry on the new document.") }
        let encoded = try await BrowserAgentResultEncoder.shared.decode(raw)
        try validate()
        try Task.checkCancellation()
        guard controller.navigationIdentifier == documentID else { throw PageError("document_changed", "The inspected document changed during serialization.") }
        return encoded
    }

    private static func screenshot(_ args: [String: Value], view: WKWebView, validate: () throws -> Void) async throws -> CallTool.Result {
        let mode = optionalText(args, "mode") ?? "viewport"
        let format = optionalText(args, "format") ?? "png"
        let maximum = try boundedNumber(args, "maxWidth", fallback: 1600, range: 1...4096)
        let quality = try boundedNumber(args, "quality", fallback: 0.85, range: 0...1)
        guard ["png", "jpeg"].contains(format), !view.bounds.isEmpty else { throw PageError("invalid_argument", "Use PNG/JPEG and a tab with a rendered viewport.") }
        let pixels: CGImage
        if mode == "full_page" {
            let dimensions = try await view.callAsyncJavaScript("return [Math.max(document.documentElement.scrollWidth, document.body?.scrollWidth || 0), Math.max(document.documentElement.scrollHeight, document.body?.scrollHeight || 0)];", arguments: [:], in: nil, contentWorld: .defaultClient)
            guard let dimensions = dimensions as? [Double], dimensions.count == 2, dimensions.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100_000 }) else { throw PageError("capture_limit", "Document dimensions are unavailable or exceed capture limits.") }
            let width = min(maximum, dimensions[0])
            let height = dimensions[1] * width / dimensions[0]
            guard width * height <= 16_000_000, dimensions[0] * dimensions[1] <= 40_000_000 else { throw PageError("capture_limit", "Full-page PDF or image exceeds capture limits. Reduce maxWidth or capture a region.") }
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: dimensions[0], height: dimensions[1])
            let pdf = try await view.pdf(configuration: configuration)
            try validate()
            let encoded = try await BrowserAgentImageEncoder.shared.encodePDF(pdf, width: Int(width.rounded(.up)), height: Int(height.rounded(.up)), format: format, quality: quality)
            try Task.checkCancellation()
            try validate()
            return captureResult(encoded, mode: mode)
        } else {
            var rect = view.bounds
            if mode == "region" {
                rect = CGRect(x: try boundedNumber(args, "x", fallback: 0, range: 0...100_000), y: try boundedNumber(args, "y", fallback: 0, range: 0...100_000), width: try boundedNumber(args, "width", fallback: 0, range: 1...100_000), height: try boundedNumber(args, "height", fallback: 0, range: 1...100_000))
            } else if mode == "element" {
                let selector = try text(args, "selector", maximum: 4096)
                let raw = try await view.callAsyncJavaScript("const nodes=document.querySelectorAll(selector); if(nodes.length!==1) throw Error('Selector must match exactly one element'); const r=nodes[0].getBoundingClientRect(); return [r.x,r.y,r.width,r.height];", arguments: ["selector": selector], in: nil, contentWorld: .defaultClient)
                guard let values = raw as? [Double], values.count == 4, values.allSatisfy(\.isFinite) else { throw PageError("element_unavailable", "Element geometry is unavailable.") }
                rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            } else if mode != "viewport" { throw PageError("invalid_argument", "Unknown screenshot mode.") }
            guard !rect.isEmpty, view.bounds.contains(rect) else { throw PageError("outside_viewport", "The capture rectangle must lie inside the viewport. Scroll the element into view first.") }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = rect
            // Bound pixel count even for a tall, narrow region and Retina scale.
            configuration.snapshotWidth = NSNumber(value: min(maximum, rect.width, sqrt(4_000_000 * rect.width / rect.height)))
            let image = try await view.takeSnapshot(configuration: configuration)
            try validate()
            guard let captured = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw PageError("capture_failed", "WebKit did not return image pixels.") }
            pixels = captured
        }
        try Task.checkCancellation()
        try validate()
        let encoded = try await BrowserAgentImageEncoder.shared.encode(pixels, format: format, maxWidth: Int(maximum), quality: quality)
        try Task.checkCancellation()
        try validate()
        return captureResult(encoded, mode: mode)
    }

    private static func captureResult(_ encoded: BrowserAgentImageEncoder.Encoded, mode: String) -> CallTool.Result {
        .init(content: [.text(text: "{\"mode\":\"\(mode)\",\"width\":\(encoded.width),\"height\":\(encoded.height),\"mimeType\":\"\(encoded.mimeType)\"}", annotations: nil, _meta: nil),
                        .image(data: encoded.data, mimeType: encoded.mimeType, annotations: nil, _meta: nil)],
              structuredContent: .object(["mode": .string(mode), "width": .int(encoded.width), "height": .int(encoded.height), "mimeType": .string(encoded.mimeType)]))
    }

    private static func optionalText(_ args: [String: Value], _ key: String) -> String? { if case .string(let text) = args[key] { return text }; return nil }
    private static func text(_ args: [String: Value], _ key: String, maximum: Int) throws -> String {
        guard let value = optionalText(args, key), !value.isEmpty, value.utf8.count <= maximum else { throw PageError("invalid_argument", "\(key) must be a bounded nonempty string.") }; return value
    }
    private static func flag(_ args: [String: Value], _ key: String) -> Bool { if case .bool(let flag) = args[key] { return flag }; return false }
    private static func stringArray(_ value: Value?) throws -> [String] {
        guard let value else { return [] }
        guard case .array(let values) = value, values.count <= 64 else { throw PageError("invalid_argument", "properties must contain at most 64 CSS property names.") }
        return try values.map {
            guard case .string(let text) = $0, !text.isEmpty, text.utf8.count <= 64 else { throw PageError("invalid_argument", "Each CSS property must be a bounded nonempty string.") }
            return text
        }
    }
    private static func boundedNumber(_ args: [String: Value], _ key: String, fallback: Double, range: ClosedRange<Double>) throws -> Double {
        let value: Double
        switch args[key] { case .double(let number): value = number; case .int(let number): value = Double(number); case nil: value = fallback; default: throw PageError("invalid_argument", "\(key) must be numeric.") }
        guard value.isFinite, range.contains(value) else { throw PageError("invalid_argument", "\(key) is outside supported bounds.") }; return value
    }
    private struct PageError: LocalizedError { let code: String; let message: String; init(_ code: String, _ message: String) { self.code = code; self.message = message }; var errorDescription: String? { "\(code): \(message)" } }
}

#endif
