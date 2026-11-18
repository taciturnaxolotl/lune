import SwiftData
import SwiftUI

struct CommandOverlay: View {
    @Bindable var browser: BrowserModel
    /// How far down the sheet sits when its field lines up with the bar's + pill.
    let collapsedOffset: CGFloat
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]

    @State private var text = ""
    @State private var suggestions: [String] = []
    @State private var historyHits: [HistoryEntry] = []
    @State private var fetchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    /// False for the first instant so the field can grow out of the bar's + pill.
    @State private var morphed = false
    /// The + glyph clears out faster than the pill stretches, as in Arc.
    @State private var plusGone = false
    /// The ghost tab stack and chevron fade well ahead of the morph, so they're mostly gone by the
    /// time the stretching field reaches them.
    @State private var ghostShown = true
    @State private var fieldWidth: CGFloat = 370
    /// Closing: the sheet drops back onto the bar instead of using a removal transition, so it can
    /// keep morphing on the way down.
    @State private var dropOffset: CGFloat = 0
    @State private var listFaded = false
    /// The field's live position, kept in a plain reference so updating it never re-renders.
    /// Writing it to view or model state every frame re-laid the sheet mid-animation and split
    /// the field's text from its capsule. Handed to the model once the open settles.
    @State private var fieldMidY = Box<CGFloat>(0)
    private let keyboard = KeyboardMetrics.shared

    private var query: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.allowsHitTesting(false)
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    // As the bar, the top edge sits where the real bar's does (32pt above the
                    // pill's centre); as the sheet, it relaxes to 12pt above the field.
                    .padding(.top, morphed ? 12 : 8)
                    .padding(.bottom, 6)

                List {
                    if query.isEmpty && browser.commandPrivate {
                        Text("You're browsing Incognito")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, minHeight: listHeight - 8)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else if query.isEmpty {
                        emptyRows
                    } else {
                        queryRows
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 56)
                .contentMargins(.bottom, 8, for: .scrollContent)
                .scrollDismissesKeyboard(.never)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: listHeight)
                .animation(.snappy(duration: 0.2), value: listHeight)
                .opacity(listFaded ? 0 : 1)
            }
            // Pinned to the sheet's top edge exactly as the real bar's controls are (10pt down,
            // 44pt tall), so they ride with the top instead of drifting with the field.
            .overlay(alignment: .top) {
                ghostBar.padding(.top, 10)
            }
            // Sit where the keyboard will end up rather than riding it, so the sheet can arrive
            // first and the keyboard rises underneath.
            .padding(.bottom, max(0, keyboard.height - KeyboardMetrics.windowSafeBottom))
            .background {
                let corner: CGFloat = morphed ? 40 : 0
                UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner, style: .continuous)
                            .fill(Color(red: 0.16, green: 0.15, blue: 0.16).opacity(0.82))
                    }
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner, style: .continuous)
                            .fill(Color(red: 0.06, green: 0.06, blue: 0.07).opacity(browser.commandPrivate ? 0.94 : 0))
                    }
                    .animation(.easeOut(duration: 0.3), value: browser.commandPrivate)
                    .overlay {
                        // Unmorphed, the sheet wears the bar's own colours, so it reads as the bar.
                        UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Tab.chromeTop, browser.selectedTab?.chromeBottom ?? Tab.neutralChromeBottom],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .opacity(morphed ? 0 : 1)
                    }
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner, style: .continuous)
                            .stroke(.white.opacity(morphed ? 0.08 : 0.1), lineWidth: 0.6)
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
            .offset(y: dropOffset)
        }
        .ignoresSafeArea(.keyboard)
        .environment(\.colorScheme, .dark)
        .onAppear {
            // Focus at once: bringing up the keyboard stalls the main thread for a frame or two,
            // and that stall is invisible while the sheet is just leaving but a visible hitch
            // mid-flight. The keyboard's own start-up latency still gives the sheet its lead.
            isFocused = true
            withAnimation(.easeOut(duration: 0.08)) { plusGone = true }
            withAnimation(.easeOut(duration: 0.1)) { ghostShown = false }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-luneFreezeMorph") { return }
            #endif
            withAnimation(.spring(duration: 0.26, bounce: 0)) { morphed = true }
            withAnimation(LuneTheme.sheetSpring) {
                browser.searchSheetShown = true
            } completion: {
                if browser.overlay == .command { browser.searchFieldRestMidY = fieldMidY.value }
            }
        }
        .onChange(of: browser.commandCollapsing) { _, collapsing in
            guard collapsing else { return }
            collapse()
        }
        .onChange(of: browser.overlay) { _, overlay in
            // Reopened mid-collapse: run the open again from wherever the sheet is.
            guard overlay == .command else { return }
            browser.commandCollapsing = false
            browser.searchSheetShown = true
            isFocused = true
            withAnimation(.easeOut(duration: 0.08)) { plusGone = true; listFaded = false }
            withAnimation(.easeOut(duration: 0.1)) { ghostShown = false }
            withAnimation(.spring(duration: 0.26, bounce: 0)) { morphed = true }
            withAnimation(LuneTheme.sheetSpring) { dropOffset = 0 }
        }
        .task {
            if !browser.commandOpensNewTab, let url = browser.selectedTab?.url, url.scheme != "about" {
                text = url.absoluteString
            }
            historyHits = browser.historyMatches("", limit: 5)
        }
        .onChange(of: text) { _, newValue in
            fetchTask?.cancel()
            historyHits = browser.historyMatches(newValue, limit: 4)
            guard newValue.count >= 2, !newValue.contains("://") else {
                suggestions = []
                return
            }
            let pending = newValue
            fetchTask = Task {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                let result = await Suggestions.fetch(for: pending)
                guard !Task.isCancelled else { return }
                suggestions = Array(result.prefix(4))
            }
        }
        .onDisappear { fetchTask?.cancel() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            TextField("", text: $text, prompt: Text("Search…").foregroundStyle(.white.opacity(0.45)))
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .tint(Color(.systemBlue))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .focused($isFocused)
                .onSubmit(openText)
            trailingControl
        }
        .padding(.leading, 24)
        .padding(.trailing, 4)
        .frame(height: 48)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fieldWidth = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: { fieldMidY.value = $0 }
        .background {
            // Starts as the bar's 76pt + pill and stretches sideways into the field, like Arc.
            let inset = morphed ? 0 : max(0, (fieldWidth - 76) / 2)
            Capsule()
                .fill(.white.opacity(browser.commandPrivate ? 0.07 : 0.1))
                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.6))
                .padding(.horizontal, inset)
                .padding(.vertical, morphed ? 0 : 4)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .opacity(plusGone ? 0 : 1)
                }
        }
        .animation(.easeOut(duration: 0.25), value: browser.commandPrivate)
    }

    /// Arc closes by turning the sheet back into the bar: it takes on the bar's colours, the rows
    /// fade, the field shrinks to the + pill as the tab icon and chevron return, and the whole
    /// thing settles onto the real bar, which then takes over without a seam.
    private func collapse() {
        withAnimation(.easeOut(duration: 0.12)) { listFaded = true }
        withAnimation(.easeOut(duration: 0.14)) { morphed = false }
        withAnimation(.easeIn(duration: 0.1).delay(0.1)) { plusGone = false; ghostShown = true }
        withAnimation(LuneTheme.sheetCloseSpring) {
            dropOffset = collapsedOffset
        } completion: {
            var handOff = Transaction()
            handOff.disablesAnimations = true
            withTransaction(handOff) { browser.commandCollapsing = false }
        }
    }

    /// The bar's tab stack and chevron, standing in either side of the field while it is still
    /// the + pill, so the top of the sheet reads as the bar itself.
    private var ghostBar: some View {
        HStack(spacing: 0) {
            TabStackIcon(snapshot: browser.selectedTab?.snapshot)
                .offset(x: 7)
                .frame(width: 56, height: 44)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 0.6))
                .frame(width: 56, height: 44)
        }
        .padding(.horizontal, 12)
        // Flatten first so the fading tab cards stay stacked instead of showing through each other.
        .compositingGroup()
        .opacity(ghostShown ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// One fixed 44pt slot: the eyes while the field is empty, the clear button while typing.
    private var trailingControl: some View {
        ZStack {
            if text.isEmpty {
                privateToggle
                    // Rides the field's trailing edge as it stretches out from the pill, so the
                    // eyes slide in from the side rather than appearing in place.
                    .offset(x: morphed ? 0 : -max(0, (fieldWidth - 76) / 2) + 10)
                    .opacity(morphed ? 1 : 0)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Clear")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: 44, height: 44)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: text.isEmpty)
    }

    /// Arc's incognito control. The eyes never move; "Incognito" slides out leftward from behind
    /// them, clipped at their edge, and takes no layout space so nothing else shifts either.
    private var privateToggle: some View {
        Button {
            Haptics.play(.privacy)
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                browser.commandPrivate.toggle()
            }
        } label: {
            PrivacyEye(closed: browser.commandPrivate, size: 24)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.86, haptic: nil))
        .accessibilityLabel(browser.commandPrivate ? "Deactivate Incognito" : "Activate Incognito")
        .background(alignment: .trailing) {
            // The label rests just left of the eyes and starts tucked fully behind them.
            let shown = browser.commandPrivate && text.isEmpty
            Text("Incognito")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize()
                .offset(x: shown ? 0 : 80)
                .opacity(shown ? 1 : 0)
                .padding(.trailing, 44)
                .frame(width: 160, alignment: .trailing)
                .mask(alignment: .trailing) {
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 10)
                        Color.clear.frame(width: 38)
                    }
                }
                .allowsHitTesting(false)
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: shown)
        }
    }

    @ViewBuilder
    private var emptyRows: some View {
        ForEach(favorites.prefix(4)) { favorite in
            ResultRow(
                title: favorite.title.isEmpty ? favorite.urlString : favorite.title,
                icon: .site(favorite.urlString),
                pinned: true
            ) { open(favorite.urlString) }
            .contextMenu {
                linkActions(favorite.urlString, title: favorite.title)
                Divider()
                Button {
                    if let url = URL(string: favorite.urlString) {
                        withAnimation { browser.removeFavorite(url) }
                    }
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
            } preview: {
                LinkPreview(title: favorite.title, urlString: favorite.urlString)
            }
            .swipeActions(edge: .trailing) {
                Button {
                    if let url = URL(string: favorite.urlString) {
                        withAnimation { browser.removeFavorite(url) }
                    }
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
                .tint(.orange)
            }
        }
        let pinned = Set(favorites.map(\.urlString))
        historyRows(historyHits.filter { !pinned.contains($0.urlString) })
    }

    @ViewBuilder
    private var queryRows: some View {
        ResultRow(
            title: looksLikeURL ? query : "Search “\(query)”",
            icon: .system(looksLikeURL ? "globe" : "magnifyingglass")
        ) { openText() }

        ForEach(suggestions.filter { $0.lowercased() != query.lowercased() }, id: \.self) { suggestion in
            ResultRow(title: suggestion, icon: .system("magnifyingglass")) {
                browser.openInput(suggestion)
                dismiss()
            }
        }

        historyRows(historyHits)
    }

    private func historyRows(_ entries: [HistoryEntry]) -> some View {
        ForEach(entries) { entry in
            ResultRow(
                title: entry.title.isEmpty ? entry.urlString : entry.title,
                icon: .site(entry.urlString),
                pinned: favorites.contains { $0.urlString == entry.urlString }
            ) { open(entry.urlString) }
            .contextMenu {
                linkActions(entry.urlString, title: entry.title)
                if let url = URL(string: entry.urlString), !browser.isFavorite(url) {
                    Button {
                        browser.addFavorite(url, title: entry.title.isEmpty ? entry.urlString : entry.title)
                    } label: {
                        Label("Pin", systemImage: "pin.fill")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    delete(entry)
                } label: {
                    Label("Delete from History", systemImage: "trash")
                }
            } preview: {
                LinkPreview(title: entry.title, urlString: entry.urlString)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    delete(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func linkActions(_ urlString: String, title: String) -> some View {
        if let url = URL(string: urlString) {
            Button {
                browser.newTab(url: url)
                dismiss()
            } label: {
                Label("Open in New Tab", systemImage: "plus.square.on.square")
            }
            Button {
                UIPasteboard.general.url = url
            } label: {
                Label("Copy Link", systemImage: "link")
            }
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func delete(_ entry: HistoryEntry) {
        Haptics.tap()
        withAnimation(.snappy) {
            historyHits.removeAll { $0.persistentModelID == entry.persistentModelID }
        }
        browser.deleteHistory(entry)
    }

    /// A constant four rows, so typing, results arriving, and toggling Incognito never move the
    /// sheet. Extra results scroll.
    private var listHeight: CGFloat { Self.listHeight }
    static let listHeight: CGFloat = 4 * 56 + 8

    /// Where the field's centre rests on screen, worked out from the layout rather than measured,
    /// so the open transition can start the field exactly on the bar's + pill.
    static func restingFieldMidY(screenHeight: CGFloat) -> CGFloat {
        screenHeight - KeyboardMetrics.shared.height - listHeight - 6 - 24
    }

    private var looksLikeURL: Bool {
        !query.contains(" ") && (query.contains(".") || query.contains("://"))
    }

    private func openText() {
        if !query.isEmpty {
            browser.openInput(query)
        }
        dismiss()
    }

    private func open(_ string: String) {
        if let url = URL(string: string) {
            browser.openURL(url)
        }
        dismiss()
    }

    private func dismiss() {
        isFocused = false
        browser.commandOpensNewTab = false
        browser.overlay = .none
    }
}

private struct ResultRow: View {
    enum Icon {
        case site(String)
        case system(String)
    }

    let title: String
    let icon: Icon
    var pinned = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.row)
            action()
        } label: {
            HStack(spacing: 12) {
                switch icon {
                case .site(let urlString):
                    SiteIcon(urlString: urlString, size: 20)
                case .system(let name):
                    Image(systemName: name)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 20, height: 20)
                }
                Text(title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 33)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.listRow)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// The card shown above a long-pressed result.
private struct LinkPreview: View {
    let title: String
    let urlString: String

    var body: some View {
        HStack(spacing: 12) {
            SiteIcon(urlString: urlString, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? urlString : title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                Text(urlString)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}

