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
	enum Category: String, Sendable {
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

	nonisolated private static let stateLock = NSLock()
	nonisolated(unsafe) private static var bootstrapped = false
	nonisolated(unsafe) private static var watchdogTimer: DispatchSourceTimer?
	nonisolated(unsafe) private static var lastMainAckNanoseconds = DispatchTime.now().uptimeNanoseconds
	nonisolated(unsafe) private static var lastStallReportNanoseconds: UInt64 = 0

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
		#if DEBUG
			emit(.trace, category, event, message(), metadata: metadata(), file: file, function: function, line: line)
		#endif
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
		#if DEBUG
			emit(.debug, category, event, message(), metadata: metadata(), file: file, function: function, line: line)
		#endif
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
		emit(.fault, category, event, message(), metadata: metadata(), file: file, function: function, line: line)
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
		let milliseconds = max(0, (clock() - started) * 1000)
		var values = metadata()
		values["elapsed_ms"] = String(format: "%.1f", milliseconds)
		if milliseconds >= warnAboveMilliseconds {
			warning(category, event, metadata: values)
		} else {
			debug(category, event, metadata: values)
		}
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
		let nsError = error as NSError
		#if DEBUG
			let keys = nsError.userInfo.keys.map { String(describing: $0) }.sorted().joined(separator: ",")
			return "\(nsError.domain):\(nsError.code) \(nsError.localizedDescription) userInfoKeys=[\(keys)]"
		#else
			return "\(nsError.domain):\(nsError.code)"
		#endif
	}

	nonisolated private static func emit(
		_ level: Level,
		_ category: Category,
		_ event: String,
		_ message: String,
		metadata: [String: String],
		file: StaticString,
		function: StaticString,
		line: UInt
	) {
		let logger = Logger(subsystem: subsystem, category: category.rawValue)
		var components = ["[ASTRA]", "[\(event)]"]
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
		#if DEBUG
			components.append("| source=\(String(describing: file)):\(line) \(String(describing: function))")
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

	nonisolated private static func clean(_ value: String) -> String {
		value
			.replacingOccurrences(of: "\n", with: "\\n")
			.replacingOccurrences(of: "\r", with: "\\r")
			.replacingOccurrences(of: "\t", with: "\\t")
	}

	nonisolated private static func startMainThreadWatchdog() {
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

	nonisolated private static func watchdogTick() {
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
