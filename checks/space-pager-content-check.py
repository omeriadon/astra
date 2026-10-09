"""Exercise resident space pages and native nested scrolling without launching Astra."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
pager = (root / 'astra/UI/Shell/BrowserSpacePager.swift').read_text()
sidebar = (root / 'astra/UI/Shell/BrowserShellControls.swift').read_text()
assert 'Lazy' not in pager and 'NSPageController' not in pager and 'DragGesture' not in pager
assert 'ShellSidebarSwipe' not in sidebar and 'isSwipePreviewOnly' not in sidebar
assert 'Lazy' not in sidebar[:sidebar.index('private struct PinnedFolderRow')]

harness = r'''
import AppKit
import Observation
import SwiftUI

struct BrowserSpace: Identifiable {
    let id: UUID
    var name: String
}
@MainActor
final class Probes {
    var created: [String: NSTextField] = [:]
    var updates = 0
}
struct RowProbe: NSViewRepresentable {
    let key: String
    let selected: Bool
    let probes: Probes
    func makeNSView(context: Context) -> NSTextField {
        let view = NSTextField(labelWithString: key)
        precondition(probes.created[key] == nil, "Resident row recreated: \(key)")
        probes.created[key] = view
        return view
    }
    func updateNSView(_ view: NSTextField, context: Context) {
        probes.updates += 1
        view.stringValue = "\(key)|\(selected)"
    }
}
@MainActor
@Observable
final class PagerModel {
    var spaces = (0..<3).map { BrowserSpace(id: UUID(), name: "\($0)") }
    var selectedIndex = 1
    var selections = 0
    let scroll = BrowserSpaceScrollState()
    let probes = Probes()
}
struct PagerHarness: View {
    let model: PagerModel
    var body: some View {
        BrowserSpacePager(
            spaces: model.spaces,
            selectedSpaceID: model.spaces[model.selectedIndex].id,
            favouriteTabIDs: [],
            scrollState: model.scroll,
            onSelectSpace: { id in
                model.selectedIndex = model.spaces.firstIndex { $0.id == id }!
                model.selections += 1
            }
        ) { space, selected, _ in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(0..<40, id: \.self) { row in
                        RowProbe(key: "\(space.name)-\(row)", selected: selected, probes: model.probes)
                            .frame(height: 28)
                    }
                }
            }
        }
    }
}
@main
struct PagerCheck {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = PagerModel()
        let host = NSHostingView(rootView: PagerHarness(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        func wait(_ seconds: Double = 0.1) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
            host.layoutSubtreeIfNeeded()
        }
        wait()
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let scrollViews = descendants(host).compactMap { $0 as? NSScrollView }
        guard let horizontal = scrollViews.first(where: { ($0.documentView?.frame.width ?? 0) > $0.contentSize.width * 2 }) else {
            fatalError("Missing native horizontal scroll view: \(scrollViews.map { ($0.frame, $0.documentView?.frame) })")
        }
        let clip = horizontal.contentView
        print("native scroll views", scrollViews.count, "mounted rows", model.probes.created.count, "initial page", model.scroll.position ?? -1, "clip", clip.bounds, "document", horizontal.documentView!.frame)
        fflush(stdout)
        precondition(model.probes.created.count == 120, "Every page and row must be mounted upfront")
        precondition(abs((model.scroll.position ?? -1) - 1) < 0.01, "Initial non-first selection must align")
        let vertical = model.probes.created["1-0"]!.enclosingScrollView!
        vertical.contentView.scroll(to: NSPoint(x: 0, y: 170))
        vertical.reflectScrolledClipView(vertical.contentView)
        wait()
        let savedVertical = vertical.contentView.bounds.origin.y
        let initialUpdates = model.probes.updates
        clip.scroll(to: NSPoint(x: horizontal.contentSize.width * 1.5, y: 0))
        horizontal.reflectScrolledClipView(clip)
        wait()
        precondition(abs((model.scroll.position ?? -1) - 1.5) < 0.01, "Halfway position must report exact progress")
        precondition(model.selections == 0, "Scroll geometry must not commit selection mid-swipe")
        precondition(model.probes.updates == initialUpdates, "Theme progress must not invalidate sidebar rows")
        clip.scroll(to: NSPoint(x: horizontal.contentSize.width, y: 0))
        horizontal.reflectScrolledClipView(clip)
        wait()
        precondition(abs((model.scroll.position ?? -1) - 1) < 0.01, "Cancellation must restore exact progress")
        precondition(abs(vertical.contentView.bounds.origin.y - savedVertical) < 1, "Each page must retain its vertical offset")
        model.selectedIndex = 2
        wait(0.45)
        precondition(abs((model.scroll.position ?? -1) - 2) < 0.01, "Programmatic selection must align")
        model.selectedIndex = 1
        wait(0.45)
        precondition(abs(vertical.contentView.bounds.origin.y - savedVertical) < 1, "Returning to a page must preserve vertical scrolling")
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -45, wheel2: 0, wheel3: 0)!
        let nativeWheel = NSEvent(cgEvent: wheel)!
        let beforeWheel = vertical.contentView.bounds.origin.y
        vertical.scrollWheel(with: nativeWheel)
        wait()
        precondition(vertical.contentView.bounds.origin.y > beforeWheel, "Native vertical scrolling must move the list")
        precondition(abs((model.scroll.position ?? -1) - 1) < 0.01, "Vertical scrolling must not move between spaces")
        let horizontalStart = model.scroll.position ?? -1
        for (phase, amount) in [(1, -100), (2, -100), (4, 0)] {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: Int32(amount), wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
            vertical.scrollWheel(with: NSEvent(cgEvent: event)!)
            wait(0.02)
        }
        wait(0.6)
        print("native horizontal forwarding", horizontalStart, "->", model.scroll.position ?? -1, "commits", model.selections)
        fflush(stdout)
        precondition((model.scroll.position ?? -1) > horizontalStart, "The native vertical view must forward horizontal gestures to the pager")
        precondition(model.selectedIndex == 2, "Native paging must commit the settled selection")
        model.selectedIndex = 1
        wait(0.45)
        window.setContentSize(NSSize(width: 300, height: 220))
        wait()
        precondition(abs((model.scroll.position ?? -1) - 1) < 0.01, "Resize must preserve page alignment")
        precondition(model.probes.created.count == 120)
        window.close()
        print("Resident rows, fractional offsets, cancellation, programmatic selection, independent vertical scrolling, and resize passed")
    }
}
'''

environment = os.environ.copy()
environment.setdefault('DEVELOPER_DIR', '/Applications/Xcode-beta 27.2 beta 2.app/Contents/Developer')
with tempfile.TemporaryDirectory() as directory:
    directory = Path(directory)
    source = directory / 'Check.swift'
    source.write_text((root / 'astra/UI/Shell/BrowserSpaceScrollState.swift').read_text() + '\n' + pager + '\n' + harness)
    binary = directory / 'check'
    subprocess.run(['swiftc', '-parse-as-library', '-o', str(binary), str(source)], check=True, env=environment)
    subprocess.run([str(binary)], check=True)
