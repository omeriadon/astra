#if os(macOS) && !ASTRA_WEBSITE_APP_RUNTIME && !ASTRA_WEBSITE_APP_HELPER
import AppIntents
import AppKit
import AstraAutomationCore
import Foundation

/// System Settings > Focus > Focus Filters > Astra. A one-time navigation, not a lock.
struct AstraFocusSpaceIntent: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Astra Space"
    static let description = IntentDescription("Switch Astra to this space when the Focus activates. You can still switch spaces manually.")
    static let pendingSpaceKey = "astra.focus.pendingSpaceID"
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Space") var space: AstraSpaceEntity?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Astra Space", subtitle: space.map { "\($0.name)" } ?? "No space selected")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let rawID = space?.id, let uuid = UUID(uuidString: rawID) else {
            UserDefaults.standard.removeObject(forKey: Self.pendingSpaceKey)
            return .result()
        }
        UserDefaults.standard.set(rawID, forKey: Self.pendingSpaceKey)
        if let browser = try? await AstraSystemActions.existingBrowser(),
           browser.workspace.spaces.contains(where: { $0.id == uuid }) {
            browser.selectSpace(uuid)
            UserDefaults.standard.removeObject(forKey: Self.pendingSpaceKey)
        }
        return .result()
    }
}

struct AstraSwitchSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Space") var space: AstraSpaceEntity
    @MainActor
    func perform() async throws -> some IntentResult {
        try await AstraSystemActions.switchSpace(id: space.id)
        return .result()
    }
}

struct AstraCreateSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        let browser = try await AstraSystemActions.browser()
        browser.createSpace()
        return .result()
    }
}

struct AstraListSpacesIntent: AppIntent {
    static let title: LocalizedStringResource = "List Astra Spaces"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some ReturnsValue<[AstraSpaceEntity]> {
        let spaces = try await AstraSpaceEntity.Query().suggestedEntities()
        return .result(value: spaces)
    }
}

struct AstraNewNamedSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Named Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Name") var name: String
    @MainActor
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
    static let title: LocalizedStringResource = "Rename Astra Space"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Space") var space: AstraSpaceEntity
    @Parameter(title: "New Name") var newName: String
    @MainActor
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
