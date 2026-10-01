import Foundation

@main
struct Task05PermissionsCheck {
	@MainActor
	static func main() throws {
		let suiteName = "task05-permissions-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let legacy = Data(#"[{"origin":"https://EXAMPLE.com/path","topOrigin":"https://example.com","capability":"camera","allowed":true},{"origin":"https://example.com","topOrigin":"https://example.com","capability":"microphone","allowed":false}]"#.utf8)
		defaults.set(legacy, forKey: "websitePermissions")
		let permissions = BrowserSitePermissions(isPrivate: false, defaults: defaults)
		precondition(permissions.entries.count == 2)
		precondition(permissions.decision(origin: "https://example.com:443", topOrigin: "https://example.com", capability: .camera) == true)
		precondition(permissions.decision(origin: "https://example.com", topOrigin: "https://embedded.test", capability: .camera) == nil)
		precondition(permissions.decision(origin: "https://example.com", topOrigin: "https://example.com", capability: .microphone) == false)

		let persistedBeforeTemporaryGrant = defaults.data(forKey: "websitePermissions")
		let controllerID = UUID()
		permissions.set(.allowOnce, origin: "HTTPS://EXAMPLE.COM/a", topOrigin: "https://example.com:443", capability: .location, controllerID: controllerID, documentID: 7)
		precondition(permissions.effectiveDecision(origin: "https://example.com", topOrigin: "https://example.com", capability: .location, controllerID: controllerID, documentID: 7) == .allowOnce)
		precondition(permissions.effectiveDecision(origin: "https://example.com", topOrigin: "https://example.com", capability: .location, controllerID: UUID(), documentID: 7) == nil)
		precondition(permissions.effectiveDecision(origin: "https://example.com", topOrigin: "https://example.com", capability: .location, controllerID: controllerID, documentID: 8) == nil)
		permissions.removeTemporaryDecisions(controllerID: controllerID)
		precondition(permissions.effectiveDecision(origin: "https://example.com", topOrigin: "https://example.com", capability: .location, controllerID: controllerID, documentID: 7) == nil)
		precondition(defaults.data(forKey: "websitePermissions") == persistedBeforeTemporaryGrant)

		precondition(BrowserSitePermissions.Decision(response: .cancel) == nil)
		precondition(BrowserSitePermissions.Decision(response: .deny) == .deny)
		var downloads = BrowserSitePermissions.AutomaticDownloadPolicy()
		precondition(!downloads.reserveAttempt())
		precondition(downloads.reserveAttempt())
		precondition(downloads.reserveAttempt())
		downloads.didCommitDocument()
		precondition(!downloads.reserveAttempt())
		precondition(BrowserSitePermissions.origin(for: URL(string: "https://EXAMPLE.com:443/path")!) == "https://example.com")
		precondition(BrowserSitePermissions.origin(for: URL(string: "https://example.com:8443/path")!) == "https://example.com:8443")

		let future = Data("[{\"origin\":\"https://future.test\",\"topOrigin\":\"https://future.test\",\"capability\":\"futureCapability\",\"decision\":\"futureDecision\"}]".utf8)
		defaults.set(future, forKey: "websitePermissions")
		let futurePermissions = BrowserSitePermissions(isPrivate: false, defaults: defaults)
		futurePermissions.set(.allowAlways, origin: "https://other.test", topOrigin: "https://other.test", capability: .camera)
		precondition(defaults.data(forKey: "websitePermissions") == future)
		let futureField = Data("[{\"origin\":\"https://future.test\",\"topOrigin\":\"https://future.test\",\"capability\":\"camera\",\"decision\":\"allowAlways\",\"futurePolicy\":true}]".utf8)
		defaults.set(futureField, forKey: "websitePermissions")
		let extendedPermissions = BrowserSitePermissions(isPrivate: false, defaults: defaults)
		extendedPermissions.set(.deny, origin: "https://other.test", topOrigin: "https://other.test", capability: .camera)
		precondition(defaults.data(forKey: "websitePermissions") == futureField)
		let malformedBoolean = Data("[{\"origin\":\"https://future.test\",\"topOrigin\":\"https://future.test\",\"capability\":\"camera\",\"allowed\":1}]".utf8)
		defaults.set(malformedBoolean, forKey: "websitePermissions")
		let malformedPermissions = BrowserSitePermissions(isPrivate: false, defaults: defaults)
		malformedPermissions.set(.deny, origin: "https://other.test", topOrigin: "https://other.test", capability: .camera)
		precondition(defaults.data(forKey: "websitePermissions") == malformedBoolean)

		let beforePrivate = defaults.data(forKey: "websitePermissions")
		let privatePermissions = BrowserSitePermissions(isPrivate: true, defaults: defaults)
		privatePermissions.set(.allowAlways, origin: "https://private.test", topOrigin: "https://private.test", capability: .camera)
		precondition(defaults.data(forKey: "websitePermissions") == beforePrivate)

		print("Task 05 permission model checks passed")
	}

}
