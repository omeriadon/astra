@preconcurrency import Dispatch
import Foundation
import Litext
@testable import MarkdownView
import XCTest

final class MainActorLRUCacheTests: XCTestCase {
	/// Destruction of a cached attributed string must release its attributes on
	/// the main actor, just like Litext's CoreText run-delegate callbacks require.
	private final class ReleaseProbe: NSObject {
		let onRelease: @Sendable () -> Void

		init(onRelease: @escaping @Sendable () -> Void) {
			self.onRelease = onRelease
		}

		deinit {
			MainActor.preconditionIsolated()
			onRelease()
		}
	}

	@MainActor
	private func insertAttachment(
		into cache: MainActorLRUCache<Int, NSAttributedString>,
		key: Int,
		onRelease: @escaping @Sendable () -> Void
	) {
		// Bound Foundation temporaries so release probes observe cache ownership,
		// rather than the surrounding XCTest autorelease pool's lifetime.
		autoreleasepool {
			let attachment = TextLabel.Attachment.hold(
				attrString: NSAttributedString(string: "formula"),
				size: CGSize(width: 20, height: 12)
			)
			let text = attachment.attributedString(attributes: [
				NSAttributedString.Key("releaseProbe"): ReleaseProbe(onRelease: onRelease),
			])
			cache.setValue(text, forKey: key)
		}
	}

	@MainActor
	func testBackgroundPressureReleasesAttachmentsOnMainActor() async {
		// A dispatch source on the same global queue used by upstream LRUCache
		// reproduces pressure without exhausting the test machine's memory.
		let pressure = DispatchSource.makeUserDataAddSource(queue: .global())
		let cache = MainActorLRUCache<Int, NSAttributedString>(countLimit: 2, memoryPressureSource: pressure)
		let released = expectation(description: "Attachment released on main actor")
		insertAttachment(into: cache, key: 1) { released.fulfill() }
		XCTAssertNotNil(cache.value(forKey: 1))

		pressure.add(data: 1)
		await fulfillment(of: [released], timeout: 5)
		XCTAssertNil(cache.value(forKey: 1))

		// Clearing must leave the cache usable for the next streamed update.
		cache.setValue(NSAttributedString(string: "next"), forKey: 2)
		XCTAssertEqual(cache.value(forKey: 2)?.string, "next")
	}

	@MainActor
	func testCountLimitStillEvictsLeastRecentlyUsedAttachment() {
		let cache = MainActorLRUCache<Int, NSAttributedString>(countLimit: 2)
		let released = expectation(description: "Least recently used attachment released")
		insertAttachment(into: cache, key: 1) { released.fulfill() }
		cache.setValue(NSAttributedString(string: "two"), forKey: 2)
		_ = cache.value(forKey: 2)
		cache.setValue(NSAttributedString(string: "three"), forKey: 3)

		XCTAssertNil(cache.value(forKey: 1))
		XCTAssertNotNil(cache.value(forKey: 2))
		XCTAssertNotNil(cache.value(forKey: 3))
		wait(for: [released], timeout: 1)
	}
}
