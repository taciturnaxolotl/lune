import SwiftData
import SwiftUI
import WebKit

struct PageMenu: View {
    @Bindable var browser: BrowserModel

    @State private var zoom = 1.0
    @State private var wantsDesktop = false
    @State private var isPinned = false
    @State private var confirmsClear = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            if let tab = browser.selectedTab {
                VStack(spacing: 16) {
                    NavigationLine(browser: browser, tab: tab)

                    HStack(alignment: .top, spacing: 16.6) {
                        ActionTile(icon: "doc.text.magnifyingglass", label: "Find on Page") {
                            browser.overlay = .findPage
                        }
                        ActionTile(icon: isPinned ? "pin.fill" : "pin", label: isPinned ? "Pinned" : "Pin") {
                            guard let url = tab.webView.url else { return }
                            if isPinned {
                                browser.removeFavorite(url)
                            } else {
                                browser.addFavorite(url, title: tab.displayTitle)
                            }
                            Haptics.select()
                            isPinned.toggle()
                        }
                        ActionTile(icon: wantsDesktop ? "desktopcomputer" : "iphone", label: wantsDesktop ? "Desktop" : "Mobile") {
                            wantsDesktop.toggle()
                        }
                        if let url = tab.webView.url {
                            ShareLink(item: url) {
                                TileContent(icon: "square.and.arrow.up", label: "Share")
                            }
                            .buttonStyle(.pressable)
                        }
                    }

                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Image(systemName: "textformat.size")
                                .frame(width: 26)
                                .padding(.trailing, 8)
                            Text("Page Zoom")
                            Spacer()
                            HStack(spacing: 0) {
                                ZoomStep(symbol: "minus", enabled: zoom > 0.51) {
                                    adjustZoom(by: -0.1, tab: tab)
                                }
                                Rectangle()
                                    .fill(.white.opacity(0.14))
                                    .frame(width: 0.6, height: 18)
                                ZoomStep(symbol: "plus", enabled: zoom < 2.99) {
                                    adjustZoom(by: 0.1, tab: tab)
                                }
                            }
                            .background(.white.opacity(0.08), in: Capsule())
                            .overlay(alignment: .leading) {
                                Text("\(Int((zoom * 100).rounded()))%")
                                    .font(.system(size: 14, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.6))
                                    .contentTransition(.numericText(value: zoom))
                                    .fixedSize()
                                    .offset(x: -52)
                            }
                        }
                        .padding(.leading, 18)
                        .padding(.trailing, 4)
                        .frame(height: 48)

                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    MenuRow(icon: "trash", title: "Clear Site Data") {
                        confirmsClear = true
                    }
                    .font(.system(size: 16))
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 44, topTrailingRadius: 44, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            UnevenRoundedRectangle(topLeadingRadius: 44, topTrailingRadius: 44, style: .continuous)
                                .fill(Color(red: 0.16, green: 0.15, blue: 0.16).opacity(0.82))
                        }
                        .overlay {
                            UnevenRoundedRectangle(topLeadingRadius: 44, topTrailingRadius: 44, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 0.6)
                        }
                        .padding(.horizontal, 4)
                        .ignoresSafeArea(edges: .bottom)
                }
                .environment(\.colorScheme, .dark)
                .onChange(of: wantsDesktop) { _, enabled in
                    let mode: WKWebpagePreferences.ContentMode = enabled ? .desktop : .mobile
                    guard tab.webView.configuration.defaultWebpagePreferences.preferredContentMode != mode else { return }
                    tab.webView.configuration.defaultWebpagePreferences.preferredContentMode = mode
                    tab.webView.reload()
                }

                .onAppear {
                    zoom = tab.webView.pageZoom
                    wantsDesktop = tab.webView.configuration.defaultWebpagePreferences.preferredContentMode == .desktop
                    if let url = tab.webView.url {
                        isPinned = browser.isFavorite(url)
                    }
                }
                .confirmationDialog("Clear cookies and storage for \(tab.domain)?", isPresented: $confirmsClear, titleVisibility: .visible) {
                    Button("Clear Data", role: .destructive) {
                        if let url = tab.webView.url {
                            Task { await browser.clearWebsiteData(for: url) }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }

    private func adjustZoom(by delta: Double, tab: Tab) {
        let next = min(3, max(0.5, ((zoom + delta) * 10).rounded() / 10))
        guard next != zoom else { return }
        Haptics.select()
        withAnimation(.snappy) { zoom = next }
        tab.webView.pageZoom = next
    }

    private func dismiss() {
        browser.overlay = .none
    }
}

private struct NavigationLine: View {
    let browser: BrowserModel
    @ObservedObject var tab: Tab

    var body: some View {
        HStack(spacing: 2) {
            iconButton("chevron.backward", enabled: tab.canGoBack) {
                tab.webView.goBack()
            }
            iconButton("chevron.forward", enabled: tab.canGoForward) {
                tab.webView.goForward()
            }

            Button {
                browser.beginSearch(newTab: false)
            } label: {
                Text(tab.domain)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            iconButton("link", enabled: tab.webView.url != nil) {
                if let url = tab.webView.url {
                    UIPasteboard.general.url = url
                    Haptics.select()
                }
            }
            iconButton("arrow.clockwise", enabled: true) {
                tab.webView.reload()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.6))
    }

    private func iconButton(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            browser.overlay = .none
        } label: {
            Image(systemName: name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.85 : 0.25))
                .frame(width: 38, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }
}

private struct TileContent: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 80)
        .contentShape(Rectangle())
    }
}

private struct ActionTile: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TileContent(icon: icon, label: label)
        }
        .buttonStyle(.pressable)
    }
}

private struct MenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: icon)
                    .frame(width: 26)
                    .padding(.trailing, 8)
                Text(title)
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
    }
}

/// Half of the zoom stepper. The whole 56x40 half is tappable, not just the glyph.
private struct ZoomStep: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
                .frame(width: 56, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.85))
        .disabled(!enabled)
        .buttonRepeatBehavior(.enabled)
    }
}
