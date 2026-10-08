import Foundation

@main
struct DownloadFileWorkerCheck {
	static func main() async throws {
		let manager = FileManager.default
		let root = manager.temporaryDirectory.appendingPathComponent(
			"astra-download-finalize-check-\(UUID().uuidString)", isDirectory: true
		)
		let output = root.appendingPathComponent("completed", isDirectory: true)
		try manager.createDirectory(at: output, withIntermediateDirectories: true)
		defer { try? manager.removeItem(at: root) }

		let bytes = Data(repeating: 0x6B, count: 2 * 1024 * 1024)
		let firstSource = root.appendingPathComponent("first.part")
		let firstDest = output.appendingPathComponent("asset.bin")
		try bytes.write(to: firstSource)
		let committed = try await BrowserDownloadFileWorker.shared.commit(
			source: firstSource, proposed: firstDest, fileScoped: false,
			bookmark: nil, hasExistingAccess: false,
			downloadURL: nil, originURL: nil
		)
		precondition(committed == firstDest)
		precondition(!manager.fileExists(atPath: firstSource.path))
		let committedData = try Data(contentsOf: committed)
		precondition(committedData == bytes)

		let secondSource = root.appendingPathComponent("second.part")
		try bytes.write(to: secondSource)
		let collision = try await BrowserDownloadFileWorker.shared.commit(
			source: secondSource, proposed: firstDest, fileScoped: false,
			bookmark: nil, hasExistingAccess: false,
			downloadURL: nil, originURL: nil
		)
		precondition(collision != firstDest)
		precondition(collision.lastPathComponent == "asset (2).bin")
		let firstData = try Data(contentsOf: firstDest)
		precondition(firstData == bytes)
		let collisionData = try Data(contentsOf: collision)
		precondition(collisionData == bytes)

		let thirdSource = root.appendingPathComponent("third.part")
		try bytes.write(to: thirdSource)
		do {
			_ = try await BrowserDownloadFileWorker.shared.commit(
				source: thirdSource, proposed: root.appendingPathComponent("missing/asset.bin"),
				fileScoped: false, bookmark: nil, hasExistingAccess: false,
				downloadURL: nil, originURL: nil
			)
			preconditionFailure("Missing external destination must fail")
		} catch {
			precondition(manager.fileExists(atPath: thirdSource.path))
			precondition(!manager.fileExists(atPath: root.appendingPathComponent("missing").path))
		}

		let fourthSource = root.appendingPathComponent("fourth.part")
		try bytes.write(to: fourthSource)
		let cancelled = Task {
			withUnsafeCurrentTask { $0?.cancel() }
			do {
				_ = try await BrowserDownloadFileWorker.shared.commit(
					source: fourthSource, proposed: output.appendingPathComponent("cancelled.bin"),
					fileScoped: false, bookmark: nil, hasExistingAccess: false,
					downloadURL: nil, originURL: nil
				)
				return false
			} catch is CancellationError {
				return true
			} catch {
				return false
			}
		}
		let wasCancelled = await cancelled.value
		precondition(wasCancelled)
		precondition(manager.fileExists(atPath: fourthSource.path))
		precondition(!manager.fileExists(atPath: output.appendingPathComponent("cancelled.bin").path))

		let staged = try manager.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
		precondition(!staged.contains { $0.lastPathComponent.hasPrefix(".astra-finalizing-") })
		print("Download finalization worker checks passed")
	}
}
