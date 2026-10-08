import Foundation

@main
struct DownloadFileWorkerCheck {
	static func main() async throws {
		let manager = FileManager.default
		let root = manager.temporaryDirectory.appendingPathComponent(
			"astra-download-finalize-check-\(UUID().uuidString)", isDirectory: true
		)
		let output = root.appendingPathComponent("completed", isDirectory: true)
		let input = root.appendingPathComponent("download-staging", isDirectory: true)
		try manager.createDirectory(at: output, withIntermediateDirectories: true)
		try manager.createDirectory(at: input, withIntermediateDirectories: true)
		defer { try? manager.removeItem(at: root) }

		let bytes = Data(repeating: 0x6B, count: 2 * 1024 * 1024)
		let firstSource = input.appendingPathComponent("first.part")
		let firstDest = output.appendingPathComponent("asset.bin")
		try bytes.write(to: firstSource)
		let committed = try await BrowserDownloadFileWorker.shared.commit(
			source: firstSource, ownedStagingDirectory: input, proposed: firstDest, fileScoped: false,
			bookmark: nil, hasExistingAccess: false,
			downloadURL: nil, originURL: nil
		)
		precondition(committed == firstDest)
		precondition(!manager.fileExists(atPath: firstSource.path))
		let committedData = try Data(contentsOf: committed)
		precondition(committedData == bytes)

		let secondSource = input.appendingPathComponent("second.part")
		try bytes.write(to: secondSource)
		let collision = try await BrowserDownloadFileWorker.shared.commit(
			source: secondSource, ownedStagingDirectory: input, proposed: firstDest, fileScoped: false,
			bookmark: nil, hasExistingAccess: false,
			downloadURL: nil, originURL: nil
		)
		precondition(collision != firstDest)
		precondition(collision.lastPathComponent == "asset (2).bin")
		let firstData = try Data(contentsOf: firstDest)
		precondition(firstData == bytes)
		let collisionData = try Data(contentsOf: collision)
		precondition(collisionData == bytes)

		let renamed = try await BrowserDownloadFileWorker.shared.renameExisting(
			source: collision, fileName: "renamed.bin",
			bookmark: nil, hasExistingAccess: false
		)
		precondition(renamed.lastPathComponent == "renamed.bin")
		precondition(!manager.fileExists(atPath: collision.path))
		let renamedData = try Data(contentsOf: renamed)
		precondition(renamedData == bytes)

		// A forged or corrupted index must never be allowed to finalize a file
		// outside the app-owned transfer staging directory.
		do {
			_ = try await BrowserDownloadFileWorker.shared.commit(
				source: firstDest, ownedStagingDirectory: input,
				proposed: output.appendingPathComponent("unsafe.bin"),
				fileScoped: false, bookmark: nil, hasExistingAccess: false,
				downloadURL: nil, originURL: nil
			)
			preconditionFailure("Finalizer accepted source outside owned staging directory")
		} catch {
			precondition(manager.fileExists(atPath: firstDest.path))
			precondition(!manager.fileExists(atPath: output.appendingPathComponent("unsafe.bin").path))
		}

		let thirdSource = input.appendingPathComponent("third.part")
		try bytes.write(to: thirdSource)
		do {
			_ = try await BrowserDownloadFileWorker.shared.commit(
				source: thirdSource, ownedStagingDirectory: input, proposed: root.appendingPathComponent("missing/asset.bin"),
				fileScoped: false, bookmark: nil, hasExistingAccess: false,
				downloadURL: nil, originURL: nil
			)
			preconditionFailure("Missing external destination must fail")
		} catch {
			precondition(manager.fileExists(atPath: thirdSource.path))
			precondition(!manager.fileExists(atPath: root.appendingPathComponent("missing").path))
		}

		let fourthSource = input.appendingPathComponent("fourth.part")
		try bytes.write(to: fourthSource)
		let cancelled = Task {
			withUnsafeCurrentTask { $0?.cancel() }
			do {
				_ = try await BrowserDownloadFileWorker.shared.commit(
					source: fourthSource, ownedStagingDirectory: input, proposed: output.appendingPathComponent("cancelled.bin"),
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

		let tempRoot = input
		let disposable = tempRoot.appendingPathComponent("disposable.part")
		try bytes.write(to: disposable)
		try await BrowserDownloadFileWorker.shared.deleteTemporaryFiles(
			[disposable], in: tempRoot, bookmark: nil, hasExistingAccess: false
		)
		precondition(!manager.fileExists(atPath: disposable.path))
		do {
			try await BrowserDownloadFileWorker.shared.deleteTemporaryFiles(
				[firstDest], in: tempRoot, bookmark: nil, hasExistingAccess: false
			)
			preconditionFailure("File outside staging area must not be deleted")
		} catch {
			precondition(manager.fileExists(atPath: firstDest.path))
		}

		let downloadIndex = root.appendingPathComponent("downloads.json")
		let archived = BrowserDownload(
			id: UUID(),
			createdAt: .now,
			sourceURL: nil,
			requestURL: nil,
			originalName: "paused.bin",
			fileURL: thirdSource,
			status: .paused,
			progress: 0.5,
			renamedByAppleIntelligence: false,
			resumeData: nil,
			errorMessage: nil
		)
		try await BrowserDownloadFileWorker.shared.persistDownloadIndex([archived], at: downloadIndex)
		let restored = try JSONDecoder().decode([BrowserDownload].self, from: Data(contentsOf: downloadIndex))
		precondition(restored == [archived])
		var newest = archived
		newest.status = .completed
		newest.progress = 1
		try await BrowserDownloadFileWorker.shared.persistDownloadIndex([newest], at: downloadIndex, revision: 12)
		// An older debounced save can arrive after a newer save or flush.
		// It must not replace the already committed newer generation.
		try await BrowserDownloadFileWorker.shared.persistDownloadIndex([archived], at: downloadIndex, revision: 11)
		let latestRestored = try JSONDecoder().decode([BrowserDownload].self, from: Data(contentsOf: downloadIndex))
		precondition(latestRestored == [newest])
		let cancelledWrite = Task {
			withUnsafeCurrentTask { $0?.cancel() }
			do {
				try await BrowserDownloadFileWorker.shared.persistDownloadIndex([archived], at: downloadIndex, revision: 13)
				return false
			} catch is CancellationError {
				return true
			} catch {
				return false
			}
		}
		let cancellationWasObserved = await cancelledWrite.value
		precondition(cancellationWasObserved)
		let afterCancellation = try JSONDecoder().decode([BrowserDownload].self, from: Data(contentsOf: downloadIndex))
		precondition(afterCancellation == [newest])

		let staged = try manager.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
		precondition(!staged.contains { $0.lastPathComponent.hasPrefix(".astra-finalizing-") })
		print("Download finalization worker checks passed")
	}
}
