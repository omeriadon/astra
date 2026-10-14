#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER
import AppKit
import WebKit

/// Native user-selected, opaque upload authorization. No agent-supplied paths are accepted.
@MainActor
final class BrowserAgentUploadScopes {
    static let shared = BrowserAgentUploadScopes()
    private struct Scope {
        let owner: ObjectIdentifier
        let urls: [URL]
        let expires: Date
    }
    private struct Armed {
        let id: UUID
        let token: String
        let document: Int
        let expires: Date
        let validate: @MainActor () throws -> Void
    }
    private var scopes: [String: Scope] = [:]
    private var approvals: [ObjectIdentifier: NSOpenPanel] = [:]
    private var armed: [ObjectIdentifier: Armed] = [:]
    private var completed: [ObjectIdentifier: Bool] = [:]
    private var waiters: [ObjectIdentifier: CheckedContinuation<Bool, Never>] = [:]

    func approveFiles(controller: BrowserController) async -> String? {
        guard let view = controller.webViewIfLoaded, let window = view.window,
              !controller.isInvalidated, controller.hasCurrentPageDocument else { return nil }
        let owner = ObjectIdentifier(controller)
        guard approvals[owner] == nil else { return nil }
        let document = controller.navigationIdentifier
        let panel = NSOpenPanel()
        approvals[owner] = panel
        defer { if approvals[owner] === panel { approvals[owner] = nil } }
        panel.title = "Allow agent file upload"
        panel.message = "Choose files this agent may upload in this shared tab. Approval expires in ten minutes."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        let response = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            Task { @MainActor in self.approvals[owner]?.cancel(nil) }
        }
        guard response == .OK, !Task.isCancelled, !controller.isInvalidated,
              document == controller.navigationIdentifier, (1...16).contains(panel.urls.count) else {
            for url in panel.urls { url.stopAccessingSecurityScopedResource() }
            return nil
        }
        let token = UUID().uuidString
        for url in panel.urls { _ = url.startAccessingSecurityScopedResource() }
        scopes[token] = Scope(owner: ObjectIdentifier(controller), urls: panel.urls, expires: Date().addingTimeInterval(600))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(600))
            self?.discard(token: token)
        }
        return token
    }

    func arm(token: String, controller: BrowserController, validate: @escaping @MainActor () throws -> Void) throws {
        try validate()
        let owner = ObjectIdentifier(controller)
        #if DEBUG
        if BrowserAgentTestBootstrap.isActive, scopes[token] == nil {
            let environment = ProcessInfo.processInfo.environment
            if environment["ASTRA_BROWSER_USE_UPLOAD_SCOPE"] == token,
               let path = environment["ASTRA_BROWSER_USE_UPLOAD_FILE"], path.hasPrefix("/") {
                scopes[token] = Scope(owner: owner, urls: [URL(fileURLWithPath: path)], expires: Date().addingTimeInterval(600))
            }
        }
        #endif
        for token in scopes.keys.filter({ scopes[$0]!.expires <= Date() }) {
            discard(token: token)
        }
        guard let scope = scopes[token], scope.owner == owner else {
            throw UploadError("file_scope_required: Choose files with Astra's native upload approval first.")
        }
        guard armed[owner] == nil, waiters[owner] == nil else {
            throw UploadError("upload_in_progress: A file selection is already pending in this tab.")
        }
        completed[owner] = nil
        let id = UUID()
        armed[owner] = Armed(id: id, token: token, document: controller.navigationIdentifier,
                             expires: Date().addingTimeInterval(30), validate: validate)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, self.armed[owner]?.id == id else { return }
            self.armed[owner] = nil
            self.finish(owner: owner, selected: false)
        }
    }

    /// Consumed exactly once by WebKit's public file-panel delegate.
    func consume(controller: BrowserController, parameters: WKOpenPanelParameters) -> [URL]? {
        let owner = ObjectIdentifier(controller)
        guard let request = armed.removeValue(forKey: owner) else { return nil }
        guard let scope = scopes[request.token] else {
            finish(owner: owner, selected: false)
            return []
        }
        guard request.expires > Date(), request.document == controller.navigationIdentifier,
              (try? request.validate()) != nil, scope.owner == owner,
              scope.expires > Date(), parameters.allowsMultipleSelection || scope.urls.count == 1 else {
            discard(token: request.token)
            finish(owner: owner, selected: false)
            return []
        }
        scopes[request.token] = nil
        finish(owner: owner, selected: true)
        return scope.urls
    }

    func waitForSelection(controller: BrowserController) async -> Bool {
        let owner = ObjectIdentifier(controller)
        return await withTaskCancellationHandler {
            if Task.isCancelled { cancel(owner: owner); return false }
            if let selected = completed.removeValue(forKey: owner) { return selected }
            return await withCheckedContinuation { waiters[owner] = $0 }
        } onCancel: {
            Task { @MainActor in self.cancel(owner: owner) }
        }
    }

    private func finish(owner: ObjectIdentifier, selected: Bool) {
        if let waiter = waiters.removeValue(forKey: owner) { waiter.resume(returning: selected) }
        else { completed[owner] = selected }
    }
    func cancel(controller: BrowserController) { cancel(owner: ObjectIdentifier(controller)) }
    private func cancel(owner: ObjectIdentifier) {
        approvals.removeValue(forKey: owner)?.cancel(nil)
        let pending = armed.removeValue(forKey: owner) != nil || waiters[owner] != nil
        if pending { finish(owner: owner, selected: false) }
        else { completed[owner] = nil }
        for token in scopes.keys.filter({ scopes[$0]!.owner == owner }) { discard(token: token) }
    }
    private func discard(token: String) {
        guard let scope = scopes.removeValue(forKey: token) else { return }
        for url in scope.urls { url.stopAccessingSecurityScopedResource() }
    }
    private struct UploadError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
#endif
