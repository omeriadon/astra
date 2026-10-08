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
				memory: nil,
				events: isPrivate ? [] : BrowserDiagnosticEventStore.shared.snapshot()
			)
		}

		static func reportWithMemory(for browser: Browser?) async -> BrowserDiagnosticReport {
			let base = report(for: browser)
			guard browser?.isPrivate != true else { return base }
			let browsers = BrowserWindowRegistry.shared.openBrowsers.filter { !$0.isPrivate && !$0.isMini }
			var controllers: [BrowserController] = []
			var controllerIDs = Set<UUID>()
			for browser in browsers {
				for tab in browser.tabs {
					for controller in [tab.controller].compactMap(\.self) + tab.peeks.map(\.controller)
					where controllerIDs.insert(controller.id).inserted
					{
						controllers.append(controller)
					}
				}
			}
			var snapshots: [BrowserTabProcessMemorySnapshot] = []
			var unavailableProcessCount = 0
			for controller in controllers {
				if let snapshot = await controller.tabProcessMemorySnapshot() {
					snapshots.append(snapshot)
					unavailableProcessCount += snapshot.processes.filter { $0.bytes == nil }.count
				} else {
					unavailableProcessCount += 1
				}
			}
			let aggregate = BrowserProcessMemoryAggregate.combining(snapshots)
			return BrowserDiagnosticReport(
				schema: base.schema,
				applicationVersion: base.applicationVersion,
				applicationBuild: base.applicationBuild,
				operatingSystem: base.operatingSystem,
				engine: base.engine,
				webKitVersion: base.webKitVersion,
				scope: base.scope,
				tabCount: base.tabCount,
				hibernatedTabCount: base.hibernatedTabCount,
				loadingTabCount: base.loadingTabCount,
				navigationFailures: base.navigationFailures,
				memory: BrowserDiagnosticReport.Memory(
					measuredControllers: snapshots.count,
					controllerCount: controllers.count,
					uniqueProcessCount: aggregate.processCount,
					uniqueProcessBytes: aggregate.uniqueBytes,
					unavailableProcessCount: unavailableProcessCount
				),
				events: base.events
			)
		}

		static func copy(for browser: Browser?) {
			Task { @MainActor in
				let report = await reportWithMemory(for: browser)
				copyEncoded(report, for: browser)
			}
		}

		private static func copyEncoded(_ report: BrowserDiagnosticReport, for browser: Browser?) {
			guard let data = report.encoded(),
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
