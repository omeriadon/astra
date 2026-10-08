#if os(macOS)
import Foundation

struct BrowserTabProcessMemorySnapshot: Equatable, Sendable {
	struct Process: Equatable, Sendable {
		let pid: pid_t
		let startTime: UInt64?
		let bytes: UInt64?

		var identity: String {
			"\(pid):\(startTime.map(String.init) ?? "?")"
		}
	}

	let webContent: Process?
	let graphics: Process?
	let network: Process?
	let model: Process?

	var webContentBytes: UInt64? { webContent?.bytes }
	var graphicsBytes: UInt64? { graphics?.bytes }
	var networkBytes: UInt64? { network?.bytes }
	var modelBytes: UInt64? { model?.bytes }

	var relatedProcessBytes: UInt64? {
		let values = [webContentBytes, graphicsBytes, networkBytes, modelBytes].compactMap(\.self)
		return values.isEmpty ? nil : values.reduce(0, +)
	}

	var observedProcessBytes: UInt64? { relatedProcessBytes }

	var processes: [Process] {
		[webContent, graphics, network, model].compactMap(\.self)
	}

	var sharedProcessBytes: UInt64? {
		let values = [graphicsBytes, networkBytes, modelBytes].compactMap(\.self)
		return values.isEmpty ? nil : values.reduce(0, +)
	}

	var hasSharedProcessMemory: Bool { sharedProcessBytes != nil }
}

struct BrowserProcessMemoryAggregate: Equatable, Sendable {
	let processCount: Int
	let uniqueBytes: UInt64?

	static func combining(_ snapshots: [BrowserTabProcessMemorySnapshot]) -> Self {
		var processes: [String: UInt64] = [:]
		for process in snapshots.flatMap(\.processes) {
			guard let bytes = process.bytes else { continue }
			processes[process.identity] = bytes
		}
		return Self(
			processCount: processes.count,
			uniqueBytes: processes.values.isEmpty ? nil : processes.values.reduce(0, +)
		)
	}
}

struct BrowserMemoryReclamationSnapshot: Equatable, Sendable {
	let before: BrowserTabProcessMemorySnapshot
	let after: BrowserTabProcessMemorySnapshot?

	var beforeObservedBytes: UInt64? { before.observedProcessBytes }
	var afterObservedBytes: UInt64? { after?.observedProcessBytes }
	var processIdentityChanged: Bool {
		guard let after else { return true }
		return Set(before.processes.map(\.identity)) != Set(after.processes.map(\.identity))
	}
	var processNoLongerObserved: Bool { after == nil }
}
#endif
