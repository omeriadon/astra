import Dispatch
import Foundation
import OSLog

/// Central structured logging for Astra.
///
/// Release logs deliberately keep user content compact/redacted. Debug builds are
/// intentionally much richer so a development console can reconstruct state
/// transitions, URLs, file locations, identifiers, timings, and failure context.
///
/// Never put password values, cookies, authorization header values, request bodies,
/// AI API keys, or other credentials in metadata. request(_:) logs header names
/// and body sizes, not values.
enum BrowserLog {
	/// Start of application code, after dyld but before NSApplication setup.
	/// This does not include pre-main executable mapping.
	@MainActor private(set) static var mainEntryUptime: TimeInterval?
	@MainActor static func markMainEntry() {
		guard mainEntryUptime == nil else { return }
		mainEntryUptime = clock()
		notice(.lifecycle, "startup.main-entered")
	}

	enum Category: String, CaseIterable, Sendable {
		case lifecycle
		case browser
		case tabs
		case spaces
		case navigation
		case webKit = "webkit"
		case persistence
		case sync
		case downloads
		case extensions
		case permissions
		case contentBlocking = "content-blocking"
		case ai
		case search
		case favicons
		case websiteApps = "website-apps"
		case agent
		case performance
		case diagnostics
	}

	enum Level: String, Sendable {
		case trace
		case debug
		case info
		case notice
		case warning
		case error
		case fault
	}

	nonisolated static let subsystem = "com.omeriadon.astra"
	/// Routine lifecycle and success events stay out of the default console. Failure
	/// boundaries remain enabled; DEBUG tooling can opt into the quieter levels.
	nonisolated static let verboseEnabled = ["1", "true", "yes"].contains(
		ProcessInfo.processInfo.environment["ASTRA_LOG_VERBOSE"]?.lowercased()
	) || ["1", "true", "yes"].contains(
		ProcessInfo.processInfo.environment["ASTRA_PERFORMANCE_BENCHMARK"]?.lowercased()
	)
	private nonisolated static let loggers = Dictionary(
		uniqueKeysWithValues: Category.allCases.map {
			($0, Logger(subsystem: subsystem, category: $0.rawValue))
		}
	)

	private nonisolated static let stateLock = NSLock()
	private nonisolated(unsafe) static var bootstrapped = false
	private nonisolated(unsafe) static var watchdogTimer: DispatchSourceTimer?
	private nonisolated(unsafe) static var lastMainAckNanoseconds = DispatchTime.now().uptimeNanoseconds
	private nonisolated(unsafe) static var lastStallReportNanoseconds: UInt64 = 0

	nonisolated static func bootstrap() {
		stateLock.lock()
		let shouldStart = !bootstrapped
		if shouldStart {
			bootstrapped = true
		}
		stateLock.unlock()
		guard shouldStart else { return }

		let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
		let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
		#if DEBUG
			let configuration = "debug"
		#else
			let configuration = "release"
		#endif
		info(
			.lifecycle,
			"process.bootstrap",
			metadata: [
				"version": version,
				"build": build,
				"configuration": configuration,
				"pid": String(ProcessInfo.processInfo.processIdentifier),
				"os": ProcessInfo.processInfo.operatingSystemVersionString,
			]
		)
		startMainThreadWatchdog()
	}

	nonisolated static func trace(
		_ category: Category,
		_ event: String,
		_ message: @autoclosure () -> String = "",
		metadata: @autoclosure () -> [String: String] = [:],
		file: StaticString = #fileID,
		function: StaticString = #function,
		line: UInt = #line
	) {
		guard isEnabled(.trace) else { return }
		emit(.trace, category, event, message(), metadata: metadata(), file: file, function: function, line: line)
	}

	nonisolated static func debug(
		_ category: Category,
		_ event: String,
		_ message: @autoclosure () -> String = "",
		metadata: @autoclosure () -> [String: String] = [:],
		file: StaticString = #fileID,
		function: StaticString = #function,
		line: UInt = #line
	) {
		guard isEnabled(.debug) else { return }
		emit(.debug, category, event, message(), metadata: metadata(), file: file, function: function, line: line)
	}

	nonisolated static func info(
		_ category: Category,
		_ event: String,
		_ message: @autoclosure () -> String = "",
		metadata: @autoclosure () -> [String: String] = [:],
		file: StaticString = #fileID,
		function: StaticString = #function,
		line: UInt = #line
	) {
		guard isEnabled(.info) else { return }
		emit(.info, category, event, message(), metadata: metadata(), file: file, function: function, line: line)
	}

	nonisolated static func notice(
		_ category: Category,
		_ event: String,
		_ message: @autoclosure () -> String = "",
		metadata: @autoclosure () -> [String: String] = [:],
		file: StaticString = #fileID,
		function: StaticString = #function,
		line: UInt = #line
	) {
		guard isEnabled(.notice) else { return }
		emit(.notice, category, event, message(), metadata: metadata(), file: file, function: function, line: line)
	}

	nonisolated static func warning(
		_ category: Category,
		_ event: String,
		_ message: @autoclosure () -> String = "",
		metadata: @autoclosure () -> [String: String] = [:],
		file: StaticString = #fileID,
		function: StaticString = #function,
		line: UInt = #line
	) {
		guard isEnabled(.warning) else { return }
		emit(.warning, category, event, message(), metadata: metadata(), file: file, function: function, line: line)
	}

	nonisolated static func error(
		_ category: Category,
		_ event: String,
		_ message: @autoclosure () -> String = "",
		metadata: @autoclosure () -> [String: String] = [:],
		file: StaticString = #fileID,
		function: StaticString = #function,
		line: UInt = #line
	) {
		guard isEnabled(.error) else { return }
		emit(.error, category, event, message(), metadata: metadata(), file: file, function: function, line: line)
	}

	nonisolated static func fault(
		_ category: Category,
		_ event: String,
		_ message: @autoclosure () -> String = "",
		metadata: @autoclosure () -> [String: String] = [:],
		file: StaticString = #fileID,
		function: StaticString = #function,
		line: UInt = #line
	) {
		guard isEnabled(.fault) else { return }
		emit(.fault, category, event, message(), metadata: metadata(), file: file, function: function, line: line)
	}

	nonisolated static func isEnabled(_ level: Level) -> Bool {
		switch level {
			case .warning, .error, .fault: true
			default: verboseEnabled
		}
	}

	@discardableResult
	nonisolated static func clock() -> TimeInterval {
		ProcessInfo.processInfo.systemUptime
	}

	nonisolated static func duration(
		_ category: Category,
		_ event: String,
		since started: TimeInterval,
		warnAboveMilliseconds: Double = 250,
		metadata: @autoclosure () -> [String: String] = [:]
	) {
		guard verboseEnabled else { return }
		let milliseconds = max(0, (clock() - started) * 1000)
		if milliseconds >= warnAboveMilliseconds {
			var values = metadata()
			values["elapsed_ms"] = String(format: "%.1f", milliseconds)
			warning(category, event, metadata: values)
			return
		}
		#if DEBUG
			var values = metadata()
			values["elapsed_ms"] = String(format: "%.1f", milliseconds)
			debug(category, event, metadata: values)
		#endif
	}

	/// Full URL in Debug except embedded credentials and obvious secret/token fields.
	/// Release logs only scheme/host plus a path marker.
	nonisolated static func url(_ url: URL?) -> String {
		guard let url else { return "nil" }
		#if DEBUG
			if url.isFileURL {
				return url.absoluteString
			}
			guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
				return "\(url.scheme ?? "?")://\(url.host ?? "?")\(url.path)"
			}
			components.user = nil
			components.password = nil
			let secretNames = ["token", "password", "passwd", "secret", "authorization", "auth", "api_key", "apikey", "credential", "session", "code"]
			if let items = components.queryItems {
				components.queryItems = items.map { item in
					let name = item.name.lowercased()
					let isSecret = secretNames.contains { name.contains($0) }
					return URLQueryItem(name: item.name, value: isSecret && item.value != nil ? "<redacted>" : item.value)
				}
			}
			if let fragment = components.fragment?.lowercased(),
			   secretNames.contains(where: { fragment.contains($0) })
			{
				components.fragment = "<redacted>"
			}
			return components.url?.absoluteString ?? "\(url.scheme ?? "?")://\(url.host ?? "?")\(url.path)"
		#else
			if url.isFileURL {
				return "file://…/\(url.lastPathComponent)"
			}
			let scheme = url.scheme ?? "?"
			let host = url.host ?? "?"
			let pathMarker = url.path.isEmpty || url.path == "/" ? "" : "/…"
			return "\(scheme)://\(host)\(pathMarker)"
		#endif
	}

	/// Full local path in Debug; basename only in Release.
	nonisolated static func path(_ url: URL?) -> String {
		guard let url else { return "nil" }
		#if DEBUG
			return url.path
		#else
			return "…/\(url.lastPathComponent)"
		#endif
	}

	/// Full arbitrary user text in Debug; byte-count marker in Release.
	nonisolated static func value(_ value: String?) -> String {
		guard let value else { return "nil" }
		#if DEBUG
			return value
		#else
			return "<redacted:\(value.utf8.count)b>"
		#endif
	}

	nonisolated static func id(_ id: UUID?) -> String {
		guard let id else { return "nil" }
		#if DEBUG
			return id.uuidString
		#else
			return String(id.uuidString.prefix(8))
		#endif
	}

	nonisolated static func request(_ request: URLRequest?) -> String {
		guard let request else { return "nil" }
		var fields = [
			"method=\(request.httpMethod ?? "GET")",
			"url=\(url(request.url))",
			"body_bytes=\(request.httpBody?.count ?? 0)",
		]
		#if DEBUG
			let names = request.allHTTPHeaderFields?.keys.sorted().joined(separator: ",") ?? ""
			fields.append("header_names=\(names)")
		#endif
		return fields.joined(separator: " ")
	}

	nonisolated static func errorDescription(_ error: Error) -> String {
		let chain = errorChain(error)
		let rendered = chain.map { item in
			var value = "\(item.domain):\(item.code) type=\(item.typeName)"
			if let decoding = item.decoding {
				value += " decoding=\(decoding)"
			}
			if !item.safeContext.isEmpty {
				value += " " + item.safeContext
			}
			if let decodingDetail = item.decodingDetail {
				value += " \(decodingDetail)"
			}
			#if DEBUG
				value += " \(redactSensitive(clean(item.message)))"
			#else
				if !item.message.isEmpty {
					value += " message_bytes=\(item.message.utf8.count)"
				}
			#endif
			#if DEBUG
				if !item.userInfoKeys.isEmpty {
					value += " userInfoKeys=[\(item.userInfoKeys.joined(separator: ","))]"
				}
				if !item.codingPath.isEmpty {
					value += " codingPath=\(item.codingPath.joined(separator: "."))"
				}
			#else
				if !item.userInfoKeys.isEmpty {
					value += " userInfoCount=\(item.userInfoKeys.count)"
				}
				if !item.codingPath.isEmpty {
					value += " codingPathCount=\(item.codingPath.count)"
				}
			#endif
			return value
		}.joined(separator: " <- ")
		guard rendered.count > 4096 else { return rendered }
		return String(rendered.prefix(4000)) + " <truncated:\(rendered.count)chars>"
	}

	private struct ErrorItem {
		let domain: String
		let code: Int
		let message: String
		let userInfoKeys: [String]
		let codingPath: [String]
		let typeName: String
		let decoding: String?
		let decodingDetail: String?
		let safeContext: String
	}

	private nonisolated static func errorChain(_ error: Error) -> [ErrorItem] {
		var result: [ErrorItem] = []
		var current: Error? = error
		var seen = Set<ObjectIdentifier>()
		while let value = current, result.count < 8 {
			let nsError = value as NSError
			let identity = ObjectIdentifier(nsError)
			guard seen.insert(identity).inserted else { break }
			let codingPath: [String]
			let decoding: String?
			let decodingDetail: String?
			var decodingCause: Error?
			if case let DecodingError.dataCorrupted(context) = value {
				decoding = "dataCorrupted"
				decodingDetail = nil
				codingPath = context.codingPath.map(\.stringValue)
				decodingCause = context.underlyingError
			} else if case let DecodingError.keyNotFound(key, context) = value {
				decoding = "keyNotFound"
				#if DEBUG
					decodingDetail = "missingKey=\(clean(key.stringValue))"
				#else
					decodingDetail = "missingKeyPresent=true"
				#endif
				codingPath = context.codingPath.map(\.stringValue)
				decodingCause = context.underlyingError
			} else if case let DecodingError.typeMismatch(expected, context) = value {
				decoding = "typeMismatch"
				decodingDetail = "expectedType=\(String(reflecting: expected))"
				codingPath = context.codingPath.map(\.stringValue)
				decodingCause = context.underlyingError
			} else if case let DecodingError.valueNotFound(expected, context) = value {
				decoding = "valueNotFound"
				decodingDetail = "expectedType=\(String(reflecting: expected))"
				codingPath = context.codingPath.map(\.stringValue)
				decodingCause = context.underlyingError
			} else {
				decoding = nil
				decodingDetail = nil
				codingPath = []
			}
			result.append(ErrorItem(
				domain: nsError.domain,
				code: nsError.code,
				message: nsError.localizedDescription,
				userInfoKeys: nsError.userInfo.keys.map { String(describing: $0) }.sorted(),
				codingPath: codingPath,
				typeName: String(reflecting: type(of: value)),
				decoding: decoding,
				decodingDetail: decodingDetail,
				safeContext: safeErrorContext(nsError)
			))
			current = decodingCause ?? nsError.userInfo[NSUnderlyingErrorKey] as? Error
		}
		return result
	}

	private nonisolated static func emit(
		_ level: Level,
		_ category: Category,
		_ event: String,
		_ message: String,
		metadata: [String: String],
		file: StaticString,
		function: StaticString,
		line: UInt
	) {
		guard let logger = loggers[category] else { return }
		var components = ["[ASTRA]", "[\(level.rawValue.uppercased())]", "[\(category.rawValue)]", "[\(event)]"]
		if !message.isEmpty {
			components.append(clean(message))
		}
		if !metadata.isEmpty {
			let rendered = metadata
				.sorted { $0.key < $1.key }
				.map { "\(clean($0.key))=\(clean($0.value))" }
				.joined(separator: " ")
			components.append("| \(rendered)")
		}
		components.append("| source=\(String(describing: file)):\(line) \(String(describing: function))")
		#if DEBUG
			components.append("thread=\(Thread.isMainThread ? "main" : "background")")
		#endif
		let rendered = components.joined(separator: " ")
		switch level {
			case .trace, .debug:
				logger.debug("\(rendered, privacy: .public)")
			case .info:
				logger.info("\(rendered, privacy: .public)")
			case .notice:
				logger.notice("\(rendered, privacy: .public)")
			case .warning:
				logger.warning("\(rendered, privacy: .public)")
			case .error:
				logger.error("\(rendered, privacy: .public)")
			case .fault:
				logger.fault("\(rendered, privacy: .public)")
		}
	}

	private nonisolated static func clean(_ value: String) -> String {
		let bounded = value.count > 4096
			? String(value.prefix(4000)) + " <truncated:\(value.count)chars>"
			: value
		return bounded
			.replacingOccurrences(of: "\n", with: "\\n")
			.replacingOccurrences(of: "\r", with: "\\r")
			.replacingOccurrences(of: "\t", with: "\\t")
	}

	private nonisolated static func safeErrorContext(_ error: NSError) -> String {
		var fields: [String] = []
		if [NSCocoaErrorDomain, NSURLErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain].contains(error.domain) {
			let reason = NSError(domain: error.domain, code: error.code).localizedDescription
			fields.append("reason=\(clean(reason))")
		}
		for key in [NSURLErrorFailingURLErrorKey, "NSErrorFailingURLStringKey"] {
			if let value = error.userInfo[key] as? URL {
				fields.append("failing_url=\(url(value))")
				break
			}
			if let value = error.userInfo[key] as? String, let valueURL = URL(string: value) {
				fields.append("failing_url=\(url(valueURL))")
				break
			}
		}
		if let value = error.userInfo[NSFilePathErrorKey] as? String {
			fields.append("failing_path=\(path(URL(fileURLWithPath: value)))")
		}
		for key in ["NSURLErrorNetworkUnavailableReasonKey", "NSURLErrorBackgroundTaskCancelledReasonKey"] {
			if let value = error.userInfo[key] as? NSNumber {
				fields.append("\(key)=\(value)")
			}
		}
		return fields.joined(separator: " ")
	}

	private nonisolated static func redactSensitive(_ value: String) -> String {
		var result = value
		let patterns = [
			#"(?i)\bBearer\s+[^\s,;"'<>]+"#,
			#"(?i)(?:["']?(?:[a-z_]*token|password|passwd|secret|api[_-]?key|authorization|cookies?|private[_-]?key)["']?)\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|'[^']*'|[^\s,;}]+)"#,
			#"(?i)https?://[^\s"<>]+"#,
		]
		for pattern in patterns {
			result = result.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
		}
		return result
	}

	private nonisolated static func startMainThreadWatchdog() {
		stateLock.lock()
		guard watchdogTimer == nil else {
			stateLock.unlock()
			return
		}
		lastMainAckNanoseconds = DispatchTime.now().uptimeNanoseconds
		let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.omeriadon.astra.watchdog", qos: .utility))
		watchdogTimer = timer
		stateLock.unlock()

		#if DEBUG
			timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250), leeway: .milliseconds(50))
			let intervalMilliseconds = "250"
		#else
			timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1), leeway: .milliseconds(100))
			let intervalMilliseconds = "1000"
		#endif
		timer.setEventHandler {
			watchdogTick()
		}
		timer.resume()
		debug(.performance, "watchdog.started", metadata: ["interval_ms": intervalMilliseconds])
	}

	private nonisolated static func watchdogTick() {
		let now = DispatchTime.now().uptimeNanoseconds
		stateLock.lock()
		let acknowledged = lastMainAckNanoseconds
		let lastReport = lastStallReportNanoseconds
		stateLock.unlock()

		#if DEBUG
			let threshold: UInt64 = 500_000_000
		#else
			let threshold: UInt64 = 2_000_000_000
		#endif
		if now > acknowledged, now - acknowledged >= threshold, now - lastReport >= 3_000_000_000 {
			let milliseconds = Double(now - acknowledged) / 1_000_000
			fault(
				.performance,
				"main-thread.stall",
				metadata: ["unresponsive_ms": String(format: "%.0f", milliseconds)]
			)
			stateLock.lock()
			lastStallReportNanoseconds = now
			stateLock.unlock()
		}

		DispatchQueue.main.async {
			let acknowledged = DispatchTime.now().uptimeNanoseconds
			stateLock.lock()
			lastMainAckNanoseconds = acknowledged
			stateLock.unlock()
		}
	}
}
