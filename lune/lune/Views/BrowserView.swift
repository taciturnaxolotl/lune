import SwiftData
import SwiftUI

struct BrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var browser = BrowserModel()
    @State private var pageFrame: CGRect = .zero

    private var barVisible: Bool {
        switch browser.overlay {
        case .none: true
        case .overview: !browser.deckSpread
        default: false
        }
    }

    var body: some View {
        ZStack {
            DarkBackdrop()

            VStack(spacing: 0) {
                pageArea
                AddressBar(browser: browser)
                    .opacity(barVisible ? 1 : 0)
                    .allowsHitTesting(browser.overlay == .none)
                    .animation(.easeOut(duration: 0.2), value: barVisible)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)

            if browser.overlay == .overview {
                TabOverview(browser: browser, pageFrame: pageFrame)
                    .transition(.identity)
            }
        }
        .task {
            browser.boot(context: modelContext)
            #if DEBUG
            browser.applyLaunchArguments()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            browser.persist()
            if phase == .background {
                browser.tabs.forEach { $0.captureSnapshot() }
            }
        }
        .onOpenURL { incoming in
            if incoming.scheme == "lune", let target = browser.destination(for: incoming) {
                browser.openURL(target)
            }
        }
        .overlay {
            if browser.overlay == .command {
                CommandOverlay(browser: browser)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if browser.overlay == .menu {
                PageMenu(browser: browser)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if browser.overlay == .findPage, let tab = browser.selectedTab {
                FindInPageOverlay(browser: browser, tab: tab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: settingsBinding) {
            SettingsView(browser: browser)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: browser.overlay == .command)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: browser.overlay == .menu)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: browser.overlay == .findPage)
    }

    @ViewBuilder
    private var pageArea: some View {
        if let tab = browser.selectedTab {
            let receded = browser.overlay == .command && !tab.showsStartPage
            BrowserPage(browser: browser, tab: tab)
                .id(tab.id)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    pageFrame = frame
                }
                .clipShape(
                    RoundedRectangle(cornerRadius: receded ? 40 : 0, style: .continuous)
                        .inset(by: receded ? 0 : -200)
                )
                .scaleEffect(receded ? 0.95 : 1, anchor: .top)
                .offset(y: receded ? -14 : 0)
                .animation(.spring(response: 0.38, dampingFraction: 0.88), value: receded)
                .overlay(alignment: .bottom) {
                    LoadingLine(tab: tab)
                        .offset(y: 1.25)
                        .zIndex(1)
                }
        } else {
            StartPageView(browser: browser)
                .ignoresSafeArea(edges: .top)
                .transition(.opacity)
        }
    }

    private var settingsBinding: Binding<Bool> {
        Binding(
            get: { browser.overlay == .settings },
            set: { isPresented in
                browser.overlay = isPresented ? .settings : .none
            }
        )
    }
}

/// Blue progress along the top edge of the bottom bar, like Arc's.
private struct LoadingLine: View {
    @ObservedObject var tab: Tab

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color(.systemBlue))
                .frame(width: geometry.size.width * tab.progress, height: 2.5)
                .animation(.linear(duration: 0.2), value: tab.progress)
        }
        .frame(height: 2.5)
        .opacity(tab.isLoading ? 1 : 0)
        .animation(.easeOut(duration: 0.3).delay(tab.isLoading ? 0 : 0.2), value: tab.isLoading)
    }
}
