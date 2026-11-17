import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @Query private var history: [HistoryEntry]
    @Query private var favorites: [Favorite]

    var body: some View {
        NavigationStack {
            List {
                Section("Search") {
                    Picker("Search Engine", selection: Binding(
                        get: { browser.engine },
                        set: { browser.setEngine($0) }
                    )) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                }

                Section("Feel") {
                    NavigationLink {
                        HapticsSettingsView()
                    } label: {
                        Label("Haptics", systemImage: "hand.tap")
                    }
                }

                Section("Browsing Data") {
                    LabeledContent("History", value: "\(history.count) pages")
                    LabeledContent("Favorites", value: "\(favorites.count)")

                    Button("Clear History", role: .destructive) {
                        browser.clearHistory()
                    }

                    Button("Clear Cache and Cookies", role: .destructive) {
                        Task {
                            await browser.clearWebsiteData()
                        }
                    }
                }

                Section("About") {
                    HStack(spacing: 14) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lune")
                                .font(.headline)
                            Text("A lightweight, native browser.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)

                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        LabeledContent("Version", value: version)
                    }
                    Link("Kieran Klukas", destination: URL(string: "https://dunkirk.sh")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
