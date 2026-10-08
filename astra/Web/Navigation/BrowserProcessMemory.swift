#if os(macOS)
import Darwin
import Foundation

struct BrowserTabProcessMemorySnapshot: Equatable, Sendable {
	struct Process: Equatable, Sendable {
		let pid: pid_t
		let startTime: UInt64?
		let bytes: UInt64?

		nonisolated var identity: String {
			"\(pid):\(startTime.map(String.init) ?? "?")"
		}
	}

	let webContent: Process?
	let graphics: Process?
	let network: Process?
	let model: Process?

	var webContentBytes: UInt64? {
		webContent?.bytes
	}
	var graphicsBytes: UInt64? {
		graphics?.bytes
	}
	var networkBytes: UInt64? {
		network?.bytes
	}
	var modelBytes: UInt64? {
		model?.bytes
	}

	var knownProcessBytes: UInt64? {
		var unique: [String: UInt64] = [:]
		for process in processes {
			if let bytes = process.bytes {
				unique[process.identity] = bytes
			}
		}
		return unique.isEmpty ? nil : unique.values.reduce(0, +)
	}

	var processes: [Process] {
		[webContent, graphics, network, model].compactMap(\.self)
	}

	var sharedProcessBytes: UInt64? {
		let values = [graphicsBytes, networkBytes, modelBytes].compactMap(\.self)
		return values.isEmpty ? nil : values.reduce(0, +)
	}

	var hasSharedProcessMemory: Bool {
		sharedProcessBytes != nil
	}

	nonisolated static func sample(_ pid: pid_t) -> Process {
		let footprint = physicalFootprint(pid)
		return Process(pid: pid, startTime: footprint?.startTime, bytes: footprint?.bytes)
	}

	nonisolated static func resample(_ processes: [Process]) async -> [String: Process] {
		await Task.detached(priority: .utility) {
			var result: [String: Process] = [:]
			for process in processes {
				let footprint = physicalFootprint(process.pid)
				let startTime = footprint?.startTime
				let bytes = process.startTime != nil && process.startTime == startTime ? footprint?.bytes : nil
				result[process.identity] = Process(pid: process.pid, startTime: startTime, bytes: bytes)
			}
			return result
		}.value
	}

	nonisolated private static func physicalFootprint(_ processIdentifier: pid_t) -> (bytes: UInt64, startTime: UInt64)? {
		var usage = rusage_info_v4()
		let result = withUnsafeMutablePointer(to: &usage) { usagePointer in
			var info: rusage_info_t? = UnsafeMutableRawPointer(usagePointer)
			return withUnsafeMutablePointer(to: &info) { infoPointer in
				proc_pid_rusage(processIdentifier, Int32(RUSAGE_INFO_V4), infoPointer)
			}
		}
		guard result == 0, usage.ri_proc_start_abstime > 0 else { return nil }
		return (usage.ri_phys_footprint, usage.ri_proc_start_abstime)
	}
}

struct BrowserProcessMemoryAggregate: Equatable, Sendable {
	let processCount: Int
	let uniqueBytes: UInt64?
	let webContentBytes: UInt64?
	let graphicsBytes: UInt64?
	let networkBytes: UInt64?
	let modelBytes: UInt64?
	let webContentMappingCount: Int
	let webContentUnavailableCount: Int

	static func combining(_ snapshots: [BrowserTabProcessMemorySnapshot]) -> Self {
		var processes: [String: UInt64] = [:]
		var roleBytes: [[String: UInt64]] = [[:], [:], [:], [:]]
		var webContentMappingCount = 0
		var webContentUnavailableCount = 0
		for snapshot in snapshots {
			if let webContent = snapshot.webContent {
				webContentMappingCount += 1
				if webContent.bytes == nil {
					webContentUnavailableCount += 1
				}
			}
			for (index, process) in [snapshot.webContent, snapshot.graphics, snapshot.network, snapshot.model].enumerated() {
				guard let process else { continue }
				guard let bytes = process.bytes else { continue }
				roleBytes[index][process.identity] = bytes
			}
		}
		for process in snapshots.flatMap(\.processes) {
			guard let bytes = process.bytes else { continue }
			processes[process.identity] = bytes
		}
		return Self(
			processCount: processes.count,
			uniqueBytes: processes.values.isEmpty ? nil : processes.values.reduce(0, +),
			webContentBytes: roleBytes[0].values.isEmpty ? nil : roleBytes[0].values.reduce(0, +),
			graphicsBytes: roleBytes[1].values.isEmpty ? nil : roleBytes[1].values.reduce(0, +),
			networkBytes: roleBytes[2].values.isEmpty ? nil : roleBytes[2].values.reduce(0, +),
			modelBytes: roleBytes[3].values.isEmpty ? nil : roleBytes[3].values.reduce(0, +),
			webContentMappingCount: webContentMappingCount,
			webContentUnavailableCount: webContentUnavailableCount
		)
	}
}

struct BrowserMemoryReclamationSnapshot: Equatable, Sendable {
	let before: BrowserTabProcessMemorySnapshot
	let after: BrowserTabProcessMemorySnapshot?

	var beforeObservedBytes: UInt64? {
		before.knownProcessBytes
	}
	var afterObservedBytes: UInt64? {
		after?.knownProcessBytes
	}
	var processIdentityChanged: Bool {
		guard let after else { return true }
		return Set(before.processes.map(\.identity)) != Set(after.processes.map(\.identity))
	}
	var unavailableProcessCount: Int {
		guard let after else { return before.processes.count }
		return after.processes.filter { $0.bytes == nil }.count
	}
}
#endif
