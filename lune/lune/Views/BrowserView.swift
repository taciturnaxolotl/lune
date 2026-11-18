import SwiftData
import SwiftUI

struct BrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var browser = BrowserModel()
    /// Unobserved: the page's frame changes every frame while it shrinks behind the search sheet,
    /// and re-rendering the whole browser on each of those caused one-frame jumps.
    @State private var pageFrame = Box<CGRect>(.zero)

    private var barVisible: Bool {
        if browser.commandCollapsing { return false }
        switch browser.overlay {
        case .none: return true
        case .overview: return !browser.deckSpread
        default: return false
        }
    }

    var body: some View {
        ZStack {
            DarkBackdrop()

            VStack(spacing: 0) {
                pageArea
                AddressBar(browser: browser)
                    .compositingGroup()
                    .opacity(barVisible ? 1 : 0)
                    .allowsHitTesting(browser.overlay == .none)
                    // The search sheet stands in for the bar while it opens and collapses, so the
                    // hand-off must be instant or the two show at once.
                    .animation(searchOwnsBar ? nil : .easeOut(duration: 0.2), value: barVisible)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)

            if browser.overlay == .overview {
                TabOverview(browser: browser, pageFrame: pageFrame.value)
                    .transition(.identity)
            }
        }
        .environment(\.privateBrowsing, browser.isPrivate)
        .task {
            _ = KeyboardMetrics.shared
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
            // The dim behind the sheets only fades; the sheets slide over it. It is always
            // mounted and animates its opacity: a removed view keeps its last, keyboard-shrunk
            // frame, which cut the fade off halfway down the screen.
            Color.black
                .opacity(dimOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(dimOpacity > 0)
                .onTapGesture {
                    browser.commandOpensNewTab = false
                    browser.overlay = .none
                }
                .animation(dimOpacity > 0 ? .easeOut(duration: 0.25) : .easeOut(duration: 0.55), value: dimOpacity)
            if browser.overlay == .command || browser.commandCollapsing {
                CommandOverlay(browser: browser, collapsedOffset: searchTravel)
                    .transition(.asymmetric(insertion: .offset(y: searchTravel), removal: .identity))
                    .allowsHitTesting(!browser.commandCollapsing)
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
        .animation(
            browser.overlay == .command ? LuneTheme.sheetSpring : LuneTheme.sheetCloseSpring,
            value: browser.overlay == .command
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: browser.overlay == .menu)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: browser.overlay == .findPage)
    }

    @ViewBuilder
    private var pageArea: some View {
        if let tab = browser.selectedTab {
            let receded = browser.searchSheetShown && !tab.showsStartPage
            BrowserPage(browser: browser, tab: tab)
                .id(tab.id)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    pageFrame.value = frame
                }
                .clipShape(RoundedRectangle(cornerRadius: receded ? 22 : 0, style: .continuous))
                // Behind the search sheet the page shrinks into a card whose top sits just below
                // the status bar, rather than tucking under it.
                .scaleEffect(receded ? 0.9 : 1, anchor: .top)
                .offset(y: receded ? 6 : 0)
                // Same spring as the search sheet, so the corners round in step with it rising.
                // Same curve both ways, so growing back mirrors shrinking.
                .animation(LuneTheme.pageSpring, value: receded)
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

    /// How far the search sheet starts below its resting spot: just enough that its field sits
    /// on the bar's + pill, so the pill stays put and grows into the field instead of the whole
    /// sheet sliding in from off screen.
    private var searchTravel: CGFloat {
        let screen = KeyboardMetrics.windowHeight
        let pill = browser.plusButtonFrame
        guard pill.height > 0 else { return screen }
        let rest = browser.searchFieldRestMidY ?? CommandOverlay.restingFieldMidY(screenHeight: screen)
        return max(0, pill.midY - rest)
    }

    private var dimOpacity: Double {
        switch browser.overlay {
        case .command: 0.25
        case .menu: 0.3
        default: 0
        }
    }

    private var searchOwnsBar: Bool {
        browser.overlay == .command || browser.commandCollapsing
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
