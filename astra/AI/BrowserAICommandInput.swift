#if os(macOS)
import Darwin
import Foundation

/// Serial nonblocking pipe transport. Backpressure never occupies MainActor;
/// cancellation is checked between bounded poll intervals, including a child
/// that is alive but has stopped draining stdin.
nonisolated final class BrowserAICommandInput: @unchecked Sendable {
	private let handle: FileHandle
	private let queue = DispatchQueue(label: "com.omeriadon.astra.ai.stdin", qos: .userInitiated)
	private let lock = NSLock()
	private var cancelled = false
	private let setupError: POSIXError?

	init(_ handle: FileHandle) {
		self.handle = handle
		let flags = fcntl(handle.fileDescriptor, F_GETFL)
		let configured = flags >= 0 ? fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) : -1
		let protected = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
		setupError = configured < 0 || protected < 0 ? POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) : nil
	}

	func write(_ text: String, close: Bool = false) async throws {
		let data = Data(text.utf8)
		try await withTaskCancellationHandler {
			try Task.checkCancellation()
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				queue.async { [self] in
					do {
						try send(data)
						if close { try handle.close() }
						continuation.resume()
					} catch { continuation.resume(throwing: error) }
				}
			}
		} onCancel: { cancel() }
	}

	func cancel() {
		lock.lock()
		cancelled = true
		lock.unlock()
		queue.async { [handle] in try? handle.close() }
	}

	private func checkCancellation() throws {
		lock.lock()
		let stopped = cancelled
		lock.unlock()
		if stopped { throw CancellationError() }
	}

	private func send(_ data: Data) throws {
		if let setupError { throw setupError }
		try data.withUnsafeBytes { buffer in
			var offset = 0
			while offset < buffer.count {
				try checkCancellation()
				let written = unsafe Darwin.write(handle.fileDescriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
				if written > 0 { offset += written; continue }
				if written < 0, errno == EINTR { continue }
				guard written < 0, errno == EAGAIN || errno == EWOULDBLOCK else {
					throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
				}
				var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLOUT), revents: 0)
				let result = unsafe poll(&descriptor, 1, 100)
				if result < 0, errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
			}
		}
	}
}
#endif
