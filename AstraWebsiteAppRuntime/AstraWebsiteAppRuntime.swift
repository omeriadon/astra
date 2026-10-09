import Foundation

@_cdecl("AstraWebsiteAppMain")
@MainActor
public func astraWebsiteAppMain() {
	BrowserWebsiteAppHelperMain.main()
}

@_cdecl("AstraBrowserMain")
@MainActor
public func astraBrowserMain() {
	browserApp.main()
}
