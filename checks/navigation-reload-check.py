"""Exercise the production reload decisions with a small mock WebView."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "astra/Web/Navigation/BrowserController.swift").read_text()

reload_start = source.index("\tfunc reload() {")
reload_end = source.index("\n\tfunc stopLoading()", reload_start)
origin_start = source.index("\tfunc reloadFromOrigin()")
origin_end = source.index("\n\tfunc zoomIn()", origin_start)
methods = source[reload_start:reload_end] + source[origin_start:origin_end]
methods = methods.replace(
    '\t\tBrowserLog.info(.navigation, "navigation.reload", metadata: ["controller": BrowserLog.id(id), "url": BrowserLog.url(url), "failure": String(navigationFailure != nil)])\n',
    "",
)
load_start = source.index("\tprivate func load(_ request:")
load_end = source.index("\n\tprivate func loadPendingRequest()", load_start)
load_method = source[load_start:load_end].replace(
    '\t\tBrowserLog.debug(.navigation, "navigation.dispatch", metadata: ["controller": BrowserLog.id(id), "request": BrowserLog.request(request), "reset_retry": String(resetConnectivityRetry), "content_blocker_ready": String(session.contentBlocking.isReadyForNavigation)])\n',
    "",
)
load_method = load_method.replace("\tprivate func load(", "\tfunc load(")

check = r'''
import Foundation

struct Navigation: Equatable {
    let id: Int
}

final class MockWebView {
    var reloadResult: Navigation?
    var reloadFromOriginResult: Navigation?
    var reloadCount = 0
    var reloadFromOriginCount = 0
    var loadResult: Navigation?
    var loadRequests: [URLRequest] = []
    var customUserAgent: String?
    var url: URL?

    func reload() -> Navigation? {
        reloadCount += 1
        return reloadResult
    }

    func reloadFromOrigin() -> Navigation? {
        reloadFromOriginCount += 1
        return reloadFromOriginResult
    }

    func load(_ request: URLRequest) -> Navigation? {
        loadRequests.append(request)
        return loadResult
    }
}

struct BrowserNavigationFailure {
    enum Kind { case other }
    let kind: Kind
    let url: URL

    init(kind: Kind, url: URL) {
        self.kind = kind
        self.url = url
    }
}

struct ContentBlocking {
    var isReadyForNavigation = true
}

struct Session {
    var contentBlocking = ContentBlocking()
}

final class Policy {
    func userInitiatedNavigation() {}
}

final class HistoryManager {
    func cancelVisit() {}
}

@MainActor
final class Controller {
    let id = UUID()
    var historyVisitPolicy = Policy()
    var historyManager = HistoryManager()
    var session = Session()
    var isInvalidated = false
    var pendingWebArchive: (data: Data, baseURL: URL)?
    var pendingLocalFile: URL?
    var pendingInteractionState: Data?
    var isAuthenticationSessionBrowser = false
    var retriedAfterConnectivityReturn = false
    var navigationFailure: BrowserNavigationFailure?
    var failedRequest: URLRequest?
    var createdWebView: MockWebView?
    var url: URL?
    var currentRequest: URLRequest?
    var pendingRequest: URLRequest?
    var currentNavigation: Navigation?
    var awaitsNavigationCommit = false
    var committedURL: URL?
    var navigationDidChange: (() -> Void)?

    var hasCurrentPageDocument: Bool {
        !awaitsNavigationCommit && committedURL != nil
    }

    func userAgentOverride(for url: URL?) -> String? { nil }

    func loadPendingRequest() {}

    LOAD_METHOD

METHODS
}

func request(_ url: URL, method: String = "GET") -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    return request
}

@MainActor
func run() {
    let blankURL = URL(string: "https://blank.example")!
    let queued = request(URL(string: "https://queued.example")!)
    let blank = Controller()
    blank.url = blankURL
    blank.createdWebView = MockWebView()
    blank.pendingRequest = queued
    blank.reload()
    assert(blank.createdWebView?.loadRequests == [queued])
    assert(blank.createdWebView?.reloadCount == 0)

    let blankNative = Controller()
    blankNative.url = blankURL
    blankNative.currentRequest = queued
    blankNative.createdWebView = MockWebView()
    blankNative.createdWebView?.reloadResult = Navigation(id: 9)
    blankNative.reload()
    assert(blankNative.createdWebView?.reloadCount == 0)
    assert(blankNative.createdWebView?.loadRequests == [queued])

    let postURL = URL(string: "https://form.example")!
    let loaded = Controller()
    loaded.url = postURL
    loaded.committedURL = postURL
    loaded.currentRequest = request(postURL, method: "POST")
    loaded.createdWebView = MockWebView()
    loaded.createdWebView?.reloadResult = Navigation(id: 1)
    loaded.reload()
    assert(loaded.createdWebView?.reloadCount == 1)
    assert(loaded.createdWebView?.loadRequests.isEmpty == true)
    assert(loaded.currentNavigation == Navigation(id: 1))
    assert(loaded.awaitsNavigationCommit)

    let fallback = Controller()
    fallback.url = postURL
    fallback.committedURL = postURL
    fallback.currentRequest = request(postURL, method: "POST")
    fallback.createdWebView = MockWebView()
    fallback.reload()
    assert(fallback.createdWebView?.loadRequests == [fallback.currentRequest!])

    let declined = Controller()
    declined.url = postURL
    declined.committedURL = postURL
    declined.createdWebView = MockWebView()
    declined.createdWebView?.loadResult = nil
    declined.currentNavigation = Navigation(id: 4)
    declined.load(request(postURL))
    assert(declined.navigationFailure?.url == postURL)
    assert(declined.currentNavigation == nil)
    assert(!declined.awaitsNavigationCommit)

    let origin = Controller()
    origin.url = postURL
    origin.committedURL = postURL
    origin.createdWebView = MockWebView()
    origin.createdWebView?.reloadFromOriginResult = Navigation(id: 2)
    origin.reloadFromOrigin()
    assert(origin.createdWebView?.reloadFromOriginCount == 1)
    assert(origin.currentNavigation == Navigation(id: 2))

    let blankOrigin = Controller()
    blankOrigin.url = blankURL
    blankOrigin.currentRequest = queued
    blankOrigin.createdWebView = MockWebView()
    blankOrigin.createdWebView?.reloadFromOriginResult = Navigation(id: 3)
    blankOrigin.reloadFromOrigin()
    assert(blankOrigin.createdWebView?.reloadFromOriginCount == 0)
    assert(blankOrigin.createdWebView?.loadRequests == [queued])
}

MainActor.assumeIsolated { run() }
print("Navigation reload check passed")
'''.replace("METHODS", methods).replace("LOAD_METHOD", load_method)

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "navigation-reload-check.swift"
    path.write_text(check)
    subprocess.run(["swift", str(path)], check=True)
