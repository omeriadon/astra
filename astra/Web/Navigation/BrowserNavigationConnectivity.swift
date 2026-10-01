import Foundation
import Network

final class BrowserNavigationConnectivity {
	static let shared = BrowserNavigationConnectivity()
	static let didChangeNotification = Notification.Name("BrowserNavigationConnectivityDidChange")

	private let monitor = NWPathMonitor()
	private let queue = DispatchQueue(label: "astra.navigation-connectivity")

	private init() {
		monitor.pathUpdateHandler = { path in
			NotificationCenter.default.post(
				name: Self.didChangeNotification,
				object: path.status == .satisfied
			)
		}
		monitor.start(queue: queue)
	}
}
