@preconcurrency import Dispatch
import LRUCache

/// A bounded cache whose values may own main-actor text attachments.
/// LRUCache's default pressure handler evicts on a global queue. A lock protects
/// its dictionary, but cannot make CoreText attachment cleanup actor-safe.
@MainActor
final class MainActorLRUCache<Key: Hashable & Sendable, Value> {
	private let storage: LRUCache<Key, Value>
	private let memoryPressureSource: any DispatchSourceProtocol

	init(
		countLimit: Int,
		memoryPressureSource: any DispatchSourceProtocol = DispatchSource.makeMemoryPressureSource(
			eventMask: [.warning, .critical], queue: .main
		)
	) {
		storage = LRUCache(countLimit: countLimit, clearsOnMemoryPressure: false)
		self.memoryPressureSource = memoryPressureSource
		memoryPressureSource.setEventHandler { [weak self] in
			Task { @MainActor [weak self] in
				self?.removeAll()
			}
		}
		memoryPressureSource.resume()
	}

	deinit {
		memoryPressureSource.cancel()
	}

	func value(forKey key: Key) -> Value? {
		storage.value(forKey: key)
	}

	func setValue(_ value: Value, forKey key: Key) {
		storage.setValue(value, forKey: key)
	}

	func removeAll() {
		storage.removeAll()
	}
}
