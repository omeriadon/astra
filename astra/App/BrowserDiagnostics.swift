#if os(macOS)
	import AppKit
	import Foundation
	import WebKit

	@MainActor
	enum BrowserDiagnostics {
		static func report(for browser: Browser?) -> BrowserDiagnosticReport {
			let isPrivate = browser?.isPrivate == true
			let tabs = isPrivate ? [] : (browser?.tabs ?? [])
			var failures: [String: Int] = [:]
			for tab in tabs {
				let controllers = [tab.controller].compactMap(\.self) + tab.peeks.map(\.controller)
				for controller in controllers {
					if let kind = controller.navigationFailure?.kind.rawValue,
					   let safeKind = BrowserDiagnosticReport.sanitizedCode(kind)
					{
						failures[safeKind, default: 0] += 1
					}
				}
			}

			return BrowserDiagnosticReport(
				schema: BrowserDiagnosticReport.schemaVersion,
				applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
				applicationBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
				operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
				engine: "System WebKit",
				webKitVersion: Bundle(identifier: "com.apple.WebKit")?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
				scope: isPrivate ? "private-redacted" : "normal",
				tabCount: isPrivate ? nil : tabs.count,
				hibernatedTabCount: isPrivate ? nil : tabs.filter(\.isHibernated).count,
				loadingTabCount: isPrivate ? nil : tabs.filter { $0.activeController?.isLoading == true }.count,
				navigationFailures: isPrivate ? nil : failures,
				events: isPrivate ? [] : BrowserDiagnosticEventStore.shared.snapshot()
			)
		}

		static func copy(for browser: Browser?) {
			guard let data = report(for: browser).encoded(),
			      let text = String(data: data, encoding: .utf8)
			else {
				(browser?.session.toastManager ?? ToastManager.shared).show(
					symbol: "exclamationmark.triangle",
					message: "Diagnostics exceeded the safe export limit"
				)
				return
			}
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(text, forType: .string)
			(browser?.session.toastManager ?? ToastManager.shared).show(symbol: "doc.on.doc", message: "Diagnostics copied")
		}
	}
#endif
