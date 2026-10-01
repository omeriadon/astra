import Foundation

let url = URL(string: "https://example.invalid")!
let get = URLRequest(url: url)
var head = URLRequest(url: url)
head.httpMethod = "HEAD"
var post = URLRequest(url: url)
post.httpMethod = "POST"
post.httpBody = Data("field=value".utf8)
var emptyPost = URLRequest(url: url)
emptyPost.httpMethod = "POST"

assert(BrowserNavigationFailure.canRetryAutomatically(get))
assert(BrowserNavigationFailure.canRetryAutomatically(head))
assert(!BrowserNavigationFailure.canRetryAutomatically(post))
assert(!BrowserNavigationFailure.canRetryAutomatically(emptyPost))
assert(!BrowserNavigationFailure.canRetryAutomatically(nil))
assert(BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorDNSLookupFailed), url: url).kind == .websiteNotFound)
assert(BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost), url: url).kind == .connectionLost)
assert(BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed), url: url).kind == .secureConnectionFailed)
assert(BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorHTTPTooManyRedirects), url: url).kind == .tooManyRedirects)
assert(BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL), url: url).kind == .invalidAddress)
