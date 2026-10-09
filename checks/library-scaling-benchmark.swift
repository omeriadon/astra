import Foundation

/// Hardware-sensitive performance diagnostic: records observations without
/// asserting wall-clock limits in CI. Use the same command locally to compare
/// revisions on the same Mac.
@main
struct LibraryScalingBenchmark {
    static func main() {
        for size in [1_000, 10_000, 50_000] {
            let bookmarks = (0..<size).map { index in
                Bookmark(
                    name: index.isMultiple(of: 10) ? "Needle \(index)" : "Page \(index)",
                    url: URL(string: "https://example.com/page/\(index)")!,
                    folder: "Folder \(index % 16)",
                    order: index
                )
            }
            let reading = (0..<size / 10).map { index in
                ReadingListItem(
                    url: URL(string: "https://example.com/article/\(index)")!,
                    title: "Article \(index)",
                    addedAt: Date(timeIntervalSince1970: Double(index))
                )
            }
            let clock = ContinuousClock()
            var durations: [Double] = []
            for _ in 0..<7 {
                let started = clock.now
                let result = BrowserLibraryProjection.build(
                    bookmarks: bookmarks, readingList: reading, query: "Needle"
                )
                precondition(result != nil)
                let elapsed = started.duration(to: clock.now)
                let components = elapsed.components
                durations.append(
                    Double(components.seconds) * 1_000
                    + Double(components.attoseconds) / 1_000_000_000_000_000
                )
            }
            durations.sort()
            let median = durations[durations.count / 2]
            let p95 = durations[Int(Double(durations.count - 1) * 0.95)]
            print("bookmarks=\(size) reading=\(reading.count) projection_median_ms=\(median) projection_p95_ms=\(p95)")
        }
    }
}
