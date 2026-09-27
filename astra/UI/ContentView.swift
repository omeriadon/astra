//
//  ContentView.swift
//  browser
//
//  Created by Adon Omeri on 20/9/2026.
//

import SwiftUI

struct ContentView: View {
	@State private var browser = Browser()

	var body: some View {
		BrowserRootView(browser: $browser)
			.onOpenURL { url in
				guard url.scheme == "http" || url.scheme == "https" else { return }
				let tab = browser.addTab()
				tab.controller?.load(url)
			}
	}
}
