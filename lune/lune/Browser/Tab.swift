import SwiftUI
import UIKit
import WebKit
import Combine

@MainActor
enum WebViewFactory {
    static func makeConfiguration(dataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.allowsInlineMediaPlayback = true
        return configuration
    }
}

final class Tab: NSObject, ObservableObject, Identifiable {
    let id = UUID()

    @Published var url: URL?
    @Published var title: String = ""
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var snapshot: UIImage? {
        didSet { snapshotData = nil }
    }
    private var snapshotData: Data?

    var snapshotJPEG: Data? {
        if let snapshotData { return snapshotData }
        guard let snapshot else { return nil }
        let size = CGSize(width: 360, height: 360 * snapshot.size.height / max(snapshot.size.width, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            snapshot.draw(in: CGRect(origin: .zero, size: size))
        }
        snapshotData = small.jpegData(compressionQuality: 0.6)
        return snapshotData
    }
    @Published private(set) var hasLoaded = false
    @Published var themeColor: UIColor?
    @Published var pageColor: UIColor?
    /// A restored tab shows its saved snapshot until the real page paints.
    @Published var awaitingPaint = false

    let webView: WKWebView
    /// Private tabs share an in-memory data store and never touch history or disk.
    let isPrivate: Bool
    var onVisit: ((URL, String) -> Void)?
    var onPageFinished: (() -> Void)?
    var onSnapshot: (() -> Void)?
    private var cancellables: Set<AnyCancellable> = []

    init(dataStore: WKWebsiteDataStore = .default(), isPrivate: Bool = false) {
        self.isPrivate = isPrivate
        webView = WKWebView(frame: .zero, configuration: WebViewFactory.makeConfiguration(dataStore: dataStore))
        super.init()

        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear

        webView.publisher(for: \.url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, self.hasLoaded, let value, value.scheme != "about" else { return }
                self.url = value
            }
            .store(in: &cancellables)
        webView.publisher(for: \.title)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, self.hasLoaded, let value, !value.isEmpty else { return }
                self.title = value
            }
            .store(in: &cancellables)
        webView.publisher(for: \.isLoading)
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
        webView.publisher(for: \.estimatedProgress)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.progress = value
                if value > 0.7, self.awaitingPaint { self.awaitingPaint = false }
            }
            .store(in: &cancellables)
        webView.publisher(for: \.canGoBack)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canGoForward)

        webView.publisher(for: \.themeColor)
            .receive(on: DispatchQueue.main)
            .assign(to: &$themeColor)

        webView.publisher(for: \.underPageBackgroundColor)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] color in
                guard let self, self.hasLoaded else { return }
                self.pageColor = color
            }
            .store(in: &cancellables)

        webView.loadHTMLString("", baseURL: nil)
    }

    var showsStartPage: Bool {
        !hasLoaded && (url == nil || url?.absoluteString == "about:blank")
    }

    var domain: String {
        guard let host = url?.host(percentEncoded: false) else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if !domain.isEmpty { return domain }
        return "New Tab"
    }

    func load(_ destination: URL) {
        diagnostic("load \(destination.absoluteString)")
        hasLoaded = true
        webView.load(URLRequest(url: destination))
    }

    func ensureLoaded() {
        guard !hasLoaded, let url, url.scheme != "about" else { return }
        awaitingPaint = snapshot != nil
        load(url)
    }

    func captureSnapshot(completion: (() -> Void)? = nil) {
        guard hasLoaded, !webView.isLoading || webView.estimatedProgress > 0.6, webView.window != nil else {
            completion?()
            return
        }
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            Task { @MainActor in
                if let self, let image {
                    self.snapshot = image
                    self.onSnapshot?()
                }
                completion?()
            }
        }
    }
}

extension Tab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pageColor = webView.underPageBackgroundColor
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        awaitingPaint = false
        diagnostic("failed \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        diagnostic("finished \(webView.url?.absoluteString ?? "none")")
        if let url = webView.url {
            onVisit?(url, webView.title ?? "")
        }
        pageColor = webView.underPageBackgroundColor
        awaitingPaint = false
        captureSnapshot()
        onPageFinished?()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        diagnostic("policy \(navigationAction.request.url?.absoluteString ?? "nil")")
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            return decisionHandler(.allow)
        }
        switch scheme {
        case "http", "https", "about", "file", "data", "blob":
            decisionHandler(.allow)
        default:
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}

extension Tab {
    var stripColor: Color {
        if let themeColor { return Color(uiColor: themeColor) }
        if let pageColor { return Color(uiColor: pageColor) }
        return Color(.systemBackground)
    }
}
