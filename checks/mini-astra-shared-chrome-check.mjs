import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = (path) => readFileSync(path, "utf8");
const mini = source("astra/UI/Shell/MiniAstraView.swift");
const miniController = source("astra/UI/Shell/MiniAstraWindowController.swift");
const shell = source("astra/UI/Shell/BrowserShellControls.swift");
const desktop = source("astra/UI/Shell/DesktopBrowserShell.swift");
const picker = source("astra/UI/Chrome/BrowserSpacesBar.swift");
const app = source("astra/App/AppDelegate.swift");

const check = (condition, message) => assert.ok(condition, message);

// The same navigation, address field, and extensions are instantiated in both windows.
check(desktop.includes("ShellTopBarView(") && mini.includes("ShellTopBarView("), "shared top bar");
check(shell.includes("BrowserAddressField(browser: browser"), "shared address field");
check(shell.includes("ShellWebsiteNavigationControls("), "shared navigation controls");
check(shell.includes("ShellExtensionControls(browser: browser"), "shared extension controls");
check(shell.includes("trailingAccessory.fixedSize"), "mini action is part of toolbar layout");

// The two windows use identical chrome geometry and retain the website-colored toolbar.
check(mini.includes("sidebarShown: true") && mini.includes("reservesWindowControls: true"), "inset toolbar with traffic light clearance");
check(mini.includes("BrowserChromeMetrics.shellEdgePadding"), "shared chrome inset");
check(mini.includes("BrowserChromeMetrics.tabWindowCornerRadiusWithSidebar"), "shared rounded corners");
check(shell.includes("browser.selectedTab?.activeController?.themeColor ?? theme.tabColor"), "website-colored toolbar surface");
check(shell.includes("themeColorIsLight") && !shell.includes("usesThemeSurface"), "website theme contrast");
check(mini.includes("roundsLeadingButton: true"), "rounded Mini leading navigation button");
check(mini.includes("theme.shaderNoiseEnabled = false") && mini.includes("theme.shaderNoiseAmount = 0"), "zero-noise theme");
check(mini.includes("theme.meshColorPoints = ["), "gradient uses multiple color points");

// Menu shortcut actions are window-targeted; hiding does not delete the toolbar tree.
check(app.includes("NotificationCenter.default.post(name: .toggleBrowserTopBar, object: browser.windowID)"), "window-specific toggle dispatch");
check(app.includes("return activeBrowser != nil"), "menu enables Mini toolbar shortcut");
check(mini.includes("notification.object as? UUID == browser.windowID"), "Mini handles only its own toggle");
check(mini.includes("isTopBarRevealed"), "Mini reveals the hidden toolbar on hover");
check(mini.includes(".allowsHitTesting(topBarHeight > 0)"), "hidden toolbar cannot intercept input");

// The popover presentation is shared, with only its selection behavior injected.
check(mini.includes("BrowserSpacePickerPopover(") && picker.includes("BrowserSpacePickerPopover("), "same picker component");
check(picker.includes("onSelectSpace: ((BrowserSpace) -> Void)?"), "space picker destination callback");
check(picker.includes("browser.selectSpace(space.id)"), "normal picker retains normal selection");
check(mini.includes('Label("Open in Space"') && mini.includes(".buttonStyle(.glassProminent)"), "prominent Open in Space button");
check(miniController.includes("promote(toSpace spaceID: UUID?)"), "destination-aware promotion");
check(app.includes("destination.browser.adoptMiniTab(tab)"), "live tab adoption");
check(app.includes("destination.browser.moveTab(tab.id, to: .normal, in: spaceID)"), "destination Space placement");
check(app.includes("openBrowserWindow(showImmediately: false)"), "picker cannot raise an unwanted window");
check(miniController.includes("window.contentView = nil"), "live WebKit detached before adoption");

console.log("Mini Astra shared chrome and Space promotion checks passed.");
