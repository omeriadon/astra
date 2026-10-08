import Foundation

let shared = BrowserTabProcessMemorySnapshot.Process(pid: 42, startTime: 100, bytes: 300)
let replacement = BrowserTabProcessMemorySnapshot.Process(pid: 42, startTime: 200, bytes: 700)
let unavailable = BrowserTabProcessMemorySnapshot.Process(pid: 43, startTime: 100, bytes: nil)

func snapshot(_ webContent: BrowserTabProcessMemorySnapshot.Process?) -> BrowserTabProcessMemorySnapshot {
	BrowserTabProcessMemorySnapshot(webContent: webContent, graphics: nil, network: nil, model: nil)
}

@main
enum BrowserProcessMemoryCheck {
	static func main() {
		precondition(BrowserProcessMemoryAggregate.combining([snapshot(shared), snapshot(shared)]) == .init(processCount: 1, uniqueBytes: 300))
		precondition(BrowserProcessMemoryAggregate.combining([snapshot(shared), snapshot(replacement)]) == .init(processCount: 2, uniqueBytes: 1_000))
		precondition(BrowserProcessMemoryAggregate.combining([snapshot(unavailable)]) == .init(processCount: 0, uniqueBytes: nil))
		precondition(BrowserProcessMemoryAggregate.combining([snapshot(shared), snapshot(unavailable), snapshot(shared)]) == .init(processCount: 1, uniqueBytes: 300))
	}
}
