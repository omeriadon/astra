import SwiftUI

struct BrowserTranslationButton: View {
	let browser: Browser
	let controller: BrowserController
	@AppStorage("translationTargetLanguage") private var targetLanguage = "en"
	@State private var pageURL: URL?
	@State private var showsTranslation = false
	@Namespace private var presentations

	private var canTranslate: Bool {
		browser.selectedTab?.activeController === controller
			&& controller.hasCurrentPageDocument
			&& !controller.isLoading
			&& controller.navigationFailure == nil
			&& !controller.isAuthenticationSessionBrowser
			&& controller.committedURL.flatMap {
				BrowserTranslationPolicy.translationURL(for: $0, language: "en", isPrivate: browser.isPrivate)
			} != nil
	}

	var body: some View {
		Button("Translate Page", systemImage: "translate") {
			pageURL = controller.committedURL
			showsTranslation = true
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.glass)
		.disabled(!canTranslate)
		.help("Translate a public page with Google Translate in a new tab")
		.accessibilityLabel("Translate Page with Google Translate")
		.accessibilityIdentifier("browser-translate-page")
		.matchedTransitionSource(id: "translate", in: presentations)
		.sheet(isPresented: $showsTranslation) {
			NavigationStack {
				List {
					Section("Language") {
						Picker("Translate To", selection: $targetLanguage) {
							ForEach(BrowserTranslationPolicy.languages, id: \.self) { language in
								Text(verbatim: Locale.current.localizedString(forIdentifier: language) ?? language)
									.tag(language)
							}
						}
						.accessibilityIdentifier("browser-translation-language")
					}
					Section("Google Translate") {
						Text("The page URL is sent to Google, which fetches and translates the website. Page text, cookies, and sign-in details are not uploaded by Astra. Pages requiring sign-in may not translate. The original stays open in its tab.")
						if let pageURL {
							Text(verbatim: pageURL.absoluteString)
								.textSelection(.enabled)
								.accessibilityIdentifier("browser-translation-url")
						}
						Text("More languages and the original view are available in Google's translation toolbar.")
					}
				}
				.navigationTitle("Translate Page")
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button(role: .cancel) { showsTranslation = false }
							.accessibilityIdentifier("browser-translation-cancel")
					}
					ToolbarItem(placement: .confirmationAction) {
						Button("Translate", systemImage: "translate", role: .confirm, action: translate)
							.buttonStyle(.glassProminent)
							.disabled(!canTranslate || controller.committedURL != pageURL)
							.accessibilityIdentifier("browser-translation-confirm")
					}
				}
			}
			.presentationDetents([.fraction(0.6)])
			#if os(iOS)
				.navigationTransition(.zoom(sourceID: "translate", in: presentations))
			#endif
			#if os(macOS)
			.frame(width: 480, height: 420)
			#endif
		}
	}

	private func translate() {
		guard canTranslate,
		      let pageURL,
		      controller.committedURL == pageURL,
		      let url = BrowserTranslationPolicy.translationURL(for: pageURL, language: targetLanguage, isPrivate: browser.isPrivate)
		else { return }
		showsTranslation = false
		browser.addTab().controller?.load(url)
	}
}
