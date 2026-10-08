"""Compile and exercise the production hibernation manager with isolated collaborators."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'astra/Models/Core/BrowserHibernationManager.swift').read_text().replace('import Defaults\n', '')
program = r'''
import Foundation

@MainActor enum Defaults {
    struct Key { static let automaticHibernationEnabled = Key() }
    static var enabled = true
    static subscript(_: Key) -> Bool { enabled }
}
struct BrowserTabProcessMemorySnapshot: Sendable {}
@MainActor final class TestWebView {
    var window: Int?
    var interactionState: Any? = Data([1, 2, 3])
}
@MainActor final class BrowserController {
    var navigationIdentifier = 1
    var canAutomaticallyHibernate = true
    var webViewIfLoaded: TestWebView? = TestWebView()
    var activityResult = true
    var onRefresh: (() -> Void)?
    var onSample: (() -> Void)?
    func refreshHibernationSafety() async -> Bool {
        onRefresh?()
        return activityResult
    }
    func tabProcessMemorySnapshot() async -> BrowserTabProcessMemorySnapshot? {
        onSample?()
        return nil
    }
    static func logReclamation(for _: BrowserTabProcessMemorySnapshot) async {}
}
@MainActor final class BrowserTab {
    let id = UUID()
    var lastInteractionAt: Date
    var controller: BrowserController? = BrowserController()
    var isHibernated = false
    var internalPage: Int?
    var canHibernate = true
    var peeks: [Int] = []
    init(age: TimeInterval) { lastInteractionAt = .now.addingTimeInterval(-age) }
}
@MainActor final class Browser {
    struct Space { var pinnedTabIDs: [UUID] = [] }
    struct Workspace { var spaces: [Space] = [] }
    final class Downloads { var activeProgress: Double? }
    final class Session { let downloads = Downloads() }
    var tabs: [BrowserTab]
    var selectedTabID = UUID()
    var favouriteTabs: [BrowserTab] = []
    var workspace = Workspace()
    let session = Session()
    var isHydrationFinished = true
    var isPrivate = false
    var reclaimed: [UUID] = []
    init(_ tabs: [BrowserTab]) { self.tabs = tabs }
    func tab(withID id: UUID) -> BrowserTab? { tabs.first { $0.id == id } }
    func finishAutomaticHibernation(_ tab: BrowserTab, interactionState: Data) -> Bool {
        precondition(interactionState == tab.controller?.webViewIfLoaded?.interactionState as? Data)
        reclaimed.append(tab.id)
        tab.isHibernated = true
        tab.controller = nil
        return true
    }
}
@MainActor final class BrowserWindowRegistry {
    static let shared = BrowserWindowRegistry()
    var openBrowsers: [Browser] = []
    var unowned: Set<UUID> = []
    func ownsTab(_ id: UUID, in _: Browser) -> Bool { !unowned.contains(id) }
}
'''
program += source
program += r'''
extension BrowserHibernationManager {
    func exerciseSweep() async {
        sweep()
        await reclamationTask?.value
    }
    func retryDelay() -> Duration {
        nextDeadlineDelay(now: .now, idleTime: Self.normalIdleTime, browser: browser!)
    }
}
@main enum HibernationChecks {
    @MainActor static func main() async {
        func make(_ age: TimeInterval = 2000) -> (BrowserTab, Browser, BrowserHibernationManager) {
            Defaults.enabled = true
            BrowserWindowRegistry.shared.unowned = []
            let tab = BrowserTab(age: age)
            let browser = Browser([tab])
            BrowserWindowRegistry.shared.openBrowsers = [browser]
            return (tab, browser, BrowserHibernationManager(browser: browser))
        }
        do {
            let (tab, browser, manager) = make()
            await manager.exerciseSweep()
            precondition(browser.reclaimed == [tab.id])
        }
        for protection in 0..<9 {
            let (tab, browser, manager) = make()
            switch protection {
            case 0: browser.selectedTabID = tab.id
            case 1: tab.controller!.canAutomaticallyHibernate = false
            case 2: browser.session.downloads.activeProgress = 0.5
            case 3: browser.favouriteTabs = [tab]
            case 4: browser.workspace.spaces = [.init(pinnedTabIDs: [tab.id])]
            case 5: tab.peeks = [1]
            case 6: tab.controller!.webViewIfLoaded!.window = 1
            case 7: BrowserWindowRegistry.shared.unowned.insert(tab.id)
            default: Defaults.enabled = false
            }
            await manager.exerciseSweep()
            precondition(browser.reclaimed.isEmpty)
            precondition(manager.retryDelay().components.seconds >= 60)
        }
        do {
            let (tab, browser, manager) = make()
            let second = Browser([tab])
            second.selectedTabID = tab.id
            BrowserWindowRegistry.shared.openBrowsers.append(second)
            await manager.exerciseSweep()
            precondition(browser.reclaimed.isEmpty)
        }
        for race in 0..<7 {
            let (tab, browser, manager) = make()
            let controller = tab.controller!
            controller.onRefresh = {
                switch race {
                case 0: browser.selectedTabID = tab.id
                case 1: tab.lastInteractionAt = .now
                case 2: controller.navigationIdentifier += 1
                case 3: tab.controller = BrowserController()
                case 4: Defaults.enabled = false
                case 5: BrowserWindowRegistry.shared.openBrowsers = []
                default: controller.activityResult = false
                }
            }
            await manager.exerciseSweep()
            precondition(browser.reclaimed.isEmpty)
        }
        do {
            let (tab, browser, manager) = make()
            tab.controller!.onSample = { browser.selectedTabID = tab.id }
            await manager.exerciseSweep()
            precondition(browser.reclaimed.isEmpty)
        }
        do {
            let (tab, browser, manager) = make()
            tab.controller!.webViewIfLoaded!.interactionState = Data(count: 4 * 1024 * 1024 + 1)
            await manager.exerciseSweep()
            precondition(browser.reclaimed.isEmpty)
        }
        do {
            let (tab, browser, manager) = make(1)
            let older = BrowserTab(age: 4000)
            browser.tabs.append(older)
            manager.handleMemoryPressure(.critical)
            await manager.exerciseSweep()
            precondition(browser.reclaimed == [older.id, tab.id])
        }
        do {
            let (tab, browser, manager) = make(1)
            manager.handleMemoryPressure(.critical)
            tab.controller!.onRefresh = { manager.handleMemoryPressure(.normal) }
            await manager.exerciseSweep()
            precondition(browser.reclaimed.isEmpty)
        }
        print("Production automatic hibernation checks passed")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='astra-hibernation-check-') as directory:
    path = Path(directory) / 'Check.swift'
    binary = Path(directory) / 'check'
    path.write_text(program)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6', '-strict-concurrency=complete', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
