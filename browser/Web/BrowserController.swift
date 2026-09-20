import Observation
import WebKit

@MainActor
@Observable
final class BrowserController: NSObject {
	private static let startURL = URL(string: "https://www.google.com/search?newwindow=1&sca_esv=a3e7c45b0e9db7ae&sxsrf=APpeQntVo1xGA_gL9UdIPDxnCIu0EkDvBQ:1789912085476&udm=2&fbs=ABfTbFVyMZGZf1hfvX9uKjN_-G8c4u0nXx4bEIpwm1lnNH832SMIiTl3t-JZ4hGJOxPbHYRQDtz5om-6srRFNP4UK_6edrYqFyYjVoLL0-Wmdmyc0u13h2Xl3P-7Fmh0o6KIonK33XPiaENqVug3Wz4snvosAa7jzH7Rt_v0NrmMfzHNS_lQU-uhKoPgJ8pgOjL1g7N337ePchsb39T_poIr_wqV3CYjsA&q=colourful+images&sa=X&ved=2ahUKEwiHq6KQpv2WAxXtIkQIHZ09Pe8QtKgLegQIFhAB&biw=1220&bih=943&dpr=2")!

	@ObservationIgnored
	let webView = WKWebView()

	var canGoBack = false
	var canGoForward = false

	@ObservationIgnored
	private var observations: [NSKeyValueObservation] = []

	override init() {
		super.init()

		observations = [
			webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					self?.canGoBack = change.newValue ?? webView.canGoBack
				}
			},

			webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, change in
				MainActor.assumeIsolated {
					self?.canGoForward = change.newValue ?? webView.canGoForward
				}
			},
		]

		load(Self.startURL)
	}

	func load(_ url: URL) {
		webView.load(URLRequest(url: url))
	}

	func goBack() {
		webView.goBack()
	}

	func goForward() {
		webView.goForward()
	}

	func reload() {
		webView.reload()
	}
}
