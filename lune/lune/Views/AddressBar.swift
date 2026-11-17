import SwiftUI
import WebKit

struct AddressBar: View {
    @Bindable var browser: BrowserModel

    var body: some View {
        if let tab = browser.selectedTab {
            BarContent(browser: browser, tab: tab)
                .id(tab.id)
        } else {
            BarContent(browser: browser, tab: nil)
        }
    }
}

private struct BarContent: View {
    let browser: BrowserModel
    let tab: Tab?

    var body: some View {
        if let tab {
            ObservedBar(browser: browser, tab: tab)
        } else {
            BarLayout(browser: browser, tab: nil)
        }
    }
}

private struct ObservedBar: View {
    let browser: BrowserModel
    @ObservedObject var tab: Tab

    var body: some View {
        BarLayout(browser: browser, tab: tab)
    }
}

private struct BarLayout: View {
    let browser: BrowserModel
    let tab: Tab?

    private var onStart: Bool { tab == nil }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                browser.openOverview()
            } label: {
                TabStackIcon(snapshot: tab?.snapshot)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        browser.tabButtonFrame = frame
                    }
                    .offset(x: 7)
                    .frame(width: 56, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .opacity(browser.tabs.isEmpty ? 0 : 1)
            .disabled(browser.tabs.isEmpty)
            .accessibilityLabel("\(browser.tabs.count) tabs")

            Spacer(minLength: 0)

            Button {
                browser.beginSearch(newTab: true)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 40)
                    .background(.white.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.6))
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable(haptic: .newTab))
            .accessibilityLabel("New tab")

            Spacer(minLength: 0)

            Button {
                browser.overlay = onStart ? .settings : .menu
            } label: {
                Image(systemName: onStart ? "gearshape" : "chevron.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 0.6))
                    .frame(width: 56, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Page actions")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, -12)
        .background {
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Tab.chromeTop, tab?.chromeBottom ?? Tab.neutralChromeBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
            .animation(.easeOut(duration: 0.3), value: tab?.themeColor)
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if abs(value.translation.width) > abs(value.translation.height),
                       abs(value.translation.width) > 50 {
                        Haptics.select()
                        browser.step(by: value.translation.width < 0 ? 1 : -1)
                    }
                }
        )
        .environment(\.colorScheme, .dark)
    }
}

private struct TabStackIcon: View {
    let snapshot: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(white: 0.85))
                .frame(width: 27, height: 30)
                .rotationEffect(.degrees(-18))
                .offset(x: -7, y: 5)

            Group {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(white: 0.13)
                }
            }
            .frame(width: 27, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.6)
            }
            .rotationEffect(.degrees(8))
            .offset(x: 7, y: -5)
            .shadow(color: .black.opacity(0.35), radius: 2, x: -1, y: 1)
        }
    }
}
