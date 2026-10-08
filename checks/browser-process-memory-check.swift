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
		let sharedAggregate = BrowserProcessMemoryAggregate.combining([snapshot(shared), snapshot(shared)])
		precondition(sharedAggregate.processCount == 1 && sharedAggregate.uniqueBytes == 300)
		let replacementAggregate = BrowserProcessMemoryAggregate.combining([snapshot(shared), snapshot(replacement)])
		precondition(replacementAggregate.processCount == 2 && replacementAggregate.uniqueBytes == 1_000)
		let unavailableAggregate = BrowserProcessMemoryAggregate.combining([snapshot(unavailable)])
		precondition(unavailableAggregate.processCount == 0 && unavailableAggregate.uniqueBytes == nil)
		let mixedAggregate = BrowserProcessMemoryAggregate.combining([snapshot(shared), snapshot(unavailable), snapshot(shared)])
		precondition(mixedAggregate.processCount == 1 && mixedAggregate.uniqueBytes == 300)
		let sameProcessAcrossRoles = BrowserTabProcessMemorySnapshot(webContent: shared, graphics: shared, network: nil, model: nil)
		let roleAggregate = BrowserProcessMemoryAggregate.combining([sameProcessAcrossRoles])
		precondition(roleAggregate.processCount == 1 && roleAggregate.uniqueBytes == 300 && roleAggregate.webContentMappingCount == 1)
	}
}
