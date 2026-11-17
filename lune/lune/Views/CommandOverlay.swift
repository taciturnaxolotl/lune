import SwiftData
import SwiftUI

struct CommandOverlay: View {
    @Bindable var browser: BrowserModel
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]

    @State private var text = ""
    @State private var suggestions: [String] = []
    @State private var historyHits: [HistoryEntry] = []
    @State private var fetchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private var query: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                List {
                    if query.isEmpty {
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
                .frame(height: min(CGFloat(rowCount) * 56 + 8, 290))
                .animation(.snappy(duration: 0.2), value: rowCount)
            }
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40, style: .continuous)
                            .fill(Color(red: 0.16, green: 0.15, blue: 0.16).opacity(0.82))
                    }
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 0.6)
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            if !browser.commandOpensNewTab, let url = browser.selectedTab?.url, url.scheme != "about" {
                text = url.absoluteString
            }
            isFocused = true
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
                .tint(LuneTheme.gold)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .focused($isFocused)
                .onSubmit(openText)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 14)
        .frame(height: 48)
        .background(.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.6))
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
                        Label("Pin", systemImage: "pin")
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

    private var rowCount: Int {
        if query.isEmpty {
            let pinned = Set(favorites.map(\.urlString))
            return min(favorites.count, 4) + historyHits.filter { !pinned.contains($0.urlString) }.count
        }
        let extra = suggestions.filter { $0.lowercased() != query.lowercased() }.count
        return 1 + extra + historyHits.count
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
                    Image(systemName: "pin")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 33)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
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
