//
//  ContentView.swift
//  browser
//
//  Created by Adon Omeri on 20/9/2026.
//

import SwiftUI

struct ContentView: View {
	@Binding var browser: Browser

	var body: some View {
		BrowserRootView(browser: $browser)
	}
}
