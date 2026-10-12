#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER
	import Foundation
	import Network

	struct BrowserAgentHTTPRequest {
		let method: String
		let path: String
		let headers: [String: String]
		let body: Data
	}

	enum BrowserAgentHTTPParser {
		enum Result {
			case incomplete
			case invalid
			case request(BrowserAgentHTTPRequest)
		}

		static let bodyLimit = 1_048_576
		static let headerLimit = 16384

		static func parse(_ data: Data) -> Result {
			guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
				return data.count > headerLimit ? .invalid : .incomplete
			}
			guard separator.lowerBound <= headerLimit,
			      let head = String(data: data[..<separator.lowerBound], encoding: .utf8)
			else { return .invalid }
			let lines = head.components(separatedBy: "\r\n")
			guard let first = lines.first else { return .invalid }
			let request = first.components(separatedBy: " ")
			guard request.count == 3, request[2] == "HTTP/1.1",
			      ["POST", "GET", "DELETE"].contains(request[0]), request[1].hasPrefix("/")
			else { return .invalid }
			var headers: [String: String] = [:]
			let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")
			for line in lines.dropFirst() {
				guard let colon = line.firstIndex(of: ":") else { return .invalid }
				let name = String(line[..<colon])
				guard !name.isEmpty, name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return .invalid }
				let key = name.lowercased()
				let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
				guard headers[key] == nil, !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return .invalid }
				headers[key] = value
			}
			guard headers["transfer-encoding"] == nil, headers["host"] != nil,
			      request[0] != "POST" || headers["content-length"] != nil
			else { return .invalid }
			let rawLength = headers["content-length"] ?? "0"
			guard !rawLength.isEmpty, rawLength.allSatisfy({ $0.isASCII && $0.isNumber }),
			      let length = Int(rawLength), length <= bodyLimit
			else { return .invalid }
			let bodyStart = separator.upperBound
			guard data.count - bodyStart <= length else { return .invalid }
			guard data.count - bodyStart == length else { return .incomplete }
			return .request(BrowserAgentHTTPRequest(method: request[0], path: request[1], headers: headers, body: Data(data[bodyStart...])))
		}
	}

	@MainActor
	final class BrowserAgentHTTP {
		struct Response {
			let status: Int
			var headers: [String: String] = [:]
			var body = Data()
		}

		private let listener: NWListener
		private var connections: [UUID: NWConnection] = [:]
		private var deadlines: [UUID: Task<Void, Never>] = [:]
		private var requests: [UUID: Task<Void, Never>] = [:]
		private let handler: (BrowserAgentHTTPRequest) async -> Response

		init(port: UInt16, state: @escaping @MainActor @Sendable (NWListener.State) -> Void, handler: @escaping (BrowserAgentHTTPRequest) async -> Response) throws {
			self.handler = handler
			let parameters = NWParameters.tcp
			parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
			listener = try NWListener(using: parameters)
			listener.stateUpdateHandler = { value in
				Task { @MainActor in state(value) }
			}
			listener.newConnectionHandler = { [weak self] connection in
				Task { @MainActor in self?.accept(connection) }
			}
		}

		func start() {
			listener.start(queue: .main)
		}

		func stop() {
			listener.cancel()
			for id in Array(connections.keys) {
				finish(id)
			}
		}

		private func accept(_ connection: NWConnection) {
			guard connections.count < 32 else { connection.cancel(); return }
			let id = UUID()
			connections[id] = connection
			connection.stateUpdateHandler = { [weak self] state in
				if case .failed = state {
					Task { @MainActor in self?.finish(id) }
				}
			}
			deadlines[id] = Task { [weak self] in
				do { try await Task.sleep(for: .seconds(30)) } catch { return }
				self?.finish(id)
			}
			connection.start(queue: .main)
			receive(id, buffer: Data())
		}

		private func receive(_ id: UUID, buffer: Data) {
			guard let connection = connections[id] else { return }
			connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
				Task { @MainActor in
					guard let self, self.connections[id] != nil else { return }
					var accumulated = buffer
					if let data {
						accumulated.append(data)
					}
					switch BrowserAgentHTTPParser.parse(accumulated) {
						case .invalid:
							self.write(Response(status: 400), id: id)
						case .incomplete:
							if complete || error != nil {
								self.finish(id)
							} else {
								self.receive(id, buffer: accumulated)
							}
						case let .request(request):
							self.requests[id] = Task { [weak self] in
								guard let self else { return }
								let response = await handler(request)
								guard !Task.isCancelled else { return }
								write(response, id: id)
							}
					}
				}
			}
		}

		private func write(_ response: Response, id: UUID) {
			guard let connection = connections[id] else { return }
			var headers = response.headers
			headers["Content-Length"] = String(response.body.count)
			headers["Connection"] = "close"
			let head = "HTTP/1.1 \(response.status) Response\r\n" + headers.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
			connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { [weak self] _ in
				Task { @MainActor in self?.finish(id) }
			})
		}

		private func finish(_ id: UUID) {
			connections.removeValue(forKey: id)?.cancel()
			deadlines.removeValue(forKey: id)?.cancel()
			requests.removeValue(forKey: id)?.cancel()
		}
	}
#endif
