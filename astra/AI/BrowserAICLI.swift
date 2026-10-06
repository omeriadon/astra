import Foundation

nonisolated struct BrowserAIModelOption: Identifiable, Sendable {
	let id: String
	let title: String
}

@MainActor
enum BrowserAICLI {
	static func generate(_ request: BrowserAIRequest, model: BrowserAIModel) async throws -> String {
		#if os(macOS)
			let images = request.images ?? []
			let instructions = request.instructions + "\nKeep the response within \(request.maximumResponseTokens) tokens."
			let command: BrowserAICommand
			let isCodex: Bool
			switch model {
				case let .codex(modelID):
					isCodex = true
					var arguments = ["exec", "--json", "--ephemeral", "--ignore-user-config", "--skip-git-repo-check", "--sandbox", "read-only", "--disable", "shell_tool", "-c", "approval_policy=\"never\"", "-c", "model_reasoning_effort=\"low\""]
					if !modelID.isEmpty {
						arguments += ["--model", modelID]
					}
					arguments += ["-"]
					command = try BrowserAICommand(name: "codex", arguments: arguments)
				case let .claude(modelID):
					isCodex = false
					var arguments = ["--print", "--output-format", images.isEmpty ? "json" : "stream-json", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}", "--setting-sources", "", "--no-session-persistence", "--effort", "low", "--system-prompt", instructions]
					if !modelID.isEmpty {
						arguments += ["--model", modelID]
					}
					if !images.isEmpty {
						arguments += ["--input-format", "stream-json", "--verbose"]
					}
					command = try BrowserAICommand(name: "claude", arguments: arguments)
				default: throw BrowserAIError.invalidRequest
			}
			return try await withTaskCancellationHandler {
				defer { command.stop() }
				if isCodex {
					try command.attach(images)
				}
				var input = isCodex
					? "\(instructions)\nRespond only with the requested text. Do not use tools or access files.\n<page-data>\n\(request.prompt)\n</page-data>"
					: request.prompt
				if !isCodex, !images.isEmpty {
					var content: [[String: Any]] = [["type": "text", "text": request.prompt]]
					for image in images {
						content.append(["type": "text", "text": "Attached image: " + image.name])
						content.append(["type": "image", "source": ["type": "base64", "media_type": image.mediaType, "data": image.data.base64EncodedString()]])
					}
					input = try json(["type": "user", "session_id": "", "message": ["role": "user", "content": content], "parent_tool_use_id": NSNull()]) + "\n"
				}
				try command.start(input: input, closeInput: true)
				var text = ""
				var failureMessage: String?
				for try await line in command.lines {
					try Task.checkCancellation()
					guard let data = line.data(using: .utf8),
					      let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
					if isCodex {
						if ["turn.failed", "error"].contains(event["type"] as? String ?? "") {
							failureMessage = (event["error"] as? [String: Any])?["message"] as? String ?? event["message"] as? String
						}
						if event["type"] as? String == "item.completed",
						   let item = event["item"] as? [String: Any], item["type"] as? String == "agent_message",
						   let value = item["text"] as? String
						{
							text = value
						}
					} else if event["type"] as? String == "result" {
						if event["is_error"] as? Bool == true {
							failureMessage = event["result"] as? String
						}
						text = event["result"] as? String ?? ""
					}
				}
				while command.isRunning {
					try Task.checkCancellation()
					try await Task.sleep(for: .milliseconds(10))
				}
				try Task.checkCancellation()
				guard command.succeeded, failureMessage == nil, !text.isEmpty else { throw command.failure(message: failureMessage) }
				return text
			} onCancel: {
				Task { @MainActor in command.stop() }
			}
		#else
			throw BrowserAIError.cliUnavailable
		#endif
	}

	/// A new process and provider catalog query on every opening; no saved model catalog.
	static func models(provider: String) async throws -> [BrowserAIModelOption] {
		#if os(macOS)
			let codex = provider == "codex"
			let command = try BrowserAICommand(
				name: codex ? "codex" : "claude",
				arguments: codex
					? ["app-server"]
					: ["--print", "--verbose", "--input-format", "stream-json", "--output-format", "stream-json", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}", "--setting-sources", "", "--no-session-persistence"]
			)
			return try await withTaskCancellationHandler {
				let initialize: [String: Any] = codex
					? ["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "astra", "version": "1.0"]]]
					: ["type": "control_request", "request_id": "astra-models", "request": ["subtype": "initialize"]]
				try command.start(input: json(initialize) + "\n", closeInput: false)
				defer { command.stop() }
				var options: [BrowserAIModelOption] = []
				for try await line in command.lines {
					try Task.checkCancellation()
					guard let data = line.data(using: .utf8), let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
					if event["error"] != nil {
						throw BrowserAIError.cliUnavailable
					}
					if codex {
						if event["id"] as? Int == 1 {
							try command.write(json(["method": "initialized"]) + "\n")
							try command.write(json(["id": 2, "method": "model/list", "params": ["limit": 100, "includeHidden": false]]) + "\n")
						} else if event["id"] as? Int == 2, let result = event["result"] as? [String: Any] {
							let models = result["data"] as? [[String: Any]] ?? []
							options += models.compactMap { item in
								guard let id = item["model"] as? String else { return nil }
								let efforts = item["supportedReasoningEfforts"] as? [[String: Any]] ?? []
								guard efforts.isEmpty || efforts.contains(where: { $0["reasoningEffort"] as? String == "low" }) else { return nil }
								return BrowserAIModelOption(id: id, title: item["displayName"] as? String ?? id)
							}
							if let cursor = result["nextCursor"] as? String {
								try command.write(json(["id": 2, "method": "model/list", "params": ["limit": 100, "cursor": cursor]]) + "\n")
							} else {
								return options
							}
						}
					} else if event["type"] as? String == "control_response", let response = event["response"] as? [String: Any] {
						guard response["subtype"] as? String == "success", let result = response["response"] as? [String: Any] else { throw BrowserAIError.cliUnavailable }
						return (result["models"] as? [[String: Any]] ?? []).compactMap { item in
							guard let id = item["value"] as? String else { return nil }
							return BrowserAIModelOption(id: id, title: item["displayName"] as? String ?? id)
						}
					}
				}
				throw BrowserAIError.cliUnavailable
			} onCancel: {
				Task { @MainActor in command.stop() }
			}
		#else
			throw BrowserAIError.cliUnavailable
		#endif
	}

	private static func json(_ value: [String: Any]) throws -> String {
		try String(decoding: JSONSerialization.data(withJSONObject: value), as: UTF8.self)
	}
}

#if os(macOS)
	/// Pipes are drained asynchronously, and cancellation terminates the owning process.
	@MainActor
	private final class BrowserAICommand {
		private let process = Process()
		private let input = Pipe()
		private let output = Pipe()
		private let directory: URL
		private let name: String
		private let diagnosticFile: FileHandle
		private let diagnosticURL: URL
		private var timedOut = false
		private var timeout: Task<Void, Never>?
		private let chunks: AsyncStream<Data>
		private let continuation: AsyncStream<Data>.Continuation

		var isRunning: Bool {
			process.isRunning
		}

		var succeeded: Bool {
			!process.isRunning && process.terminationStatus == 0
		}

		var lines: AsyncThrowingStream<String, Error> {
			AsyncThrowingStream { continuation in
				Task {
					var buffer = Data()
					for await chunk in chunks {
						buffer.append(chunk)
						while let end = buffer.firstIndex(of: 10) {
							continuation.yield(String(decoding: buffer[..<end], as: UTF8.self))
							buffer.removeSubrange(...end)
						}
					}
					if !buffer.isEmpty {
						continuation.yield(String(decoding: buffer, as: UTF8.self))
					}
					continuation.finish()
				}
			}
		}

		init(name: String, arguments: [String]) throws {
			self.name = name
			let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
				+ ["/opt/homebrew/bin", "/usr/local/bin", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]
			guard let path = paths.map({ URL(fileURLWithPath: $0).appendingPathComponent(name).path })
				.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
				?? ["/Applications/Codex.app/Contents/Resources/codex", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path]
				.first(where: { name == "codex" && FileManager.default.isExecutableFile(atPath: $0) })
			else { throw BrowserAIError.commandMissing(name.capitalized) }
			directory = FileManager.default.temporaryDirectory.appendingPathComponent("astra-ai-\(UUID().uuidString)")
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			diagnosticURL = directory.appendingPathComponent("diagnostics.log")
			FileManager.default.createFile(atPath: diagnosticURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
			diagnosticFile = try FileHandle(forWritingTo: diagnosticURL)
			(chunks, continuation) = AsyncStream<Data>.makeStream()
			process.executableURL = URL(fileURLWithPath: path)
			process.arguments = arguments
			process.currentDirectoryURL = directory
			process.standardInput = input
			process.standardOutput = output
			process.standardError = diagnosticFile
			var environment = ProcessInfo.processInfo.environment
			environment["PATH"] = paths.joined(separator: ":")
			environment["CLAUDE_CODE_EFFORT_LEVEL"] = "low"
			process.environment = environment
		}

		func start(input text: String, closeInput: Bool) throws {
			let continuation = continuation
			output.fileHandleForReading.readabilityHandler = { handle in
				let data = handle.availableData
				if data.isEmpty {
					handle.readabilityHandler = nil
					continuation.finish()
				} else {
					continuation.yield(data)
				}
			}
			do { try process.run() } catch {
				stop()
				throw BrowserAIError.commandFailed(name.capitalized, "The installed command could not be started. Check its permissions.")
			}
			let handle = input.fileHandleForWriting
			Task.detached {
				do {
					try handle.write(contentsOf: Data(text.utf8))
					if closeInput {
						try handle.close()
					}
				} catch { continuation.finish() }
			}
			timeout = Task { [weak self] in
				do { try await Task.sleep(for: .seconds(180)) } catch { return }
				self?.timedOut = true
				self?.stop()
			}
		}

		func attach(_ images: [BrowserAIImage]) throws {
			var arguments = process.arguments ?? []
			for (index, image) in images.enumerated() {
				let extensionName = image.mediaType == "image/jpeg" ? "jpg" : image.mediaType == "image/webp" ? "webp" : image.mediaType == "image/gif" ? "gif" : "png"
				let url = directory.appendingPathComponent("image-\(index).\(extensionName)")
				try image.data.write(to: url, options: .atomic)
				arguments.insert(contentsOf: ["--image", url.path], at: max(0, arguments.count - 1))
			}
			process.arguments = arguments
		}

		func failure(message: String? = nil) -> BrowserAIError {
			if timedOut {
				return .commandTimedOut(name.capitalized)
			}
			var diagnostics = message ?? ""
			if diagnostics.isEmpty, let handle = try? FileHandle(forReadingFrom: diagnosticURL) {
				defer { try? handle.close() }
				if let size = try? handle.seekToEnd() {
					try? handle.seek(toOffset: size > 8192 ? size - 8192 : 0)
					diagnostics = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
				}
			}
			let lower = diagnostics.lowercased()
			let reason = if lower.contains("login") || lower.contains("sign in") || lower.contains("unauthorized") || lower.contains("401") || lower.contains("api key") {
				"Its existing provider account is unavailable. Connect your account in the installed command-line tool."
			} else if lower.contains("model") && (lower.contains("not supported") || lower.contains("not found") || lower.contains("not available") || lower.contains("invalid")) {
				"The selected model is unavailable for this provider account. Refresh the model selection in Developer settings."
			} else if lower.contains("rate") || lower.contains("quota") || lower.contains("429") {
				"The provider’s usage limit has been reached. Wait before trying again."
			} else if lower.contains("context") || lower.contains("too large") || lower.contains("token limit") || lower.contains("10mb") {
				"The page or attachment context is too large for this request. Remove a linked page or attachment."
			} else if lower.contains("unknown") || lower.contains("unexpected argument") || lower.contains("unrecognized") {
				"The installed command-line tool does not support this request format. Update it to a current version."
			} else if lower.contains("network") || lower.contains("connection") || lower.contains("fetch") {
				"Could not reach its provider. Check the network connection and try again."
			} else if lower.contains("permission") || lower.contains("operation not permitted") {
				"The installed command could not access its account or working files. Check its file permissions."
			} else {
				"The command stopped without a usable answer\(process.isRunning ? "" : " (exit \(process.terminationStatus))"). Try again or check the command in Terminal."
			}
			return .commandFailed(name.capitalized, reason)
		}

		func write(_ text: String) throws {
			try input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
		}

		func stop() {
			timeout?.cancel()
			if process.isRunning {
				process.terminate()
			}
			output.fileHandleForReading.readabilityHandler = nil
			continuation.finish()
			try? input.fileHandleForWriting.close()
			try? diagnosticFile.close()
			try? FileManager.default.removeItem(at: directory)
		}
	}
#endif
