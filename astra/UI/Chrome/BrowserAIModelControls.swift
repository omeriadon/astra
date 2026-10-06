import SwiftUI

struct BrowserAIModelControls: View {
	@Binding var selectedProvider: String
	@Binding var selectedModelID: String
	@Binding var selectedReasoning: String
	let provider: String
	var isDisabled = false
	var identifierPrefix = "ai-chat"
	var initialModelID = ""
	var initialReasoning = ""
	@State private var models: [BrowserAIModelOption] = []
	@State private var showingModels = false
	@State private var loading = false
	@State private var loadingProvider: String?
	@State private var error: String?

	private var selected: BrowserAIModelOption? {
		models.first { $0.id == selectedModelID }
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Button(selected?.title ?? "Choose Model", systemImage: "cpu") { showingModels = true }
				.lineLimit(1)
				.accessibilityLabel("Model: \(selected?.title ?? "Choose Model")")
				.accessibilityIdentifier("\(identifierPrefix)-model")
				.popover(isPresented: $showingModels) {
					List {
						if loading {
							ProgressView("Retrieving Models")
						}
						if let error {
							Text(error)
								.foregroundStyle(.secondary)
								.fixedSize(horizontal: false, vertical: true)
						}
						#if os(macOS)
							if error != nil {
								Button("Allow Account Files", systemImage: "folder.badge.plus") {
									Task {
										if await BrowserAICLI.authorize(provider: provider) {
											await refresh()
										}
									}
								}
								.accessibilityIdentifier("ai-allow-account-files")
								Button("Allow Installed Command", systemImage: "terminal") {
									Task {
										if await BrowserAICLI.authorizeCommand(provider: provider) {
											await refresh()
										}
									}
								}
								.accessibilityIdentifier("ai-allow-installed-command")
							}
						#endif
						ForEach(models) { model in
							Button(model.title, systemImage: "cpu") {
								selectedProvider = provider
								selectedModelID = model.id
								selectedReasoning = model.reasoningLevels.contains("low") ? "low" : model.defaultReasoning ?? ""
								showingModels = false
							}
							.accessibilityIdentifier("\(identifierPrefix)-model-\(model.id)")
						}
					}
					.listStyle(.sidebar)
					.scrollContentBackground(.hidden)
					.frame(width: 340, height: 350)
					.task { await refresh() }
				}
			Picker("Reasoning", selection: $selectedReasoning) {
				Text("Provider Default").tag("")
				ForEach(selected?.reasoningLevels ?? [], id: \.self) { level in
					Text(level.capitalized).tag(level)
				}
			}
			.accessibilityIdentifier("\(identifierPrefix)-reasoning")
		}
		.buttonStyle(.glass)
		.disabled(isDisabled)
		.task(id: provider) {
			if selectedProvider != provider {
				selectedModelID = initialModelID
				selectedReasoning = initialReasoning
				selectedProvider = provider
			}
			models = []
			await refresh()
		}
	}

	private func refresh() async {
		let requestedProvider = provider
		guard loadingProvider != requestedProvider else { return }
		loadingProvider = requestedProvider
		loading = true
		error = nil
		defer {
			if loadingProvider == requestedProvider {
				loading = false
				loadingProvider = nil
			}
		}
		do {
			let result = try await BrowserAICLI.models(provider: requestedProvider)
			try Task.checkCancellation()
			guard provider == requestedProvider else { return }
			models = result
			if result.isEmpty {
				error = "The installed command returned no available models."
			}
			if selectedModelID.isEmpty, let first = result.first {
				selectedProvider = provider
				selectedModelID = first.id
				selectedReasoning = first.reasoningLevels.contains("low") ? "low" : first.defaultReasoning ?? ""
			}
		} catch {
			if !Task.isCancelled, provider == requestedProvider {
				self.error = error.localizedDescription
			}
		}
	}
}
