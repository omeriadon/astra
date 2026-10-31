import Foundation

@main
struct HistorySearchCancellationCheck {
	static func main() async {
		let values = (0 ..< 10000).map { index in
			BrowserVisit(
				url: URL(string: "https://example.com/\(index)")!,
				title: index.isMultiple(of: 3) ? "Alpha \(index)" : "Beta \(index)"
			)
		}
		let expected = BrowserVisit.matching(values, query: "Alpha")
		let actual = BrowserVisit.matchingUnlessCancelled(values, query: "Alpha")
		precondition(actual == expected)
		precondition(BrowserVisit.matchingUnlessCancelled(values, query: "") == values)

		let cancelled = Task.detached {
			withUnsafeCurrentTask { $0?.cancel() }
			return BrowserVisit.matchingUnlessCancelled(values, query: "Beta")
		}
		let stale = await cancelled.value
		precondition(stale == nil, "Cancelled search must not return stale results")
		print("History cooperative cancellation checks passed")
	}
}
