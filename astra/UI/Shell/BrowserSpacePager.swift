#if os(macOS)
	import AppKit
	import SwiftUI

	/// AppKit-backed horizontal paging for the sidebar.
	///
	/// Keeping horizontal page navigation in NSPageController prevents the vertical
	/// SwiftUI ScrollView inside each Space from competing for the same trackpad
	/// scroll events.
	struct BrowserSpacePager<Content: View>: NSViewControllerRepresentable {
		let spaces: [BrowserSpace]
		let selectedSpaceID: UUID
		let onSelectSpace: (UUID) -> Void
		let content: (BrowserSpace) -> Content

		@Environment(\.accessibilityReduceMotion) private var reduceMotion

		init(
			spaces: [BrowserSpace],
			selectedSpaceID: UUID,
			onSelectSpace: @escaping (UUID) -> Void,
			@ViewBuilder content: @escaping (BrowserSpace) -> Content
		) {
			self.spaces = spaces
			self.selectedSpaceID = selectedSpaceID
			self.onSelectSpace = onSelectSpace
			self.content = content
		}

		func makeNSViewController(context _: Context) -> BrowserSpacePageController<Content> {
			let controller = BrowserSpacePageController(content: content)
			controller.update(
				spaces: spaces,
				selectedSpaceID: selectedSpaceID,
				content: content,
				onSelectSpace: onSelectSpace,
				animated: false
			)
			return controller
		}

		func updateNSViewController(
			_ controller: BrowserSpacePageController<Content>,
			context _: Context
		) {
			controller.update(
				spaces: spaces,
				selectedSpaceID: selectedSpaceID,
				content: content,
				onSelectSpace: onSelectSpace,
				animated: !reduceMotion
			)
		}
	}

	final class BrowserSpacePageController<Content: View>: NSPageController, NSPageControllerDelegate {
		private var spaces: [BrowserSpace] = []
		private var content: (BrowserSpace) -> Content
		private var onSelectSpace: (UUID) -> Void = { _ in }
		private var contentControllers: [String: BrowserSpacePageContentController<Content>] = [:]
		private var previousBoundsSize: CGSize = .zero

		init(content: @escaping (BrowserSpace) -> Content) {
			self.content = content
			super.init(nibName: nil, bundle: nil)
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			nil
		}

		override func loadView() {
			view = NSView()
		}

		override func viewDidLoad() {
			super.viewDidLoad()
			delegate = self
			transitionStyle = .horizontalStrip
			view.wantsLayer = true
		}

		override func viewDidLayout() {
			super.viewDidLayout()

			// NSPageController can retain stale page geometry across live window
			// resizes. Keep every prepared page pinned to the pager bounds.
			for subview in view.subviews {
				subview.frame = view.bounds
			}

			let currentSize = view.bounds.size
			if currentSize != previousBoundsSize {
				previousBoundsSize = currentSize
				completeTransition()
			}
		}

		func update(
			spaces: [BrowserSpace],
			selectedSpaceID: UUID,
			content: @escaping (BrowserSpace) -> Content,
			onSelectSpace: @escaping (UUID) -> Void,
			animated: Bool
		) {
			let oldIDs = self.spaces.map(\.id)
			let newIDs = spaces.map(\.id)

			self.spaces = spaces
			self.content = content
			self.onSelectSpace = onSelectSpace

			loadViewIfNeeded()

			if oldIDs != newIDs || arrangedObjects.count != spaces.count {
				arrangedObjects = spaces
			}

			// BrowserSpace is a value type and changes whenever tabs, folders, names,
			// or themes change. Refresh any pages NSPageController has already
			// prepared so they never render a stale Space snapshot.
			var staleIdentifiers: [String] = []
			for (identifier, controller) in contentControllers {
				guard
					let id = UUID(uuidString: identifier),
					let space = spaces.first(where: { $0.id == id })
				else {
					staleIdentifiers.append(identifier)
					continue
				}
				controller.update(space: space, content: content)
			}
			for identifier in staleIdentifiers {
				contentControllers[identifier] = nil
			}

			guard
				let targetIndex = spaces.firstIndex(where: { $0.id == selectedSpaceID }),
				targetIndex != selectedIndex
			else { return }

			if animated, !spaces.isEmpty {
				NSAnimationContext.runAnimationGroup { context in
					context.duration = 0.3
					animator().selectedIndex = targetIndex
				} completionHandler: { [weak self] in
					self?.completeTransition()
				}
			} else {
				selectedIndex = targetIndex
				completeTransition()
			}
		}

		func pageController(
			_: NSPageController,
			identifierFor object: Any
		) -> NSPageController.ObjectIdentifier {
			guard let space = object as? BrowserSpace else { return "" }
			return space.id.uuidString
		}

		func pageController(
			_: NSPageController,
			viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier
		) -> NSViewController {
			if let controller = contentControllers[identifier] {
				return controller
			}

			let controller = BrowserSpacePageContentController<Content>()
			if
				let id = UUID(uuidString: identifier),
				let space = spaces.first(where: { $0.id == id })
			{
				controller.update(space: space, content: content)
			}
			contentControllers[identifier] = controller
			return controller
		}

		func pageControllerDidEndLiveTransition(_: NSPageController) {
			completeTransition()
		}

		func pageController(_: NSPageController, didTransitionTo _: Any) {
			guard spaces.indices.contains(selectedIndex) else { return }

			let id = spaces[selectedIndex].id
			DispatchQueue.main.async { [onSelectSpace] in
				onSelectSpace(id)
			}
		}
	}

	final class BrowserSpacePageContentController<Content: View>: NSViewController {
		private var hostingView: NSHostingView<Content>?

		override func loadView() {
			view = NSView()
		}

		func update(
			space: BrowserSpace,
			content: @escaping (BrowserSpace) -> Content
		) {
			let rootView = content(space)

			if let hostingView {
				hostingView.rootView = rootView
				return
			}

			loadViewIfNeeded()

			let hostingView = NSHostingView(rootView: rootView)
			hostingView.sizingOptions = []
			hostingView.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(hostingView)
			NSLayoutConstraint.activate([
				hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
				hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
				hostingView.topAnchor.constraint(equalTo: view.topAnchor),
				hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			])
			self.hostingView = hostingView
		}
	}

#else
	import SwiftUI

	/// Non-macOS fallback. The desktop shell is macOS-first, but this keeps the
	/// shared target buildable on iOS without introducing AppKit there.
	struct BrowserSpacePager<Content: View>: View {
		let spaces: [BrowserSpace]
		let selectedSpaceID: UUID
		let onSelectSpace: (UUID) -> Void
		let content: (BrowserSpace) -> Content

		@State private var scrollSpaceID: UUID?
		@State private var isScrolling = false
		@Environment(\.accessibilityReduceMotion) private var reduceMotion

		init(
			spaces: [BrowserSpace],
			selectedSpaceID: UUID,
			onSelectSpace: @escaping (UUID) -> Void,
			@ViewBuilder content: @escaping (BrowserSpace) -> Content
		) {
			self.spaces = spaces
			self.selectedSpaceID = selectedSpaceID
			self.onSelectSpace = onSelectSpace
			self.content = content
		}

		var body: some View {
			ScrollView(.horizontal) {
				LazyHStack(spacing: 0) {
					ForEach(spaces) { space in
						content(space)
							.containerRelativeFrame(.horizontal)
							.id(space.id)
					}
				}
				.scrollTargetLayout()
			}
			.scrollIndicators(.hidden)
			.scrollTargetBehavior(.paging)
			.scrollPosition(id: $scrollSpaceID, anchor: .center)
			.onScrollPhaseChange { _, phase in
				isScrolling = phase == .interacting || phase == .decelerating
			}
			.onChange(of: selectedSpaceID, initial: true) { oldID, id in
				withAnimation(reduceMotion || oldID == id ? nil : .smooth(duration: 0.3)) {
					scrollSpaceID = id
				}
			}
			.onChange(of: scrollSpaceID) { _, id in
				guard isScrolling, let id, id != selectedSpaceID else { return }
				onSelectSpace(id)
			}
		}
	}
#endif
