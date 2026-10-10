#if os(macOS)
	import AppKit
	import Foundation
	import Observation

	@MainActor
	@Observable
	final class BrowserTabHoverPreviewCoordinator {
		static let shared = BrowserTabHoverPreviewCoordinator()

		private(set) var presentedTabID: UUID?
		private(set) var windowID: UUID?
		private(set) var sourceFrame = CGRect.zero
		private(set) var isVisible = false

		@ObservationIgnored private var hoveredTabID: UUID?
		@ObservationIgnored private var activationTask: Task<Void, Never>?
		@ObservationIgnored private var dismissalTask: Task<Void, Never>?
		@ObservationIgnored private var warmSession = false
		@ObservationIgnored private var escapeMonitor: Any?

		private init() {
			escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
				guard event.keyCode == 53, let self, isVisible, let windowID else { return event }
				dismiss(for: windowID)
				return event
			}
		}

		func hoverBegan(tabID: UUID, windowID: UUID, sourceFrame: CGRect) {
			dismissalTask?.cancel()
			dismissalTask = nil
			// Already showing this tab: just refresh the anchor, don't restart timers.
			if isVisible, presentedTabID == tabID, self.windowID == windowID {
				hoveredTabID = tabID
				self.sourceFrame = sourceFrame
				return
			}
			hoveredTabID = tabID
			self.windowID = windowID
			self.sourceFrame = sourceFrame
			if isVisible {
				presentedTabID = tabID
			}

			// Short debounce in both cases: instant warm shows flicker while
			// sweeping across tabs, and the old 2s cold delay felt broken.
			let delay: Duration = warmSession ? .milliseconds(250) : .seconds(1)
			activationTask?.cancel()
			activationTask = Task { @MainActor [weak self] in
				do {
					try await Task.sleep(for: delay)
				} catch {
					return
				}
				guard let self,
				      hoveredTabID == tabID,
				      self.windowID == windowID
				else { return }
				warmSession = true
				presentedTabID = tabID
				isVisible = true
			}
		}

		func updateFrame(for tabID: UUID, windowID: UUID, frame: CGRect) {
			guard hoveredTabID == tabID, self.windowID == windowID else { return }
			sourceFrame = frame
		}

		func hoverEnded(tabID: UUID, windowID: UUID) {
			guard hoveredTabID == tabID, self.windowID == windowID else { return }
			hoveredTabID = nil
			activationTask?.cancel()
			activationTask = nil

			dismissalTask?.cancel()
			dismissalTask = Task { @MainActor [weak self] in
				do {
					try await Task.sleep(for: .milliseconds(160))
				} catch {
					return
				}
				guard let self, hoveredTabID == nil else { return }
				isVisible = false
				presentedTabID = nil
			}
		}

		func dismiss(for windowID: UUID) {
			guard self.windowID == windowID else { return }
			activationTask?.cancel()
			dismissalTask?.cancel()
			activationTask = nil
			dismissalTask = nil
			hoveredTabID = nil
			presentedTabID = nil
			isVisible = false
			warmSession = false
			self.windowID = nil
		}
	}
#endif
