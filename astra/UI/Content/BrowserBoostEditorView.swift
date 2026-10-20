#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME
	import AppKit
	import JavaScriptCore
	import SwiftUI

	/// Dedicated document-style windows, independent of the browser's tab lifecycle.
	@MainActor
	final class BrowserBoostEditorWindowController: NSObject, NSWindowDelegate {
		private static var openWindows: [UUID: BrowserBoostEditorWindowController] = [:]
		let id: UUID
		let window: NSWindow

		static func open(_ id: UUID) {
			guard BrowserBoostStore.shared.boosts.contains(where: { $0.id == id }) else { return }
			if let existing = openWindows[id] {
				existing.window.makeKeyAndOrderFront(nil)
				NSApp.activate(ignoringOtherApps: true)
				return
			}
			let controller = BrowserBoostEditorWindowController(id: id)
			openWindows[id] = controller
			controller.window.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
		}

		static func close(_ id: UUID) {
			openWindows[id]?.window.close()
		}

		private init(id: UUID) {
			self.id = id
			let frame = NSRect(x: 0, y: 0, width: 900, height: 640)
			window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
			                  backing: .buffered, defer: false)
			super.init()
			window.delegate = self
			let hostingController = NSHostingController(rootView: NavigationStack {
				BrowserBoostEditorView(boostID: id)
			})
			// An AppKit-created window requires explicit SwiftUI scene bridging to
			// populate its native NSToolbar from .toolbar { } content.
			hostingController.sceneBridgingOptions = [.title, .toolbars]
			window.contentViewController = hostingController
			window.toolbarStyle = .unifiedCompact
			window.minSize = NSSize(width: 520, height: 320)
			window.title = "Boost"
			window.center()
			window.isReleasedWhenClosed = false
			window.tabbingMode = .disallowed
		}

		func windowWillClose(_: Notification) {
			Self.openWindows.removeValue(forKey: id)
		}
	}

	private enum BoostSourceLanguage: String, CaseIterable, Identifiable {
		case css = "CSS"
		case javascript = "JavaScript"
		var id: String {
			rawValue
		}
	}

	@MainActor
	private struct BrowserBoostEditorView: View {
		let boostID: UUID
		@State private var store = BrowserBoostStore.shared
		@State private var language: BoostSourceLanguage = .css
		@State private var name = ""
		@State private var isGlobal = true
		@State private var domain = ""
		@State private var css = ""
		@State private var javascript = ""
		@State private var enabled = true
		@State private var loaded = false
		@State private var revision = 0
		@State private var syntaxIssue: String?

		private var activeCode: Binding<String> {
			language == .css ? $css : $javascript
		}

		var body: some View {
			Group {
				if loaded {
					BoostCodeTextView(text: activeCode, language: language)
						.overlay(alignment: .bottomLeading) {
							if let message = syntaxIssue ?? store.validationMessage {
								Text(message)
									.font(.caption.monospaced())
									.foregroundStyle(.orange)
									.padding(8)
									.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
									.padding(12)
									.allowsHitTesting(false)
							}
						}
				} else {
					ProgressView()
				}
			}
			.navigationTitle(name.isEmpty ? "Boost" : name)
			.toolbar {
				ToolbarItem(placement: .navigation) {
					TextField("Boost name", text: $name)
						.textFieldStyle(.roundedBorder)
						.frame(width: 170)
				}
				ToolbarItem(placement: .principal) {
					Picker("Language", selection: $language) {
						ForEach(BoostSourceLanguage.allCases) { option in
							Text(option.rawValue).tag(option)
						}
					}
					.pickerStyle(.segmented)
					.frame(width: 230)
				}
				ToolbarItemGroup(placement: .primaryAction) {
					Toggle("Enabled", isOn: $enabled)
						.toggleStyle(.checkbox)
					Toggle("All Websites", isOn: $isGlobal)
						.toggleStyle(.checkbox)
					if !isGlobal {
						TextField("example.com", text: $domain)
							.textFieldStyle(.roundedBorder)
							.frame(width: 155)
					}
				}
			}
			.onAppear(perform: load)
			.onChange(of: name) { _, _ in modified() }
			.onChange(of: css) { _, _ in modified() }
			.onChange(of: javascript) { _, _ in modified() }
			.onChange(of: domain) { _, _ in modified() }
			.onChange(of: isGlobal) { _, _ in modified() }
			.onChange(of: enabled) { _, _ in modified() }
			.onChange(of: language) { _, _ in revision += 1 }
			.task(id: revision) {
				guard loaded else { return }
				try? await Task.sleep(for: .milliseconds(220))
				guard !Task.isCancelled else { return }
				persist()
				syntaxIssue = BoostSourceValidation.diagnostic(language == .css ? css : javascript, language: language)
			}
			.onDisappear(perform: persist)
		}

		private func load() {
			guard !loaded,
			      let boost = store.boosts.first(where: { $0.id == boostID }) else { return }
			name = boost.name
			isGlobal = boost.domain == nil
			domain = boost.domain ?? ""
			css = boost.css
			javascript = boost.javascript
			enabled = boost.isEnabled
			loaded = true
		}

		private func modified() {
			guard loaded else { return }
			revision &+= 1
		}

		private func persist() {
			guard loaded, var boost = store.boosts.first(where: { $0.id == boostID }) else { return }
			let normalized = isGlobal ? nil : BrowserBoost.normalizedDomain(domain)
			guard isGlobal || normalized != nil else {
				syntaxIssue = "Enter a valid domain before saving."
				return
			}
			boost.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Boost" : name
			boost.domain = normalized
			boost.css = css
			boost.javascript = javascript
			boost.isEnabled = enabled
			guard boost != store.boosts.first(where: { $0.id == boostID }) else { return }
			store.update(boost)
		}
	}

	/// JSCore compiles JavaScript without executing the user's script. CSS uses a
	/// low-cost structural scanner; full browser CSS grammar remains WebKit's job.
	@MainActor
	private enum BoostSourceValidation {
		static func diagnostic(_ text: String, language: BoostSourceLanguage) -> String? {
			guard !text.isEmpty else { return nil }
			if language == .javascript {
				let context = JSContext()
				let json = (try? JSONSerialization.data(withJSONObject: [text])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\" ]"
				let literal = String(json.dropFirst().dropLast())
				context?.evaluateScript("new Function(" + literal + ")")
				return context?.exception.map { "JavaScript: \($0)" }
			}
			var depth = 0
			var quote: Character?
			var escaped = false
			var inComment = false
			let characters = Array(text)
			var index = 0
			while index < characters.count {
				let character = characters[index]
				let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
				if inComment {
					if character == "*", next == "/" {
						inComment = false; index += 1
					}
				} else if let delimiter = quote {
					if escaped {
						escaped = false
					} else if character == "\\" {
						escaped = true
					} else if character == delimiter {
						quote = nil
					}
				} else if character == "/", next == "*" {
					inComment = true
					index += 1
				} else if character == "\"" || character == "'" {
					quote = character
				} else if character == "{" {
					depth += 1
				} else if character == "}" {
					depth -= 1
					if depth < 0 {
						return "CSS: Unexpected closing brace."
					}
				}
				index += 1
			}
			if inComment {
				return "CSS: Unclosed comment."
			}
			if quote != nil {
				return "CSS: Unclosed string."
			}
			if depth != 0 {
				return "CSS: Unbalanced braces."
			}
			return nil
		}
	}

	private struct BoostCodeTextView: NSViewRepresentable {
		@Binding var text: String
		let language: BoostSourceLanguage

		func makeCoordinator() -> Coordinator {
			Coordinator(self)
		}

		func makeNSView(context: Context) -> NSScrollView {
			let scrollView = NSScrollView()
			scrollView.hasVerticalScroller = true
			scrollView.drawsBackground = true
			let editor = NSTextView(frame: .zero)
			editor.delegate = context.coordinator
			editor.isRichText = false
			editor.isEditable = true
			editor.isAutomaticQuoteSubstitutionEnabled = false
			editor.isAutomaticDashSubstitutionEnabled = false
			editor.isAutomaticSpellingCorrectionEnabled = false
			editor.isContinuousSpellCheckingEnabled = false
			editor.isHorizontallyResizable = false
			editor.isVerticallyResizable = true
			unsafe editor.textContainer?.widthTracksTextView = true
			editor.textContainerInset = NSSize(width: 16, height: 16)
			editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
			editor.string = text
			editor.usesFindBar = true
			scrollView.documentView = editor
			context.coordinator.highlight(editor)
			return scrollView
		}

		func updateNSView(_ scrollView: NSScrollView, context: Context) {
			context.coordinator.parent = self
			guard let editor = scrollView.documentView as? NSTextView else { return }
			if editor.string != text {
				let selected = editor.selectedRange()
				editor.string = text
				editor.setSelectedRange(NSRange(location: min(selected.location, (text as NSString).length), length: 0))
			}
			if context.coordinator.lastLanguage != language {
				context.coordinator.lastLanguage = language
				context.coordinator.highlight(editor)
			}
		}

		@MainActor
		final class Coordinator: NSObject, NSTextViewDelegate {
			var parent: BoostCodeTextView
			var lastLanguage: BoostSourceLanguage
			private var pendingHighlight: Task<Void, Never>?

			init(_ parent: BoostCodeTextView) {
				self.parent = parent
				lastLanguage = parent.language
			}

			func textDidChange(_ notification: Notification) {
				guard let editor = notification.object as? NSTextView else { return }
				parent.text = editor.string
				pendingHighlight?.cancel()
				pendingHighlight = Task { @MainActor [weak self, weak editor] in
					try? await Task.sleep(for: .milliseconds(75))
					guard !Task.isCancelled, let self, let editor else { return }
					highlight(editor)
				}
			}

			func highlight(_ editor: NSTextView) {
				guard let storage = unsafe editor.textStorage else { return }
				let value = editor.string
				let range = NSRange(location: 0, length: (value as NSString).length)
				let base: [NSAttributedString.Key: Any] = [
					.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
					.foregroundColor: NSColor.labelColor,
				]
				storage.beginEditing()
				storage.setAttributes(base, range: range)
				let regex = parent.language == .css ? Self.cssTokens : Self.jsTokens
				for match in regex.matches(in: value, range: range) {
					let token = (value as NSString).substring(with: match.range)
					let color: NSColor = if token.hasPrefix("//") || token.hasPrefix("/*") {
						.secondaryLabelColor
					} else if token.hasPrefix("\"") || token.hasPrefix("'") || token.hasPrefix("`") {
						.systemGreen
					} else if token.hasPrefix("#") || token.first?.isNumber == true {
						.systemOrange
					} else {
						.systemPurple
					}
					storage.addAttribute(.foregroundColor, value: color, range: match.range)
				}
				storage.endEditing()
			}

			private static let cssTokens = try! NSRegularExpression(pattern:
				#"(?s)/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|#[a-fA-F0-9]{3,8}\b|\b(?:@media|@supports|@keyframes|important|var|calc|inherit|initial|unset|none|auto|solid|flex|grid|display|position|color|background|transform)\b|\b\d+(?:\.\d+)?\b"#)
			private static let jsTokens = try! NSRegularExpression(pattern:
				#"(?s)/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\b(?:const|let|var|function|return|if|else|for|while|async|await|class|new|this|true|false|null|undefined|try|catch|throw|import|export|default|typeof|instanceof|switch|case|break|continue)\b|\b\d+(?:\.\d+)?\b"#)
		}
	}
#endif
