#if os(macOS)
import Foundation

extension BrowserWebsiteAppPolicy {
	nonisolated static func shouldStayInWebsiteApp(_ destination: URL, launchURL: URL) -> Bool {
		guard validatedURL(destination) != nil,
		      let launchHost = launchURL.host?.lowercased(),
		      let destinationHost = destination.host?.lowercased()
		else { return false }
		let normalizedLaunch = launchHost.hasPrefix("www.") ? String(launchHost.dropFirst(4)) : launchHost
		let normalizedDestination = destinationHost.hasPrefix("www.") ? String(destinationHost.dropFirst(4)) : destinationHost
		return normalizedDestination == normalizedLaunch
			|| normalizedDestination.hasSuffix("." + normalizedLaunch)
			|| normalizedLaunch.hasSuffix("." + normalizedDestination)
	}
}
#endif
