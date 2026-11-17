import SwiftUI
import WebKit

final class TabWebViewController: UIViewController {
    let tabModel: Tab

    init(tab: Tab) {
        self.tabModel = tab
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = tabModel.webView
    }
}

struct WebViewHost: UIViewControllerRepresentable {
    let tab: Tab

    func makeUIViewController(context: Context) -> TabWebViewController {
        TabWebViewController(tab: tab)
    }

    func updateUIViewController(_ uiViewController: TabWebViewController, context: Context) {}
}

struct BrowserPage: View {
    let browser: BrowserModel
    @ObservedObject var tab: Tab

    var body: some View {
        ZStack {
            WebViewHost(tab: tab)
                .opacity(tab.showsStartPage ? 0 : 1)
                .allowsHitTesting(!tab.showsStartPage)

            if tab.awaitingPaint, let snapshot = tab.snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if tab.showsStartPage {
                StartPageView(browser: browser)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .background {
            Color(uiColor: tab.pageColor ?? .systemBackground)
        }
        .background {
            tab.stripColor
                .ignoresSafeArea(edges: .top)
                .animation(.easeOut(duration: 0.25), value: tab.stripColor)
        }
        .animation(.easeOut(duration: 0.2), value: tab.awaitingPaint)
        .animation(.easeOut(duration: 0.18), value: tab.showsStartPage)
    }
}
