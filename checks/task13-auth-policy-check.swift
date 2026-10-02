import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
	guard condition() else {
		fatalError(message)
	}
}

@main
struct AuthenticationPolicyCheck {
	static func main() {
		let methods = BrowserAuthenticationPolicy.credentialMethods
		check(methods.count == 3, "Basic, Digest, and default challenge methods are supported")
		for method in methods {
			check(BrowserAuthenticationPolicy.decision(method: method, previousFailureCount: 0) == .prompt, "supported challenge prompts")
			check(BrowserAuthenticationPolicy.decision(method: method, previousFailureCount: 2) == .prompt, "retry remains available below the limit")
			check(BrowserAuthenticationPolicy.decision(method: method, previousFailureCount: 3) == .cancel, "repeated refusal is bounded")
		}
		check(BrowserAuthenticationPolicy.decision(method: NSURLAuthenticationMethodServerTrust, previousFailureCount: 0) == .useDefaultHandling, "server trust remains native")
		check(BrowserAuthenticationPolicy.decision(method: NSURLAuthenticationMethodClientCertificate, previousFailureCount: 0) == .useDefaultHandling, "client certificate remains native")
		check(BrowserAuthenticationPolicy.title(host: "example.test", port: 8443, realm: "staff") == "Sign in to example.test:8443 (staff)", "prompt identifies port and realm")
		check(BrowserAuthenticationPolicy.isEncrypted(protocolName: "HTTPS"), "HTTPS is recognized case insensitively")
		check(!BrowserAuthenticationPolicy.isEncrypted(protocolName: "http"), "HTTP is identified as unencrypted")
	}
}
