import SwiftUI

/// Arc-style tab deck, matched frame by frame to a screen recording of Arc Search.
///
/// Tabs are ordered most-recent-last, so the current tab is the right-hand peeking card and the
/// deck focuses the tab before it. Opening: the live page shrinks into that peek slot while the
/// other cards grow out of the tab-stack button. Choosing a card expands it in place to fill the
/// page; everything else collapses back into the button underneath it.
struct TabOverview: View {
    @Bindable var browser: BrowserModel
    /// The page area in global coordinates; the zoomed-in hero card fills exactly this.
    let pageFrame: CGRect

    @State private var position: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var heroID: Tab.ID?

    private static let openSpring = Animation.spring(response: 0.36, dampingFraction: 0.88)
    private static let closeSpring = Animation.spring(response: 0.28, dampingFraction: 0.94)

    var body: some View {
        GeometryReader { geometry in
            let layout = DeckLayout(size: geometry.size)
            let spread = browser.deckSpread
            let heroIndex = browser.tabs.firstIndex { $0.id == heroID } ?? (browser.tabs.count - 1)
            let button = buttonRect

            ZStack(alignment: .topLeading) {
                DarkBackdrop()

                ForEach(Array(browser.tabs.enumerated()), id: \.element.id) { index, tab in
                    let deckRect = layout.rect(index: index, position: position)
                    let isHero = index == heroIndex
                    let rect = spread ? deckRect : (isHero ? pageFrame : button)
                    let radius: CGFloat = spread ? 36 * deckRect.width / layout.cardWidth : (isHero ? 0 : 6)
                    TabCard(
                        tab: tab,
                        rect: rect,
                        cornerRadius: radius,
                        chromeOpacity: spread ? layout.labelOpacity(index: index, position: position) : 0,
                        referenceWidth: layout.cardWidth,
                        open: { open(tab) },
                        close: { close(tab) }
                    )
                    .opacity(spread || isHero ? 1 : 0)
                    .zIndex(isHero && !spread ? 500 : Double(index))
                }

                controls
                    .opacity(spread ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .zIndex(1000)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(scrub(step: layout.step))
            .allowsHitTesting(spread)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear {
            heroID = browser.selectedID
            position = CGFloat(max(0, browser.tabs.count - 2))
            withAnimation(Self.openSpring) {
                browser.deckSpread = true
            }
        }
    }

    /// The tab-stack button, as a card-shaped rect for cards to shrink into.
    private var buttonRect: CGRect {
        let frame = browser.tabButtonFrame
        guard frame.width > 0 else {
            return CGRect(x: 30, y: pageFrame.maxY + 14, width: 27, height: 30)
        }
        return CGRect(x: frame.midX - 6, y: frame.midY - 18, width: 27, height: 30)
    }

    private var controls: some View {
        HStack {
            Color.clear.frame(width: 56, height: 44)
            Spacer()
            Button {
                browser.deckSpread = false
                browser.overlay = .none
                browser.beginSearch(newTab: true)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 40)
                    .background(.white.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.6))
            }
            .buttonStyle(.pressable(haptic: .newTab))
            .accessibilityLabel("New tab")
            Spacer()
            Button {
                browser.deckSpread = false
                browser.overlay = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 0.6))
                    .frame(width: 56, height: 44)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 22)
    }

    private func open(_ tab: Tab) {
        heroID = tab.id
        browser.selectTab(tab.id)
        withAnimation(Self.closeSpring) {
            browser.deckSpread = false
        } completion: {
            browser.overlay = .none
        }
    }

    private func close(_ tab: Tab) {
        Haptics.tap()
        let wasLast = browser.tabs.count == 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            browser.close(tab)
            position = min(position, CGFloat(max(0, browser.tabs.count - 1)))
        }
        if wasLast {
            withAnimation(.easeOut(duration: 0.25)) {
                browser.deckSpread = false
            } completion: {
                browser.overlay = .none
            }
        }
    }

    private func scrub(step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) || dragStart != nil else { return }
                if dragStart == nil { dragStart = position }
                let raw = (dragStart ?? position) - value.translation.width / step
                let last = CGFloat(max(0, browser.tabs.count - 1))
                position = raw < 0 ? raw / 3 : (raw > last ? last + (raw - last) / 3 : raw)
            }
            .onEnded { value in
                guard let start = dragStart else { return }
                dragStart = nil
                let projected = start - value.predictedEndTranslation.width / step
                let last = CGFloat(max(0, browser.tabs.count - 1))
                let target = min(last, max(0, projected.rounded()))
                if target != position.rounded() { Haptics.select() }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    position = target
                }
            }
    }
}

/// Geometry measured from Arc Search on a 402x874pt screen, scaled to the current size.
private struct DeckLayout {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardTop: CGFloat
    let anchor: CGFloat
    let step: CGFloat
    let pile: CGFloat

    init(size: CGSize) {
        cardWidth = (size.width * 0.70).rounded()
        cardHeight = (size.height * 0.651).rounded()
        cardTop = (size.height * 0.19).rounded()
        anchor = (size.width * 0.209).rounded()
        step = cardWidth - (cardWidth * 0.203).rounded()
        pile = size.width * 0.274
    }

    private func depth(index: Int, position: CGFloat) -> CGFloat {
        let natural = anchor + (CGFloat(index) - position) * step
        return max(0, (anchor - natural) / step)
    }

    func rect(index: Int, position: CGFloat) -> CGRect {
        let natural = anchor + (CGFloat(index) - position) * step
        let depth = max(0, (anchor - natural) / step)
        let scale = max(0.6, 1 - 0.02 * depth * depth)
        let shift = step * depth - pile * (1 - pow(0.33, depth))
        let width = cardWidth * scale
        let height = cardHeight * scale
        let centerX = natural + shift + cardWidth / 2
        let centerY = cardTop + cardHeight / 2
        return CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
    }

    func labelOpacity(index: Int, position: CGFloat) -> CGFloat {
        max(0, 1 - depth(index: index, position: position) * 1.5)
    }
}

private struct TabCard: View {
    @ObservedObject var tab: Tab
    let rect: CGRect
    let cornerRadius: CGFloat
    let chromeOpacity: CGFloat
    let referenceWidth: CGFloat
    let open: () -> Void
    let close: () -> Void

    @State private var dragY: CGFloat = 0
    @State private var isClosing = false

    /// Header height above the card at full deck size.
    private static let headerHeight: CGFloat = 34

    var body: some View {
        // The header is laid out at deck size and scaled with the card, so it shrinks, grows and
        // travels exactly as the card does instead of snapping to its final spot.
        let scale = rect.width / referenceWidth
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SiteIcon(urlString: tab.url?.absoluteString ?? "", size: 22)
                Text(tab.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(width: referenceWidth - 12, height: 22, alignment: .leading)
            .padding(.leading, 12)
            .padding(.bottom, Self.headerHeight - 22)
            .scaleEffect(scale, anchor: .bottomLeading)
            .frame(width: rect.width, height: Self.headerHeight * scale, alignment: .bottomLeading)
            .opacity(chromeOpacity)
            .opacity(1 - min(1, -dragY / 140))

            preview
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.08 * chromeOpacity), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.5 * chromeOpacity), radius: 20, x: -8, y: 0)
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
                .simultaneousGesture(swipeToClose)
        }
        .frame(width: rect.width, height: rect.height + Self.headerHeight * scale, alignment: .topLeading)
        .position(x: rect.midX, y: rect.midY - Self.headerHeight * scale / 2 + min(0, dragY))
        .opacity(isClosing ? 0 : 1 - min(0.6, -dragY / 500))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityAddTraits(.isButton)
    }

    private var swipeToClose: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard dragY != 0 || abs(value.translation.height) > abs(value.translation.width) * 1.5 else { return }
                dragY = value.translation.height < 0 ? value.translation.height : value.translation.height * 0.15
            }
            .onEnded { value in
                let flung = value.predictedEndTranslation.height < -260
                if dragY < -130 || (dragY < -40 && flung) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragY = -rect.height * 1.4
                        isClosing = true
                    } completion: {
                        close()
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragY = 0
                    }
                }
            }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = tab.snapshot, !tab.showsStartPage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                .clipped()
                .background(tab.stripColor)
        } else {
            ZStack {
                if tab.showsStartPage {
                    DarkBackdrop()
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(176, rect.width * 0.4), height: min(176, rect.width * 0.4))
                } else {
                    LuneTheme.panel
                    SiteIcon(urlString: tab.url?.absoluteString ?? "", size: 44)
                }
            }
        }
    }
}
