import Foundation
import UIKit
import SwiftData
import WebKit

@MainActor
@Observable
final class BrowserModel {
    enum Overlay {
        case none
        case command
        case menu
        case findPage
        case overview
        case settings
    }

    var tabs: [Tab] = []
    var selectedID: Tab.ID?
    var overlay: Overlay = .none
    var findPageSeed: String?
    var commandOpensNewTab = false
    /// True while the tab deck is spread out; false while a card is zoomed to fill the page.
    var deckSpread = false
    /// Global frame of the tab-stack button; deck cards fly into and out of it.
    var tabButtonFrame: CGRect = .zero
    var engine: SearchEngine

    private var context: ModelContext?

    init() {
        engine = SearchEngine(rawValue: UserDefaults.standard.string(forKey: "searchEngine") ?? "")
            ?? .duckDuckGo
    }

    var selectedTab: Tab? {
        guard let selectedID else { return nil }
        return tabs.first { $0.id == selectedID }
    }

    var selectedIndex: Int {
        guard let selectedID else { return 0 }
        return tabs.firstIndex { $0.id == selectedID } ?? 0
    }

    func setEngine(_ newEngine: SearchEngine) {
        engine = newEngine
        UserDefaults.standard.set(newEngine.rawValue, forKey: "searchEngine")
    }

    // MARK: - Lifecycle

    func boot(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context

        let descriptor = FetchDescriptor<TabRecord>(sortBy: [SortDescriptor(\.order)])
        let records = ((try? context.fetch(descriptor)) ?? []).filter { record in
            guard let url = URL(string: record.urlString) else { return false }
            return url.scheme == "http" || url.scheme == "https"
        }
        diagnostic("boot restoring \(records.count) tabs")
        var selected: Tab?
        for record in records {
            let tab = makeTab()
            tab.title = record.title
            if let data = record.snapshot {
                tab.snapshot = UIImage(data: data)
            }
            tab.url = URL(string: record.urlString)
            tabs.append(tab)
            if record.selected { selected = tab }
        }
        if let first = selected ?? tabs.last {
            selectedID = first.id
            first.ensureLoaded()
        }
    }

    private var persistTask: Task<Void, Never>?

    func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    func persist() {
        guard let context else { return }
        try? context.delete(model: TabRecord.self)
        for (index, tab) in tabs.enumerated() where !tab.showsStartPage {
            let record = TabRecord(
                urlString: tab.url?.absoluteString ?? "",
                title: tab.title,
                order: index,
                selected: tab.id == selectedID,
                snapshot: tab.snapshotJPEG
            )
            context.insert(record)
        }
        try? context.save()
    }

    #if DEBUG
    func applyLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        diagnostic("arguments \(arguments)")
        if let index = arguments.firstIndex(of: "-luneURL"), index + 1 < arguments.count,
           let url = URL(string: arguments[index + 1]) {
            selectedTab?.load(url)
        }
        if let index = arguments.firstIndex(of: "-luneOverlay"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "start": selectedID = nil
            case "command": beginSearch(newTab: true)
            case "menu": overlay = .menu
            case "find":
                overlay = .none
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    overlay = .findPage
                }
            case "overview":
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    openOverview()
                }
            case "settings": overlay = .settings
            default: overlay = .none
            }
        }
        if let index = arguments.firstIndex(of: "-luneFind"), index + 1 < arguments.count {
            findPageSeed = arguments[index + 1]
            overlay = .findPage
        }
    }
    #endif

    // MARK: - Tab management

    @discardableResult
    private func makeTab() -> Tab {
        let tab = Tab()
        tab.onVisit = { [weak self] url, title in
            self?.recordVisit(url, title: title)
        }
        tab.onSnapshot = { [weak self] in
            self?.schedulePersist()
        }
        return tab
    }

    @discardableResult
    func newTab(url: URL? = nil) -> Tab {
        let tab = makeTab()
        if let url { tab.url = url }
        tabs.append(tab)
        selectedID = tab.id
        if let url { tab.load(url) }
        persist()
        return tab
    }

    func selectTab(_ id: Tab.ID) {
        if id != selectedID {
            selectedTab?.captureSnapshot()
        }
        selectedID = id
        selectedTab?.ensureLoaded()
        persist()
    }

    func close(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let wasSelected = tab.id == selectedID
        tabs.remove(at: index)

        if tabs.isEmpty {
            selectedID = nil
        } else if wasSelected {
            let next = tabs[min(index, tabs.count - 1)]
            selectedID = next.id
            next.ensureLoaded()
        }
        persist()
    }

    func closeOthers(_ tab: Tab) {
        tabs = [tab]
        selectedID = tab.id
        tab.ensureLoaded()
        persist()
    }

    func step(by offset: Int) {
        guard !tabs.isEmpty else { return }
        let index = (selectedIndex + offset + tabs.count) % tabs.count
        selectTab(tabs[index].id)
    }

    func scrollToNewest() {
        tabs.last.map { selectTab($0.id) }
    }

    // MARK: - Navigation

    func destination(for incoming: URL) -> URL? {
        if let components = URLComponents(url: incoming, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
           let url = URL(string: value), url.scheme == "http" || url.scheme == "https" {
            return url
        }
        if let host = incoming.host, !host.isEmpty {
            let scheme = host.hasPrefix("localhost") ? "http" : "https"
            return URL(string: "\(scheme)://\(host)")
        }
        return nil
    }


    func openInput(_ text: String) {
        guard let url = AddressParser.destination(for: text, engine: engine) else { return }
        openURL(url)
    }

    func openURL(_ url: URL) {
        if commandOpensNewTab || selectedTab == nil {
            newTab(url: url)
        } else if let current = selectedTab {
            current.load(url)
        } else {
            newTab(url: url)
        }
        commandOpensNewTab = false
        overlay = .none
        persist()
    }

    func openOverview() {
        guard overlay == .none, !tabs.isEmpty else { return }
        deckSpread = false
        if let index = tabs.firstIndex(where: { $0.id == selectedID }), index != tabs.count - 1 {
            tabs.append(tabs.remove(at: index))
            schedulePersist()
        }
        guard let tab = selectedTab else {
            overlay = .overview
            return
        }
        tab.captureSnapshot { [weak self] in
            self?.overlay = .overview
        }
    }

    func beginSearch(newTab: Bool) {
        commandOpensNewTab = newTab
        overlay = .command
    }

    // MARK: - History and favorites

    private func recordVisit(_ url: URL, title: String) {
        guard let context, url.scheme == "http" || url.scheme == "https" else { return }
        let key = url.absoluteString
        let predicate = #Predicate<HistoryEntry> { $0.urlString == key }
        var descriptor = FetchDescriptor<HistoryEntry>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.visitedAt = .now
            if !title.isEmpty { existing.title = title }
        } else {
            context.insert(HistoryEntry(urlString: key, title: title))
        }
        try? context.save()
    }

    func historyMatches(_ text: String, limit: Int = 6) -> [HistoryEntry] {
        guard let context else { return [] }
        var descriptor = FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
        descriptor.fetchLimit = 200
        guard let all = try? context.fetch(descriptor) else { return [] }
        if text.isEmpty { return Array(all.prefix(limit)) }
        let query = text.lowercased()
        return Array(all.filter {
            $0.urlString.lowercased().contains(query) || $0.title.lowercased().contains(query)
        }.prefix(limit))
    }

    func isFavorite(_ url: URL) -> Bool {
        guard let context else { return false }
        let key = url.absoluteString
        let predicate = #Predicate<Favorite> { $0.urlString == key }
        var descriptor = FetchDescriptor<Favorite>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    func deleteHistory(_ entry: HistoryEntry) {
        guard let context else { return }
        context.delete(entry)
        try? context.save()
    }

    func removeFavorite(_ url: URL) {
        guard let context else { return }
        let key = url.absoluteString
        let predicate = #Predicate<Favorite> { $0.urlString == key }
        let descriptor = FetchDescriptor<Favorite>(predicate: predicate)
        if let matches = try? context.fetch(descriptor) {
            for match in matches { context.delete(match) }
        }
        try? context.save()
    }

    func addFavorite(_ url: URL, title: String) {
        guard let context else { return }
        if isFavorite(url) { return }
        context.insert(Favorite(urlString: url.absoluteString, title: title))
        try? context.save()
    }

    func clearHistory() {
        context?.deleteAll(of: HistoryEntry.self)
    }

    func clearWebsiteData() async {
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }

    func clearWebsiteData(for url: URL) async {
        guard let rawHost = url.host()?.lowercased() else { return }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let matching = records.filter {
            let name = $0.displayName.lowercased()
            return name == host || name.hasSuffix("." + host)
        }
        await store.removeData(ofTypes: types, for: matching)
    }
}

private extension ModelContext {
    func deleteAll<T: PersistentModel>(of type: T.Type) {
        try? delete(model: type)
        try? save()
    }
}
