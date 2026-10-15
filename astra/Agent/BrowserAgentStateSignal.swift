#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER
	import Foundation

	/// A one-shot, buffered observation signal. Its continuation is thread-safe and Sendable.
	final nonisolated class BrowserAgentStateSignal: Sendable {
		private let stream: AsyncStream<Void>
		private let continuation: AsyncStream<Void>.Continuation

		init() {
			let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
			stream = pair.stream
			continuation = pair.continuation
		}

		func finish() {
			continuation.yield(())
			continuation.finish()
		}

		func wait(until deadline: ContinuousClock.Instant) async throws {
			try await withThrowingTaskGroup(of: Void.self) { group in
				group.addTask { [stream] in
					for await _ in stream {
						return
					}
					try Task.checkCancellation()
				}
				group.addTask {
					try await ContinuousClock().sleep(until: deadline)
				}
				defer { group.cancelAll(); continuation.finish() }
				_ = try await group.next()
			}
			try Task.checkCancellation()
		}
	}
#endif
