import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class BrowserContentBlocking {
	static let shared = BrowserContentBlocking(isPrivate: false)
	static let defaultsKey = "nativeContentBlockingSource"

	let isPrivate: Bool
	private let defaults: UserDefaults
	private var store: WKContentRuleListStore?
	private var privateStoreDirectory: URL?
	@ObservationIgnored private var storedRecordData: Data?
	private var storedSource: BrowserContentBlockingRuleSource.Stored?
	private var privateSessionIsEnding = false
	private var idleWaiters: [CheckedContinuation<Void, Never>] = []
	private(set) var source: BrowserContentBlockingRuleSource.Validated?
	private(set) var compiledRuleList: WKContentRuleList?
	private(set) var sourceFileName: String?
	private(set) var updatedAt: Date?
	private(set) var isEnabled = false
	private(set) var isBusy = false
	private(set) var isPrepared = false
	private(set) var isPreparing = false
	private(set) var isReadOnly = false
	private(set) var errorDescription: String?
	@ObservationIgnored var didUpdate: (() -> Void)?

	init(isPrivate: Bool, defaults: UserDefaults = .standard) {
		BrowserLog.info(.contentBlocking, "content-blocking.init", metadata: ["private": String(isPrivate)])
		self.isPrivate = isPrivate
		self.defaults = defaults
		if !isPrivate {
			store = WKContentRuleListStore.default()
			storedRecordData = defaults.data(forKey: Self.defaultsKey)
		}
	}

	var isActive: Bool {
		isEnabled && compiledRuleList != nil
	}

	var isReadyForNavigation: Bool {
		isPrivate || (isPrepared && !isPreparing)
	}

	func prepare() async {
		guard !isPrivate, !isPrepared, !isBusy else {
			BrowserLog.trace(.contentBlocking, "content-blocking.prepare.skip", metadata: ["private": String(isPrivate), "prepared": String(isPrepared), "busy": String(isBusy)])
			return
		}
		let logStarted = BrowserLog.clock()
		BrowserLog.info(.contentBlocking, "content-blocking.prepare.begin")
		isPrepared = true
		guard let storedRecordData else {
			didUpdate?()
			return
		}
		isPreparing = true
		isBusy = true
		defer {
			isPreparing = false
			BrowserLog.duration(.contentBlocking, "content-blocking.prepare.end", since: logStarted, warnAboveMilliseconds: 500, metadata: ["enabled": String(isEnabled), "has_rules": String(compiledRuleList != nil), "error": BrowserLog.value(errorDescription)])
			finishOperation()
		}

		guard let stored = await Task.detached(priority: .utility, operation: {
			BrowserContentBlockingRuleSource.Stored.decodeSupported(storedRecordData)
		}).value else {
			self.storedRecordData = nil
			isReadOnly = true
			errorDescription = "Astra preserved content rules it cannot read. Remove or replace them after updating Astra."
			return
		}
		self.storedRecordData = nil
		storedSource = stored
		isEnabled = stored.isEnabled
		sourceFileName = stored.fileName
		updatedAt = stored.updatedAt

		guard let source = await Task.detached(priority: .utility, operation: {
			try? BrowserContentBlockingRuleSource.validate(stored.data)
		}).value else {
			errorDescription = "Astra preserved a content-rule source it cannot validate. Import a valid list to replace it."
			return
		}
		self.source = source

		do {
			guard let store else { throw StoreError.unavailable }
			let cachedList: WKContentRuleList?
			do {
				cachedList = try await store.contentRuleList(forIdentifier: source.identifier)
			} catch {
				cachedList = nil
			}
			if let cachedList {
				compiledRuleList = cachedList
			} else {
				compiledRuleList = try await compile(source, using: store)
			}
			errorDescription = nil
		} catch {
			errorDescription = error.localizedDescription
		}
	}

	func importRules(from url: URL) async {
		BrowserLog.info(.contentBlocking, "content-blocking.import-file", metadata: ["file": BrowserLog.path(url)])
		guard !isBusy, !privateSessionIsEnding else { return }
		guard url.pathExtension.lowercased() == "json" else {
			errorDescription = "Choose a JSON rule list no larger than 2 MB."
			return
		}
		let access = url.startAccessingSecurityScopedResource()
		defer {
			if access {
				url.stopAccessingSecurityScopedResource()
			}
		}
		do {
			let values = try? url.resourceValues(forKeys: [.fileSizeKey])
			if let fileSize = values?.fileSize,
			   fileSize > BrowserContentBlockingRuleSource.maximumBytes
			{
				throw BrowserContentBlockingRuleSource.ValidationError.sourceTooLarge
			}
			let data = try BrowserContentBlockingRuleSource.readBounded(from: url)
			await importRules(data, fileName: url.lastPathComponent)
		} catch {
			errorDescription = Self.validationMessage(for: error)
		}
	}

	func importRules(_ data: Data, fileName: String) async {
		BrowserLog.info(.contentBlocking, "content-blocking.import-data", metadata: ["file": BrowserLog.value(fileName), "bytes": String(data.count)])
		guard !isBusy, !privateSessionIsEnding else { return }
		let candidate: BrowserContentBlockingRuleSource.Validated
		do {
			candidate = try BrowserContentBlockingRuleSource.validate(data)
		} catch {
			errorDescription = Self.validationMessage(for: error)
			return
		}
		guard !isReadOnly else {
			errorDescription = "Astra preserved a content-rule record it cannot rewrite."
			return
		}
		isBusy = true
		defer { finishOperation() }
		do {
			let store = try contentRuleListStore()
			let cachedList: WKContentRuleList?
			do {
				cachedList = try await store.contentRuleList(forIdentifier: candidate.identifier)
			} catch {
				cachedList = nil
			}
			let list: WKContentRuleList = if let cachedList {
				cachedList
			} else {
				try await compile(candidate, using: store)
			}
			guard let accepted = BrowserContentBlockingRuleSource.lastGood(
				current: source,
				candidate: candidate,
				compiledIdentifier: list.identifier
			) else { throw StoreError.staleCompile }
			let updatedAt = Date.now
			let stored = BrowserContentBlockingRuleSource.Stored(
				fileName: Self.safeFileName(fileName),
				data: data,
				updatedAt: updatedAt,
				isEnabled: true
			)
			if !isPrivate {
				guard let encoded = try? JSONEncoder().encode(stored) else { throw StoreError.sourceSaveFailed }
				defaults.set(encoded, forKey: Self.defaultsKey)
				storedRecordData = nil
			}
			let previousIdentifier = source?.identifier
			source = accepted
			storedSource = stored
			compiledRuleList = list
			sourceFileName = stored.fileName
			self.updatedAt = updatedAt
			isEnabled = true
			errorDescription = nil
			didUpdate?()
			if let previousIdentifier, previousIdentifier != accepted.identifier, !isPrivate {
				try? await store.removeContentRuleList(forIdentifier: previousIdentifier)
			}
		} catch {
			errorDescription = error.localizedDescription
		}
	}

	func refresh() async {
		BrowserLog.info(.contentBlocking, "content-blocking.refresh")
		guard !isBusy, !privateSessionIsEnding, let source else { return }
		isBusy = true
		defer { finishOperation() }
		do {
			let store = try contentRuleListStore()
			let cachedList: WKContentRuleList?
			do {
				cachedList = try await store.contentRuleList(forIdentifier: source.identifier)
			} catch {
				cachedList = nil
			}
			let list: WKContentRuleList = if let cachedList {
				cachedList
			} else {
				try await compile(source, using: store)
			}
			guard list.identifier == source.identifier else { throw StoreError.staleCompile }
			compiledRuleList = list
			errorDescription = nil
		} catch {
			errorDescription = error.localizedDescription
		}
	}

	func setEnabled(_ enabled: Bool) {
		BrowserLog.notice(.contentBlocking, "content-blocking.set-enabled", metadata: ["enabled": String(enabled)])
		guard !isBusy, !privateSessionIsEnding,
		      !enabled || compiledRuleList != nil else { return }
		guard !isReadOnly else {
			errorDescription = "Astra preserved a content-rule record it cannot rewrite."
			return
		}
		isEnabled = enabled
		if !isPrivate, var storedSource {
			storedSource.isEnabled = enabled
			guard let data = try? JSONEncoder().encode(storedSource) else {
				errorDescription = StoreError.sourceSaveFailed.localizedDescription
				return
			}
			defaults.set(data, forKey: Self.defaultsKey)
			self.storedSource = storedSource
		}
		didUpdate?()
	}

	func removeRules() async {
		BrowserLog.notice(.contentBlocking, "content-blocking.remove-rules")
		guard !isBusy, !privateSessionIsEnding, !isReadOnly else { return }
		isBusy = true
		defer { finishOperation() }

		var cacheRemovalFailed = false
		if let source, let store {
			do {
				try await store.removeContentRuleList(forIdentifier: source.identifier)
			} catch {
				cacheRemovalFailed = true
			}
		}
		if !isPrivate {
			defaults.removeObject(forKey: Self.defaultsKey)
			storedRecordData = nil
		}
		source = nil
		storedSource = nil
		compiledRuleList = nil
		sourceFileName = nil
		updatedAt = nil
		isEnabled = false
		errorDescription = cacheRemovalFailed
			? "Imported rules were removed from Astra, but WebKit could not delete its compiled cache. The cached list is no longer active."
			: nil
	}

	func endPrivateSession() async {
		guard isPrivate, !privateSessionIsEnding else { return }
		privateSessionIsEnding = true
		if isBusy {
			await withCheckedContinuation { idleWaiters.append($0) }
		}
		isEnabled = false
		source = nil
		storedSource = nil
		compiledRuleList = nil
		sourceFileName = nil
		updatedAt = nil
		store = nil
		didUpdate?()
		guard let privateStoreDirectory else { return }
		do {
			try FileManager.default.removeItem(at: privateStoreDirectory)
			self.privateStoreDirectory = nil
			errorDescription = nil
		} catch {
			errorDescription = "Temporary compiled content rules could not be removed."
		}
	}

	func ruleList(for origin: String?, sitePreferences: BrowserSitePreferences) -> WKContentRuleList? {
		guard BrowserContentBlockingRuleSource.shouldApply(
			enabled: isEnabled,
			hasCompiledList: compiledRuleList != nil,
			isSiteException: origin.map(sitePreferences.disablesNativeContentBlocking(for:)) ?? false
		) else { return nil }
		return compiledRuleList
	}

	private func contentRuleListStore() throws -> WKContentRuleListStore {
		if let store {
			return store
		}
		guard isPrivate else { throw StoreError.unavailable }
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("astra-content-rules-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		guard let store = WKContentRuleListStore(url: directory) else {
			try? FileManager.default.removeItem(at: directory)
			throw StoreError.unavailable
		}
		privateStoreDirectory = directory
		self.store = store
		return store
	}

	private func compile(
		_ source: BrowserContentBlockingRuleSource.Validated,
		using store: WKContentRuleListStore
	) async throws -> WKContentRuleList {
		guard let json = String(data: source.data, encoding: .utf8),
		      let list = try await store.compileContentRuleList(
		      	forIdentifier: source.identifier,
		      	encodedContentRuleList: json
		      ) else { throw StoreError.compileFailed }
		return list
	}

	private static func safeFileName(_ value: String) -> String {
		let name = URL(fileURLWithPath: value).lastPathComponent
		return String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(255))
	}

	private func finishOperation() {
		isBusy = false
		didUpdate?()
		let waiters = idleWaiters
		idleWaiters.removeAll()
		for waiter in waiters {
			waiter.resume()
		}
	}

	private static func validationMessage(for error: Error) -> String {
		switch error as? BrowserContentBlockingRuleSource.ValidationError {
			case .sourceTooLarge: "Choose a nonempty JSON list no larger than 2 MB."
			case .invalidJSON: "The selected file is not a valid JSON rule list."
			case .invalidRuleCount: "The list must contain between 1 and 50,000 rules."
			case .invalidRule: "A rule is missing a valid URL filter or action."
			case .unsupportedAction: "The list uses an action Astra cannot accept."
			case nil: error.localizedDescription
		}
	}

	private enum StoreError: LocalizedError {
		case unavailable
		case compileFailed
		case staleCompile
		case sourceSaveFailed

		var errorDescription: String? {
			switch self {
				case .unavailable: "WebKit's content-rule store is unavailable."
				case .compileFailed: "WebKit did not return a compiled content-rule list."
				case .staleCompile: "WebKit returned a different rule-list version. The previous list remains active."
				case .sourceSaveFailed: "The imported rules could not be saved. The previous list remains active."
			}
		}
	}
}
