#if os(macOS)
	import AppKit
	import Foundation
	import WebKit

	@MainActor
	enum BrowserDiagnostics {
		static func copy(for browser: Browser?) {
			let controller = browser?.selectedTab?.activeController
			let info: [String: Any] = [
				"applicationVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
				"applicationBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
				"macOS": ProcessInfo.processInfo.operatingSystemVersionString,
				"engine": "System WebKit",
				"webKitVersion": Bundle(identifier: "com.apple.WebKit")?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
				"privateWindow": browser?.isPrivate ?? false,
				"pageLoading": controller?.isLoading ?? false,
				"navigationFailure": controller?.navigationFailure?.kind.rawValue ?? "None",
				"mediaPlaying": controller?.isPlayingMedia ?? false,
				"cameraCapture": controller?.cameraCaptureState.rawValue ?? 0,
				"microphoneCapture": controller?.microphoneCaptureState.rawValue ?? 0,
			]
			guard let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]),
			      let text = String(data: data, encoding: .utf8) else { return }
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(text, forType: .string)
			ToastManager.shared.show(symbol: "doc.on.doc", message: "Diagnostics copied")
		}
	}
#endif
