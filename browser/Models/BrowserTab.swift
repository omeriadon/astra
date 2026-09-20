import Observation
import WebKit

@Observable
final class BrowserTab: Identifiable {
    let id = UUID()
    let page = WebPage()
}
