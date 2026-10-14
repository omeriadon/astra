#if os(macOS)
	import Foundation
	import CoreFoundation
	import Observation

	#if !ASTRA_WEBSITE_APP_HELPER
		import AppKit
		import MCP
		import Security
		import WebKit
	#endif

	@MainActor
	@Observable
	final class BrowserAgentServer {
		static let shared = BrowserAgentServer()

		private(set) var isEnabled = false
		private(set) var endpoint = ""
		private(set) var status = "Disabled"
        var allowJavaScriptEvaluation = false
        var allowNativeMutations = false
        var allowBoostMutations = false

		var codexConfiguration: String {
			#if !ASTRA_WEBSITE_APP_HELPER
				guard isEnabled, !endpoint.isEmpty else { return "" }
				return """
				[mcp_servers.astra]
				url = "\(endpoint)"
				http_headers = { Authorization = "Bearer \(token)" }
				"""
			#else
				return ""
			#endif
		}

		private init() {}
        #if DEBUG && !ASTRA_WEBSITE_APP_HELPER
        var testCredential: String { token }
        #endif

		#if ASTRA_WEBSITE_APP_HELPER
			func setEnabled(_: Bool) {}
			func isControlled(_: UUID) -> Bool {
				false
			}

			func share(tab _: BrowserTab, in _: Browser) {}
			func revoke(_: UUID) {}
            func approveUploadFiles() async -> String? { nil }
		#else
			private let port: UInt16 = 8766
			private var token = ""
			private var generation = UUID()
			private var http: BrowserAgentHTTP?
            private var router: BrowserAgentProtocol?
			private var grants: [UUID: Grant] = [:]
			private var snapshots: [UUID: Snapshot] = [:]
			private var operations: [UUID: Task<CallTool.Result, Never>] = [:]
            private var operationIDs: [UUID: UUID] = [:]
            private var nativeOperations: [UUID: Task<CallTool.Result, Never>] = [:]
            private var nativeTabOperations: [UUID: UUID] = [:]

			private struct Grant {
				weak var tab: BrowserTab?
				weak var browser: Browser?
				let id = UUID()
			}

			private struct Snapshot {
				let id: String
				let controllerID: UUID
				let documentID: Int
			}

			func setEnabled(_ enabled: Bool) {
				guard enabled != isEnabled else { return }
				stop()
				guard enabled else { return }
				var bytes = [UInt8](repeating: 0, count: 32)
				let credentialStatus = unsafe SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
				guard credentialStatus == errSecSuccess else {
					BrowserLog.error(.agent, "agent.credential-generation.failed", metadata: ["os_status": String(credentialStatus)])
					status = "Could not create access credential"
					return
				}
				token = Data(bytes).base64EncodedString()
				let lifetime = generation
				do {
					let protocolRouter = BrowserAgentProtocol(token: token, port: port, tools: BrowserAgentToolCatalog.tools) { [weak self] params in
                        guard let self else { return .init(content: [.text(text: "Access revoked", annotations: nil, _meta: nil)], isError: true) }
                        return await self.callTool(params, lifetime: lifetime)
                    }
                    router = protocolRouter
                    http = try BrowserAgentHTTP(port: port, state: { [weak self] state in
						guard let self, generation == lifetime else { return }
						switch state {
							case .ready:
								endpoint = "http://127.0.0.1:\(port)/mcp"
								status = "Ready"
							case let .failed(error):
								BrowserLog.error(.agent, "agent.listener.failed", metadata: ["port": String(port), "error": BrowserLog.errorDescription(error)])
								stop()
								if case let .posix(code) = error, code == .EPERM || code == .EACCES {
									status = "This build cannot accept Browser Use connections. Rebuild Astra with Incoming Connections enabled."
								} else {
									status = "Could not start: \(error.localizedDescription)"
								}
							default:
								break
						}
					}, handler: { request in
                        await protocolRouter.handle(request)
                    })
					isEnabled = true
					status = "Starting"
					if let http { Task { await http.start() } }
				} catch {
					BrowserLog.error(.agent, "agent.server-start.failed", metadata: ["error": BrowserLog.errorDescription(error)])
					stop()
					status = "Could not start: \(error.localizedDescription)"
				}
			}

			private func stop() {
                #if !ASTRA_BROWSER_USE_FIXTURE
                for grant in grants.values {
                    if let controller = grant.tab?.controller {
                        BrowserAgentUploadScopes.shared.cancel(controller: controller)
                        BrowserAgentPageService.disableDiagnostics(controller: controller)
                    }
                }
                #endif
                isEnabled = false
				generation = UUID()
				let oldHTTP = http
                let oldRouter = router
                http = nil
                router = nil
                Task { await oldHTTP?.stop(); await oldRouter?.stop() }
                allowJavaScriptEvaluation = false
                allowNativeMutations = false
                allowBoostMutations = false
				for task in operations.values {
					task.cancel()
				}
				operations.removeAll()
                operationIDs.removeAll()
                for task in nativeOperations.values { task.cancel() }
                nativeOperations.removeAll()
                nativeTabOperations.removeAll()
                grants.removeAll()
				snapshots.removeAll()
				token = ""
				endpoint = ""
				status = "Disabled"
			}

			func isControlled(_ tabID: UUID) -> Bool {
				guard isEnabled, let grant = grants[tabID] else { return false }
				return eligible(grant)
			}

			func share(tab: BrowserTab, in browser: Browser) {
				let grant = Grant(tab: tab, browser: browser)
				guard isEnabled, eligible(grant), Self.webURL(tab.currentURL) != nil else { return }
				revoke(tab.id)
				grants[tab.id] = grant
			}

			func approveUploadFiles() async -> String? {
                #if !ASTRA_BROWSER_USE_FIXTURE
                guard let browser = BrowserWindowRegistry.shared.activeBrowser, let tab = browser.selectedTab,
                      isControlled(tab.id), let controller = tab.controller else { return nil }
                let grantID = grants[tab.id]?.id
                let token = await BrowserAgentUploadScopes.shared.approveFiles(controller: controller)
                guard isControlled(tab.id), grants[tab.id]?.id == grantID else {
                    BrowserAgentUploadScopes.shared.cancel(controller: controller)
                    return nil
                }
                return token
                #else
                return nil
                #endif
            }

            func revoke(_ tabID: UUID, cancelNative: Bool = true) {
                #if !ASTRA_BROWSER_USE_FIXTURE
                if let controller = grants[tabID]?.tab?.controller {
                    BrowserAgentUploadScopes.shared.cancel(controller: controller)
                    BrowserAgentPageService.disableDiagnostics(controller: controller)
                }
                #endif
                grants.removeValue(forKey: tabID)
				snapshots.removeValue(forKey: tabID)
				operationIDs.removeValue(forKey: tabID)
				operations.removeValue(forKey: tabID)?.cancel()
                if cancelNative, let operationID = nativeTabOperations.removeValue(forKey: tabID) {
                    nativeOperations.removeValue(forKey: operationID)?.cancel()
                }
            }

			private func eligible(_ grant: Grant) -> Bool {
				guard let tab = grant.tab, let browser = grant.browser else { return false }
				return !browser.isPrivate && !browser.isMini && tab.internalPage == nil
					&& BrowserWindowRegistry.shared.openBrowsers.contains(where: { $0 === browser })
					&& browser.tabs.contains(where: { $0 === tab })
					&& BrowserWindowRegistry.shared.ownsTab(tab.id, in: browser)
			}

			private func callTool(_ params: CallTool.Parameters, lifetime: UUID) async -> CallTool.Result {
				do {
					try Task.checkCancellation()
					guard isEnabled, generation == lifetime else { throw AgentError.revoked }
					guard BrowserAgentToolCatalog.tools.tools.contains(where: { $0.name == params.name }) else { throw AgentError.invalidArgument }
                    let typedArgs = params.arguments ?? [:]
                    let args = typedArgs.mapValues(Self.javascriptArgument)
                    #if !ASTRA_BROWSER_USE_FIXTURE
                    if BrowserAgentNativeActions.tools.contains(where: { $0.name == params.name }) {
                        let operationID = UUID()
                        let tabID: UUID?
                        if case .string(let raw)? = typedArgs["tabID"] { tabID = UUID(uuidString: raw) } else { tabID = nil }
                        if let tabID {
                            guard nativeTabOperations[tabID] == nil, operations[tabID] == nil else { throw AgentError.busy }
                            nativeTabOperations[tabID] = operationID
                        }
                        let task = Task { [weak self] () -> CallTool.Result in
                            guard let self else { return Self.failure(AgentError.revoked) }
                            do {
                                let output = try await BrowserAgentNativeActions.execute(name: params.name, arguments: typedArgs,
                                    authorizeTab: { [unowned self] id in
                                        guard let grant = self.grants[id], self.eligible(grant), let browser = grant.browser, let tab = grant.tab else { throw AgentError.revoked }
                                        guard self.operations[id] == nil else { throw AgentError.busy }
                                        return (browser, tab)
                                    }, shareTab: { [unowned self] tab, browser in
                                        self.grants[tab.id] = Grant(tab: tab, browser: browser)
                                    }, revokeTab: { [unowned self] id in self.revoke(id, cancelNative: false) }, authorizeNativeMutation: { [unowned self] in
                                        guard self.allowNativeMutations else { throw AgentError.permission }
                                    }, authorizeBoostMutation: { [unowned self] in
                                        guard self.allowBoostMutations else { throw AgentError.permission }
                                    })
                                try Task.checkCancellation()
                                guard self.isEnabled, self.generation == lifetime else { throw AgentError.revoked }
                                return try await self.structuredResult(output)
                            } catch { return Self.failure(error) }
                        }
                        nativeOperations[operationID] = task
                        let output = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
                        nativeOperations.removeValue(forKey: operationID)
                        if let tabID, nativeTabOperations[tabID] == operationID { nativeTabOperations.removeValue(forKey: tabID) }
                        guard isEnabled, generation == lifetime, !Task.isCancelled else { throw AgentError.revoked }
                        return output
                    }
                    #endif
					if params.name == "list_tabs" {
						let tabs = grants.values.filter(eligible).compactMap { grant -> [String: Any]? in
							guard let tab = grant.tab, let browser = grant.browser else { return nil }
							return ["tabID": tab.id.uuidString, "windowID": browser.windowID.uuidString, "title": tab.title, "url": tab.copyableURL.map(BrowserAddress.withoutCredentials)?.absoluteString ?? ""]
						}
						return try await result(tabs)
					}
					if params.name == "open_tab" {
						let url = try destination(args)
						let candidates = BrowserWindowRegistry.shared.openBrowsers.filter { !$0.isPrivate && !$0.isMini }
						let browser: Browser?
						if let raw = args["windowID"] as? String {
							guard let id = UUID(uuidString: raw) else { throw AgentError.invalidArgument }
							browser = candidates.first { $0.windowID == id }
						} else {
							browser = candidates.first { $0 === BrowserWindowRegistry.shared.activeBrowser } ?? candidates.first
						}
						guard let browser else { throw AgentError.unavailable }
						let tab = browser.openHistoryURL(url, inBackground: false)
						grants[tab.id] = Grant(tab: tab, browser: browser)
						return try await result(["tabID": tab.id.uuidString, "windowID": browser.windowID.uuidString, "url": url.absoluteString])
					}
					guard let raw = args["tabID"] as? String, let id = UUID(uuidString: raw),
					      let grant = grants[id], eligible(grant), let tab = grant.tab,
					      let controller = tab.activeController, controller === tab.controller,
					      Self.webURL(controller.committedURL ?? controller.url) != nil
					else { throw AgentError.revoked }
					guard operations[id] == nil, nativeTabOperations[id] == nil else { throw AgentError.busy }
					let operationID = UUID()
					let task = Task { [weak self] () -> CallTool.Result in
						guard let self else { return .init(content: [.text(text: "Access revoked", annotations: nil, _meta: nil)], isError: true) }
						do {
							return try await perform(params.name, args: args, grant: grant, tab: tab, controller: controller)
						} catch {
							BrowserLog.warning(.agent, "agent.tool.failed", metadata: [
								"tool": BrowserLog.value(params.name),
								"error": BrowserLog.errorDescription(error),
							])
							return Self.failure(error)
						}
					}
					operations[id] = task
					operationIDs[id] = operationID
					let output = await withTaskCancellationHandler {
						await task.value
					} onCancel: { task.cancel() }
					if operationIDs[id] == operationID {
						operations.removeValue(forKey: id)
						operationIDs.removeValue(forKey: id)
					}
					guard isEnabled, generation == lifetime, grants[id]?.id == grant.id, eligible(grant), !Task.isCancelled else { throw AgentError.revoked }
                    return output
				} catch {
					BrowserLog.warning(.agent, "agent.call.failed", metadata: [
						"tool": BrowserLog.value(params.name),
						"error": BrowserLog.errorDescription(error),
					])
					return Self.failure(error)
				}
			}

			private func validate(_ grant: Grant, tab: BrowserTab, controller: BrowserController, documentID: Int? = nil) throws {
				try Task.checkCancellation()
				guard isEnabled, grants[tab.id]?.id == grant.id, eligible(grant),
				      tab.controller === controller, tab.activeController === controller,
				      Self.webURL(controller.committedURL ?? controller.url) != nil
				else { throw AgentError.revoked }
				if let documentID, documentID != controller.navigationIdentifier {
					throw AgentError.stale
				}
			}

			private func perform(_ name: String, args: [String: Any], grant: Grant, tab: BrowserTab, controller: BrowserController) async throws -> CallTool.Result {
				try validate(grant, tab: tab, controller: controller)
				let documentID = controller.navigationIdentifier
				switch name {
					case "navigate":
						let url = try destination(args)
						snapshots.removeValue(forKey: tab.id)
						controller.load(url)
						return try await result(["navigationStarted": true, "url": url.absoluteString])
					case "read_page":
						let page = try await BrowserAIPageText.extract(from: controller)
						try validate(grant, tab: tab, controller: controller, documentID: documentID)
						return try await result(["title": page.title, "url": BrowserAddress.withoutCredentials(page.url).absoluteString, "text": String(page.text.prefix(50000)), "truncated": page.text.count > 50000])
                    case "snapshot":
                        guard controller.hasCurrentPageDocument, controller.readerHTML == nil,
                              let view = controller.webViewIfLoaded else { throw AgentError.unavailable }
                        let offset = args["offset"] as? Double ?? 0
                        let snapshotID: String
                        if offset > 0 {
                            guard let previous = snapshots[tab.id], previous.controllerID == controller.id,
                                  previous.documentID == documentID else { throw AgentError.stale }
                            snapshotID = previous.id
                        } else { snapshotID = UUID().uuidString }
                        let value = try await view.callAsyncJavaScript(BrowserAgentPageScripts.snapshot,
                            arguments: ["snapshotID": snapshotID, "options": args], in: nil, contentWorld: .defaultClient)
                        try validate(grant, tab: tab, controller: controller, documentID: documentID)
                        snapshots[tab.id] = Snapshot(id: snapshotID, controllerID: controller.id, documentID: documentID)
                        guard let value else { throw AgentError.unavailable }
                        return try await result(value)
                    case let operation where BrowserAgentToolCatalog.pageActions.contains(operation):
                        guard controller.hasCurrentPageDocument, controller.readerHTML == nil,
                              let view = controller.webViewIfLoaded else { throw AgentError.unavailable }
                        if name == "find_elements", snapshots[tab.id] == nil { throw AgentError.stale }
                        var scriptArgs: [String: Any] = ["operation": name, "snapshotID": "", "ref": "", "value": args["value"] ?? "", "dy": args["dy"] ?? 0, "options": args]
                        if let ref = args["ref"] as? String {
                            guard let snapshot = snapshots[tab.id], snapshot.controllerID == controller.id,
                                  snapshot.documentID == documentID, ref.hasPrefix(snapshot.id + ":") else { throw AgentError.stale }
                            scriptArgs["snapshotID"] = snapshot.id
                            scriptArgs["ref"] = ref
                        } else if let snapshot = snapshots[tab.id], snapshot.documentID == documentID {
                            scriptArgs["snapshotID"] = snapshot.id
                        }
                        #if !ASTRA_BROWSER_USE_FIXTURE
                        if BrowserAgentInputService.keyOperations.contains(name) {
                            guard grant.browser?.selectedTabID == tab.id else { throw AgentError.unavailable }
                            if args["ref"] != nil || args["selector"] != nil {
                                var focus = scriptArgs
                                focus["operation"] = "focus_element"
                                _ = try await view.callAsyncJavaScript(BrowserAgentPageScripts.action, arguments: focus, in: nil, contentWorld: .defaultClient)
                                try validate(grant, tab: tab, controller: controller, documentID: documentID)
                            }
                            return try await result(BrowserAgentInputService.key(name, arguments: args, view: view))
                        }
                        if args["inputMode"] as? String == "native", ["click", "double_click", "right_click", "hover", "move_pointer"].contains(name) {
                            return try await result(try await nativePointer(name, args: args, grant: grant, tab: tab, controller: controller))
                        }
                        #endif
                        let value = try await view.callAsyncJavaScript(BrowserAgentPageScripts.action, arguments: scriptArgs, in: nil, contentWorld: .defaultClient)
                        try validate(grant, tab: tab, controller: controller)
                        if ["click", "fill", "select_option", "scroll"].contains(name) {
                            return try await result(["result": value ?? NSNull(), "documentChanged": documentID != controller.navigationIdentifier])
                        }
                        return try await result(value ?? NSNull())
                    case let operation where BrowserAgentToolCatalog.waits.contains(operation):
                        let timeout = args["timeout"] as? Double ?? 5
                        guard timeout.isFinite, timeout >= 0, timeout <= 300 else { throw AgentError.invalidArgument }
                        if name == "wait_for_navigation" || name == "wait_for_url" || name == "wait_for_load_state" || (name == "wait" && args["text"] == nil) {
                            return try await waitForBrowserState(name, args: args, timeout: timeout, grant: grant, tab: tab, controller: controller)
                        }
                        guard let view = controller.webViewIfLoaded, controller.hasCurrentPageDocument else { throw AgentError.unavailable }
                        let operationID = UUID().uuidString
                        var options = args
                        options["timeoutMs"] = timeout * 1000
                        options["operationID"] = operationID
                        options["condition"] = name == "wait_for_element" ? "element" : "text"
                        if let ref = args["ref"] as? String {
                            guard let snapshot = snapshots[tab.id], snapshot.documentID == documentID,
                                  ref.hasPrefix(snapshot.id + ":") else { throw AgentError.stale }
                        }
                        let value = try await withTaskCancellationHandler {
                            try await view.callAsyncJavaScript(BrowserAgentPageScripts.wait, arguments: ["snapshotID": snapshots[tab.id]?.id ?? "", "options": options], in: nil, contentWorld: .defaultClient)
                        } onCancel: {
                            Task { @MainActor in
                                _ = try? await view.callAsyncJavaScript(BrowserAgentPageScripts.cancelWait, arguments: ["operationID": operationID], in: nil, contentWorld: .defaultClient)
                            }
                        }
                        try validate(grant, tab: tab, controller: controller, documentID: documentID)
                        return try await result(value ?? ["outcome": "unavailable"])

					default:
                        #if !ASTRA_BROWSER_USE_FIXTURE
                        if BrowserAgentPageService.tools.contains(where: { $0.name == name }) {
                            let typed = args.mapValues(Self.mcpValue)
                            return try await BrowserAgentPageService.execute(name: name, arguments: typed, controller: controller,
                                authorizeJavaScript: { [unowned self] in
                                    guard self.allowJavaScriptEvaluation else { throw AgentError.permission }
                                }, validate: { [unowned self] in
                                    try self.validate(grant, tab: tab, controller: controller, documentID: documentID)
                                }, uploadTrigger: { [unowned self] ref in
                                    _ = try await self.nativePointer("click", args: ["ref": ref, "requireFileInput": true], grant: grant, tab: tab, controller: controller)
                                })
                        }
                        #endif
                        throw AgentError.invalidArgument
				}
			}

            #if !ASTRA_BROWSER_USE_FIXTURE
            private func nativePointer(_ name: String, args: [String: Any], grant: Grant, tab: BrowserTab, controller: BrowserController) async throws -> [String: Any] {
                try validate(grant, tab: tab, controller: controller)
                guard grant.browser?.selectedTabID == tab.id, let view = controller.webViewIfLoaded else { throw AgentError.unavailable }
                let documentID = controller.navigationIdentifier
                var snapshotID = ""
                if let ref = args["ref"] as? String {
                    guard let snapshot = snapshots[tab.id], snapshot.controllerID == controller.id,
                          snapshot.documentID == documentID, ref.hasPrefix(snapshot.id + ":") else { throw AgentError.stale }
                    snapshotID = snapshot.id
                }
                let scriptArgs: [String: Any] = ["operation": "prepare_native_input", "snapshotID": snapshotID,
                    "ref": args["ref"] ?? "", "value": "", "dy": 0, "options": args]
                guard let prepared = try await view.callAsyncJavaScript(BrowserAgentPageScripts.action, arguments: scriptArgs, in: nil, contentWorld: .defaultClient) as? [String: Any],
                      let point = prepared["point"] as? [String: Any], let x = point["x"] as? Double,
                      let y = point["y"] as? Double, prepared["frame"] as? String == "main" else { throw AgentError.unavailable }
                try validate(grant, tab: tab, controller: controller, documentID: documentID)
                return try BrowserAgentInputService.pointer(name, arguments: args, view: view,
                    point: CGPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y))
            }
            #endif

            private static func failure(_ error: Error) -> CallTool.Result {
                let description = error.localizedDescription
                let code: String
                if error is CancellationError { code = "CANCELLED" }
                else if let error = error as? AgentError {
                    switch error {
                        case .invalidArgument: code = "INVALID_ARGUMENT"
                        case .unavailable: code = "UNAVAILABLE"
                        case .revoked: code = "REVOKED"
                        case .stale: code = "STALE_REFERENCE"
                        case .busy: code = "TAB_BUSY"
                        case .permission: code = "PERMISSION_DENIED"
                    }
                } else if description.lowercased().contains("timeout") { code = "TIMEOUT" }
                else { code = "OPERATION_FAILED" }
                return .init(content: [.text(text: description, annotations: nil, _meta: nil)],
                    structuredContent: .object(["code": .string(code), "message": .string(description), "outcome": .string(code.lowercased())]), isError: true)
            }

            private func structuredResult(_ value: Value) async throws -> CallTool.Result {
                try await BrowserAgentResultEncoder.shared.encode(value)
            }

            private static func javascriptArgument(_ value: Value) -> Any {
                switch value {
                    case .string(let value): return value
                    case .bool(let value): return value
                    case .int(let value): return value
                    case .double(let value): return value
                    case .array(let values): return values.map(javascriptArgument)
                    case .object(let values): return values.mapValues(javascriptArgument)
                    case .null: return NSNull()
                }
            }

            private static func mcpValue(_ value: Any) -> Value {
                if value is NSNull { return .null }
                if let value = value as? String { return .string(value) }
                if let value = value as? NSNumber {
                    if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
                    return .double(value.doubleValue)
                }
                if let value = value as? [Any] { return .array(value.map(mcpValue)) }
                if let value = value as? [String: Any] { return .object(value.mapValues(mcpValue)) }
                return .null
            }

            /// Observation re-arms only when browser state changes; no polling or text extraction.
            private func waitForBrowserState(_ name: String, args: [String: Any], timeout: Double, grant: Grant, tab: BrowserTab, controller: BrowserController) async throws -> CallTool.Result {
                let initialDocument = controller.navigationIdentifier
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(timeout))
                while true {
                    try validate(grant, tab: tab, controller: controller)
                    let matched: Bool
                    if name == "wait_for_navigation" {
                        if let previousURL = args["url"] as? String {
                            matched = controller.hasCurrentPageDocument && controller.committedURL?.absoluteString != previousURL
                        } else {
                            matched = controller.navigationIdentifier != initialDocument && controller.hasCurrentPageDocument
                        }
                    } else if name == "wait_for_url" {
                        guard let url = args["url"] as? String else { throw AgentError.invalidArgument }
                        matched = controller.committedURL?.absoluteString.contains(url) == true
                    } else {
                        matched = controller.hasCurrentPageDocument && !controller.isLoading
                    }
                    if matched { return try await result(["matched": true, "outcome": "success"]) }
                    if clock.now >= deadline { return try await result(["matched": false, "outcome": "timeout"]) }
                    let signal = BrowserAgentStateSignal()
                    withObservationTracking {
                        _ = controller.navigationIdentifier
                        _ = controller.isLoading
                        _ = controller.hasCurrentPageDocument
                        _ = controller.committedURL
                        _ = isEnabled
                        _ = grants[tab.id]?.id
                    } onChange: { signal.finish() }
                    try await signal.wait(until: deadline)
                }
            }

			private func destination(_ args: [String: Any]) throws -> URL {
				guard let raw = args["url"] as? String, raw.utf8.count <= 8192,
				      let url = Self.webURL(URL(string: raw)) else { throw AgentError.invalidArgument }
				return url
			}

			static func webURL(_ url: URL?) -> URL? {
				guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
				      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
				return url
			}

            private func result(_ object: Any) async throws -> CallTool.Result {
                try await structuredResult(Self.mcpValue(object))
            }

			private enum AgentError: LocalizedError {
				case invalidArgument, unavailable, revoked, stale, busy, permission

				var errorDescription: String? {
					switch self {
						case .permission: "PERMISSION_DENIED: Enable the separate Browser Use permission in Developer settings."
                        case .invalidArgument: "Invalid tool arguments. Only credential-free HTTP(S) URLs and bounded values are accepted."
						case .unavailable: "The page or browser window is not ready."
						case .revoked: "Access to this tab was revoked or its ownership changed."
						case .stale: "The element reference expired. Take another snapshot."
						case .busy: "Another operation is running on this tab. Wait for its result."
					}
				}
			}
		#endif
	}
#endif
