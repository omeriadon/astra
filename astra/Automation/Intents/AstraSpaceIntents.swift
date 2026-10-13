#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import AppKit
import AstraAutomationCore
import Foundation

struct AstraSwitchSpaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Space") var space: AstraSpaceEntity
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.switchSpace(id: space.id)
        return .result()
    }
}

struct AstraCreateSpaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        browser.createSpace()
        return .result()
    }
}

struct AstraListSpacesIntent: AppIntent {
    static var title: LocalizedStringResource = "List Astra Spaces"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    func perform() async throws -> some ReturnsValue<[AstraSpaceEntity]> {
        let spaces = try await AstraSpaceEntity.Query().suggestedEntities()
        return .result(value: spaces)
    }
}

struct AstraNewNamedSpaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Named Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Name") var name: String
    func perform() async throws -> some IntentResult {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 128 else {
            throw AstraSystemActions.Failure.unsupportedAction
        }
        let browser = try await AstraSystemActions.browser()
        browser.createSpace()
        browser.renameSelectedSpace(text)
        return .result()
    }
}

struct AstraRenameSpaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Rename Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Space") var space: AstraSpaceEntity
    @Parameter(title: "New Name") var newName: String
    func perform() async throws -> some IntentResult {
        let text = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 128,
              let id = UUID(uuidString: space.id) else {
            throw AstraSystemActions.Failure.missingItem
        }
        let browser = try await AstraSystemActions.browser()
        guard browser.workspace.spaces.contains(where: { $0.id == id }) else {
            throw AstraSystemActions.Failure.missingItem
        }
        browser.selectSpace(id)
        browser.renameSelectedSpace(text)
        return .result()
    }
}
#endif
