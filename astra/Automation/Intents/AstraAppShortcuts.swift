#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import AppKit
import AstraAutomationCore
import Foundation

struct AstraAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AstraOpenURLIntent(),
                    phrases: ["Open a website in \(.applicationName)", "Open a URL in \(.applicationName)"],
                    shortTitle: "Open Website", systemImageName: "globe")
        AppShortcut(intent: AstraSearchWebIntent(),
                    phrases: ["Search the web with \(.applicationName)"],
                    shortTitle: "Search Web", systemImageName: "magnifyingglass")
        AppShortcut(intent: AstraNewTabIntent(),
                    phrases: ["New tab in \(.applicationName)"],
                    shortTitle: "New Tab", systemImageName: "plus.square")
        AppShortcut(intent: AstraNewWindowIntent(),
                    phrases: ["New window in \(.applicationName)"],
                    shortTitle: "New Window", systemImageName: "macwindow.badge.plus")
        AppShortcut(intent: AstraMiniAstraIntent(),
                    phrases: ["Open Mini \(.applicationName)"],
                    shortTitle: "Mini Astra", systemImageName: "macwindow")
        AppShortcut(intent: AstraBookmarkCurrentPageIntent(),
                    phrases: ["Bookmark this page in \(.applicationName)"],
                    shortTitle: "Bookmark Page", systemImageName: "bookmark")
        AppShortcut(intent: AstraSaveCurrentPageIntent(),
                    phrases: ["Save this page in \(.applicationName)"],
                    shortTitle: "Save Page", systemImageName: "text.book.closed")
        AppShortcut(intent: AstraCreateEaselIntent(),
                    phrases: ["Create an easel in \(.applicationName)"],
                    shortTitle: "New Easel", systemImageName: "square.on.square")
        AppShortcut(intent: AstraSwitchSpaceIntent(),
                    phrases: ["Switch spaces in \(.applicationName)"],
                    shortTitle: "Switch Space", systemImageName: "square.stack.3d.up")
        AppShortcut(intent: AstraToggleAISidebarIntent(),
                    phrases: ["Open AI in \(.applicationName)"],
                    shortTitle: "AI Sidebar", systemImageName: "bubble.left.and.text.bubble.right")
    }
}
#endif
