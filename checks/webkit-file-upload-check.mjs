import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");

const desktop = source("astra/UI/Shell/DesktopBrowserShell.swift");
const tabRow = source("astra/UI/Tabs/BrowserTabRow.swift");
const controller = source("astra/Web/Navigation/BrowserController.swift");
const websiteUI = source("astra/Web/Navigation/BrowserWebsiteUI.swift");
const info = source("astra/Special/Info.plist");
const fixture = source("checks/fixtures/webkit-file-upload.html");

const tabType = 'UTType(exportedAs: "com.omeriadon.astra.tab", conformingTo: .data)';
for (const [name, code] of [["page", desktop], ["tab row", tabRow]]) {
  assert.ok(code.includes(`.onDrop(of: [${tabType}]`), `${name}: drop destination must accept only Astra tabs`);
  assert.ok(!code.includes(".onDrop(of: [UTType.data]"), `${name}: generic data would hijack file drops`);
}
assert.ok(!tabRow.includes('registerDataRepresentation(forTypeIdentifier: "public.data"'),
  "Internal tab drags must not advertise a generic file/data payload");
assert.ok(tabRow.includes('registerDataRepresentation(forTypeIdentifier: "com.omeriadon.astra.tab"'),
  "Internal tab drags must continue to advertise their private type");
assert.ok(info.includes("<string>com.omeriadon.astra.tab</string>"),
  "The private drag type must be exported in the app Info.plist");

const ownership = controller.match(/func ownsFileUpload\([\s\S]*?\n\t\t\}/)?.[0];
assert.ok(ownership, "File uploads need their own document/window ownership check");
assert.ok(ownership.includes("promptOwnership?(webView) == true"));
assert.ok(ownership.includes("webView.window === window"));
assert.ok(ownership.includes("window.isVisible"));
assert.ok(!ownership.includes("isKeyWindow"),
  "File panels must remain valid as AppKit changes key-window focus");
assert.match(controller, /for url in urls where url\.startAccessingSecurityScopedResource\(\)/,
  "Only successful security-scope starts should be retained and later stopped");

const upload = websiteUI.match(/runOpenPanelWith parameters: WKOpenPanelParameters[\s\S]*?(?=\n\t\tfunc webView\()/)?.[0];
assert.ok(upload, "macOS WKUIDelegate must implement the file picker; WebKit disables it by default");
assert.ok(upload.includes("ownsFileUpload(in: webView, documentID: documentID, window: window)"));
assert.ok(!upload.includes("ownsPrompt(in:"),
  "WebKit's file picker cannot use the JavaScript prompt's key-window gate");
assert.ok(upload.includes("panel.allowsMultipleSelection = parameters.allowsMultipleSelection"));
assert.ok(upload.includes("panel.canChooseDirectories = parameters.allowsDirectories"));
assert.ok(upload.includes("panel.canChooseFiles = !parameters.allowsDirectories"));
assert.ok(upload.includes("panel.beginSheetModal(for: window)"));
assert.ok(upload.includes("let urls = response == .OK && current ? selectedURLs : nil"));
assert.ok(upload.includes("guard !completed else { return }"),
  "Cancel/selection/teardown races must complete WebKit's callback only once");
assert.ok(upload.includes("self.endLifecycleOperation()"));
assert.ok(upload.includes("panel.cancel(nil)"),
  "Switching tabs or navigating away must dismiss an obsolete file picker");
assert.ok(!upload.includes("url.stopAccessingSecurityScopedResource()"),
  "Do not stop a URL's security scope unless it was started");

for (const id of ["single", "multiple", "directory", "file-drop-zone"]) {
  assert.ok(fixture.includes(`id="${id}"`), `Missing manual WebKit upload smoke case: ${id}`);
}
console.log("WebKit file upload and drag-and-drop guards passed");
