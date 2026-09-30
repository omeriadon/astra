import Foundation

struct SafariExtensionCandidate: Identifiable, Sendable {
	let id: String
	let name: String
	let bundleURL: URL

	nonisolated static func discover() -> [Self] {
		#if os(macOS)
			let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
			var results: [Self] = []
			for root in roots {
				let apps = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
				for app in apps where app.pathExtension == "app" {
					let plugins = app.appendingPathComponent("Contents/PlugIns")
					let bundles = (try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)) ?? []
					for bundle in bundles where bundle.pathExtension == "appex" {
						guard let data = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
						      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
						      let extensionInfo = info["NSExtension"] as? [String: Any],
						      extensionInfo["NSExtensionPointIdentifier"] as? String == "com.apple.Safari.web-extension",
						      let id = info["CFBundleIdentifier"] as? String else { continue }
						results.append(Self(id: id, name: app.deletingPathExtension().lastPathComponent, bundleURL: bundle))
					}
				}
			}
			return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		#else
			return []
		#endif
	}
}
