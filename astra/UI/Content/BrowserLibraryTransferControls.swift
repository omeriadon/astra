import SwiftUI
import UniformTypeIdentifiers

struct BrowserLibraryTransferControls: View {
	let browser: Browser
	let scope: BrowserImportScope
	@Namespace private var transitions
	@State private var showsImport = false
	@State private var showsExport = false
	@State private var exportDocument: BrowserLibraryExportDocument?
	@State private var errorMessage = ""
	@State private var showsError = false

	private var title: String {
		scope == .bookmarks ? "Bookmarks" : "History"
	}

	var body: some View {
		HStack {
			Button("Import \(title)", systemImage: "square.and.arrow.down") {
				showsImport = true
			}
			.labelStyle(.iconOnly)
			.accessibilityLabel("Import \(title)")
			.accessibilityIdentifier("import-\(scope.rawValue)")
			.matchedTransitionSource(id: "library-import", in: transitions)
			Button("Export \(title)", systemImage: "square.and.arrow.up") {
				prepareExport()
			}
			.labelStyle(.iconOnly)
			.accessibilityLabel("Export \(title)")
			.accessibilityIdentifier("export-\(scope.rawValue)")
		}
		.disabled(browser.isPrivate || browser.isMini)
		.sheet(isPresented: $showsImport) {
			NavigationStack {
				BrowserImportView(browser: browser, scope: scope)
					.navigationTitle("Import \(title)")
					.toolbar {
						ToolbarItem(placement: .cancellationAction) {
							Button(role: .cancel) { showsImport = false }
								.accessibilityIdentifier("dismiss-library-import")
						}
					}
			}
			#if os(iOS)
			.navigationTransition(.zoom(sourceID: "library-import", in: transitions))
			.presentationDetents([.fraction(0.7), .large])
			#else
			.frame(minWidth: 480, minHeight: 520)
			#endif
		}
		.fileExporter(isPresented: $showsExport, document: exportDocument, contentType: scope == .bookmarks ? .html : .json, defaultFilename: "Astra \(title)") { result in
			if case let .failure(error) = result {
				report(error)
			}
		}
		.alert("Export Failed", isPresented: $showsError) {
			Button(role: .cancel) {}
		} message: {
			Text(errorMessage)
		}
	}

	private func prepareExport() {
		guard !browser.isPrivate, !browser.isMini else { return }
		do {
			let document = scope.selecting(BrowserUserData(bookmarks: browser.bookmarks, history: browser.historyVisits))
			let data = scope == .bookmarks ? document.encodedHTML() : try JSONEncoder().encode(document)
			exportDocument = BrowserLibraryExportDocument(data: data)
			showsExport = true
		} catch {
			report(error)
		}
	}

	private func report(_ error: Error) {
		errorMessage = error.localizedDescription
		showsError = true
	}
}
