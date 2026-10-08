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
		let favouriteTabIDs: [UUID]
		let onSelectSpace: (UUID) -> Void
		let content: (BrowserSpace, Bool, [UUID]) -> Content

		@Environment(\.accessibilityReduceMotion) private var reduceMotion

		init(
			spaces: [BrowserSpace],
			selectedSpaceID: UUID,
			favouriteTabIDs: [UUID],
			onSelectSpace: @escaping (UUID) -> Void,
			@ViewBuilder content: @escaping (BrowserSpace, Bool, [UUID]) -> Content
		) {
			self.spaces = spaces
			self.selectedSpaceID = selectedSpaceID
			self.favouriteTabIDs = favouriteTabIDs
			self.onSelectSpace = onSelectSpace
			self.content = content
		}

		func makeNSViewController(context _: Context) -> BrowserSpacePageController<Content> {
			let controller = BrowserSpacePageController(content: content)
			controller.update(
				spaces: spaces,
				selectedSpaceID: selectedSpaceID,
				favouriteTabIDs: favouriteTabIDs,
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
				favouriteTabIDs: favouriteTabIDs,
				content: content,
				onSelectSpace: onSelectSpace,
				animated: !reduceMotion
			)
		}
	}

	private struct BrowserSpacePageSignature: Equatable {
		let id: UUID
		let name: String
		let symbol: String
		let theme: BrowserTheme
		let tabIDs: [UUID]
		let pinnedTabIDs: [UUID]
		let todayTabGroups: [BrowserTabGroupingFeature.Group]
		let pinnedFolders: [PinnedTabFolder]
		let isSelected: Bool
		let favouriteTabIDs: [UUID]

		init(_ space: BrowserSpace, isSelected: Bool, favouriteTabIDs: [UUID]) {
			id = space.id
			name = space.name
			symbol = space.symbol
			theme = space.theme
			tabIDs = space.tabIDs
			pinnedTabIDs = space.pinnedTabIDs
			todayTabGroups = space.todayTabGroups
			pinnedFolders = space.pinnedFolders
			self.isSelected = isSelected
			self.favouriteTabIDs = favouriteTabIDs
		}
	}

	final class BrowserSpacePageController<Content: View>: NSPageController, NSPageControllerDelegate {
		private var spaces: [BrowserSpace] = []
		private var selectedSpaceID: UUID?
		private var favouriteTabIDs: [UUID] = []
		private var content: (BrowserSpace, Bool, [UUID]) -> Content
		private var onSelectSpace: (UUID) -> Void = { _ in }
		private var contentControllers: [String: BrowserSpacePageContentController<Content>] = [:]
		private var previousBoundsSize: CGSize = .zero

		init(content: @escaping (BrowserSpace, Bool, [UUID]) -> Content) {
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

			let currentSize = view.bounds.size
			guard currentSize != previousBoundsSize else { return }
			previousBoundsSize = currentSize

			// Repair page geometry only for an actual resize. Writing every
			// subview's frame on every layout pass fights NSPageController's live
			// horizontal-strip animation and recursively dirties SwiftUI layout.
			for subview in view.subviews {
				subview.frame = view.bounds
			}
			completeTransition()
		}

		func update(
			spaces: [BrowserSpace],
			selectedSpaceID: UUID,
			favouriteTabIDs: [UUID],
			content: @escaping (BrowserSpace, Bool, [UUID]) -> Content,
			onSelectSpace: @escaping (UUID) -> Void,
			animated: Bool
		) {
			let updateStartedAt = BrowserLog.clock()
			defer {
				BrowserLog.duration(
					.performance,
					"space-pager.update.end",
					since: updateStartedAt,
					warnAboveMilliseconds: 40,
					metadata: ["spaces": String(spaces.count), "prepared": String(contentControllers.count)]
				)
			}
			let oldIDs = self.spaces.map(\.id)
			let newIDs = spaces.map(\.id)

			self.spaces = spaces
			self.selectedSpaceID = selectedSpaceID
			self.favouriteTabIDs = favouriteTabIDs
			self.content = content
			self.onSelectSpace = onSelectSpace

			loadViewIfNeeded()

			if oldIDs != newIDs || arrangedObjects.count != spaces.count {
				arrangedObjects = spaces
			}

			// Selection timestamps and selectedTabID mutate BrowserSpace on every tab
			// switch, but neither changes what an individual sidebar page renders.
			// Let each prepared page compare a content-only signature before replacing
			// its NSHostingView root. Replacing every root here was forcing a full
			// SwiftUI/AttributeGraph layout pass during tab changes and live swipes.
			let spacesByID = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) })
			let targetIndex = spaces.firstIndex(where: { $0.id == selectedSpaceID })
			// NSPageController may retain a hosting controller for every space
			// the user has visited. Updating all of them during each selection,
			// hover-triggered shell invalidation, or animation is expensive.
			// Only live/adjacent pages need a current SwiftUI root. When AppKit
			// asks for a distant cached page, refresh it on demand below.
			var visibleIdentifiers = Set<String>()
			for index in [selectedIndex, targetIndex ?? selectedIndex] {
				guard spaces.indices.contains(index) else { continue }
				for neighbor in max(0, index - 1) ... min(spaces.count - 1, index + 1) {
					visibleIdentifiers.insert(spaces[neighbor].id.uuidString)
				}
			}
			var staleIdentifiers: [String] = []
			for (identifier, controller) in contentControllers {
				guard let id = UUID(uuidString: identifier),
				      let space = spacesByID[id]
				else {
					staleIdentifiers.append(identifier)
					continue
				}
				guard visibleIdentifiers.contains(identifier) else { continue }
				controller.update(
					space: space,
					isSelected: space.id == selectedSpaceID,
					favouriteTabIDs: favouriteTabIDs,
					content: content
				)
			}
			for identifier in staleIdentifiers {
				contentControllers[identifier] = nil
			}

			guard let targetIndex, targetIndex != selectedIndex else { return }

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
			let controller = contentControllers[identifier]
				?? BrowserSpacePageContentController<Content>()
			if let id = UUID(uuidString: identifier),
			   let space = spaces.first(where: { $0.id == id })
			{
				// A cached offscreen page can have intentionally stale input.
				// Refresh before it enters NSPageController's live strip.
				controller.update(
					space: space,
					isSelected: space.id == selectedSpaceID,
					favouriteTabIDs: favouriteTabIDs,
					content: content
				)
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
		private var signature: BrowserSpacePageSignature?

		override func loadView() {
			view = NSView()
		}

		func update(
			space: BrowserSpace,
			isSelected: Bool,
			favouriteTabIDs: [UUID],
			content: @escaping (BrowserSpace, Bool, [UUID]) -> Content
		) {
			let nextSignature = BrowserSpacePageSignature(
				space,
				isSelected: isSelected,
				favouriteTabIDs: favouriteTabIDs
			)
			guard hostingView == nil || signature != nextSignature else { return }
			signature = nextSignature
			let rootView = content(space, isSelected, favouriteTabIDs)

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
		let favouriteTabIDs: [UUID]
		let onSelectSpace: (UUID) -> Void
		let content: (BrowserSpace, Bool, [UUID]) -> Content

		@State private var scrollSpaceID: UUID?
		@State private var isScrolling = false
		@Environment(\.accessibilityReduceMotion) private var reduceMotion

		init(
			spaces: [BrowserSpace],
			selectedSpaceID: UUID,
			favouriteTabIDs: [UUID],
			onSelectSpace: @escaping (UUID) -> Void,
			@ViewBuilder content: @escaping (BrowserSpace, Bool, [UUID]) -> Content
		) {
			self.spaces = spaces
			self.selectedSpaceID = selectedSpaceID
			self.favouriteTabIDs = favouriteTabIDs
			self.onSelectSpace = onSelectSpace
			self.content = content
		}

		var body: some View {
			ScrollView(.horizontal) {
				LazyHStack(spacing: 0) {
					ForEach(spaces) { space in
						content(space, space.id == selectedSpaceID, favouriteTabIDs)
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
