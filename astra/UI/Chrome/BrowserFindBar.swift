import Defaults
import SwiftUI

struct BrowserFindBar: View {
	@Bindable var controller: BrowserController
	@FocusState private var isFocused: Bool
	@Default(.aiFind) private var aiEnabled
	@Default(.aiFeaturesEnabled) private var allFeatures
	@Default(.aiFindContextLimit) private var contextLimit
	@State private var answer = ""
	@State private var aiError: String?
	@State private var isAnswering = false

	private var answerKey: String {
		"\(controller.findText)|\(String(describing: controller.findHasMatch))|\(controller.navigationIdentifier)|\(aiEnabled)|\(contextLimit)|\(allFeatures)"
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				Image(systemName: "magnifyingglass")
					.accessibilityHidden(true)
				TextField("Find in Page", text: $controller.findText)
					.textFieldStyle(.plain)
					.focused($isFocused)
					.onSubmit { controller.findNext() }
					.onChange(of: controller.findText) { _, _ in
						controller.findNext()
					}
					.onKeyPress(.escape) {
						controller.dismissFind()
						return .handled
					}
					.accessibilityIdentifier("find-in-page-field")
				if !controller.findText.isEmpty, controller.findHasMatch == false {
					Text("No matches")
						.font(.caption)
						.foregroundStyle(.secondary)
						.accessibilityIdentifier("find-in-page-no-match")
				}
				if !controller.findText.isEmpty, controller.findMatchCount > 0 {
					Text("\(controller.findMatchIndex) of \(controller.findMatchCount)")
						.monospacedDigit()
						.font(.caption)
						.accessibilityLabel("Match \(controller.findMatchIndex) of \(controller.findMatchCount)")
						.accessibilityIdentifier("find-in-page-match-count")
				}
				if !controller.findText.isEmpty, controller.findHasMatch == true, controller.findMatchCount == 0 {
					Text("Match found")
						.font(.caption)
						.accessibilityIdentifier("find-in-page-native-match")
				}
				Button("Previous Match", systemImage: "chevron.up") {
					controller.findNext(backwards: true)
				}
				.labelStyle(.iconOnly)
				.accessibilityIdentifier("find-previous-match")
				Button("Next Match", systemImage: "chevron.down") {
					controller.findNext()
				}
				.labelStyle(.iconOnly)
				.accessibilityIdentifier("find-next-match")
				Button("Close Find", systemImage: "xmark", action: controller.dismissFind)
					.labelStyle(.iconOnly)
					.accessibilityIdentifier("find-close")
			}
			if isAnswering || !answer.isEmpty || aiError != nil {
				Divider()
				if isAnswering, answer.isEmpty {
					ProgressView("Reading Page")
				}
				if !answer.isEmpty {
					ScrollView {
						Text((try? AttributedString(markdown: answer)) ?? AttributedString(answer))
							.frame(maxWidth: .infinity, alignment: .leading)
							.textSelection(.enabled)
							.accessibilityIdentifier("find-ai-answer")
					}
					.frame(maxHeight: 300)
				}
				if let aiError {
					Text(aiError).font(.caption).foregroundStyle(.secondary)
				}
			}
		}
		.buttonStyle(.glass)
		.padding(10)
		.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
		.frame(maxWidth: 440)
		.padding(12)
		.onAppear {
			isFocused = true
			controller.findNext()
		}
		.task(id: controller.findFocusRequest) {
			await Task.yield()
			isFocused = true
		}
		.task(id: answerKey) {
			let key = answerKey
			answer = ""
			aiError = nil
			isAnswering = false
			guard allFeatures, aiEnabled, !controller.session.isPrivate, controller.findHasMatch == false,
			      !controller.findText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
			do {
				try await Task.sleep(for: .milliseconds(750))
				isAnswering = true
				defer {
					if answerKey == key {
						isAnswering = false
					}
				}
				let page = try await BrowserAIPageText.extract(from: controller)
				let context = contextLimit ? try await page.limited(to: 30000, onlyAbove: 40000) : page
				let notice = context.text == page.text ? "" : "\nOnly the first 30,000 tokens of this large page are supplied. State this limitation when relevant."
				let result = try await BrowserAI.shared.performStreaming(
					BrowserPageAnswerFeature(feature: .find),
					input: .init(question: controller.findText, context: context.prompt + notice)
				) { snapshot in
					if !Task.isCancelled, answerKey == key {
						answer = snapshot
					}
				}
				if !Task.isCancelled, answerKey == key {
					answer = result
				}
			} catch {
				if !Task.isCancelled, answerKey == key {
					answer = ""
					aiError = error.localizedDescription
				}
			}
		}
		.onDisappear { controller.invalidateFindResults() }
		.accessibilityIdentifier("find-in-page-bar")
	}
}
