import SwiftUI

struct BrowserAIModelControls: View {
	@Bindable var chat: BrowserAIChat
	let provider: String
	@State private var models: [BrowserAIModelOption] = []
	@State private var showingModels = false
	@State private var loading = false
	@State private var error: String?

	private var selected: BrowserAIModelOption? {
		models.first { $0.id == chat.selectedModelID }
	}

	var body: some View {
		HStack {
			Button(selected?.title ?? "Choose Model", systemImage: "cpu") { showingModels = true }
				.lineLimit(1)
				.accessibilityIdentifier("ai-chat-model")
				.popover(isPresented: $showingModels) {
					List {
						if loading {
							ProgressView("Retrieving Models")
						}
						if let error {
							Text(error).foregroundStyle(.secondary)
						}
						ForEach(models) { model in
							Button(model.title, systemImage: "cpu") {
								chat.selectedProvider = provider
								chat.selectedModelID = model.id
								chat.selectedReasoning = model.reasoningLevels.contains("low") ? "low" : model.defaultReasoning ?? ""
								showingModels = false
							}
							.accessibilityIdentifier("ai-chat-model-\(model.id)")
						}
					}
					.listStyle(.sidebar)
					.scrollContentBackground(.hidden)
					.frame(width: 340, height: 350)
					.task { await refresh() }
				}
			Picker("Reasoning", selection: $chat.selectedReasoning) {
				Text("Provider Default").tag("")
				ForEach(selected?.reasoningLevels ?? [], id: \.self) { level in Text(level.capitalized).tag(level) }
			}
			.accessibilityIdentifier("ai-chat-reasoning")
		}
		.buttonStyle(.glass)
		.disabled(chat.isResponding)
		.task(id: provider) {
			if chat.selectedProvider != provider {
				chat.selectedModelID = ""
				chat.selectedReasoning = ""
			}
			await refresh()
		}
	}

	private func refresh() async {
		loading = true
		error = nil
		defer { loading = false }
		do {
			let result = try await BrowserAICLI.models(provider: provider)
			try Task.checkCancellation()
			models = result
			if chat.selectedModelID.isEmpty, let first = result.first {
				chat.selectedProvider = provider
				chat.selectedModelID = first.id
				chat.selectedReasoning = first.reasoningLevels.contains("low") ? "low" : first.defaultReasoning ?? ""
			}
		} catch {
			if !Task.isCancelled {
				self.error = error.localizedDescription
			}
		}
	}
}
