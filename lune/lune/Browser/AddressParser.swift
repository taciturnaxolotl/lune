import Foundation

enum SearchEngine: String, CaseIterable, Identifiable {
    case duckDuckGo
    case google
    case bing
    case brave

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .brave: "Brave"
        }
    }

    func searchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        switch self {
        case .duckDuckGo:
            components.host = "duckduckgo.com"
            components.path = "/"
        case .google:
            components.host = "www.google.com"
            components.path = "/search"
        case .bing:
            components.host = "www.bing.com"
            components.path = "/search"
        case .brave:
            components.host = "search.brave.com"
            components.path = "/search"
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

enum AddressParser {
    static func destination(for input: String, engine: SearchEngine) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host != nil {
            return url
        }

        if !text.contains(" ") && !text.contains("://") {
            let lower = text.lowercased()
            if lower.hasPrefix("localhost") || lower.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) {
                return URL(string: "http://\(text)")
            }
            if lower.contains(".") && !lower.contains(":") {
                return URL(string: "https://\(text)")
            }
        }

        return engine.searchURL(query: text)
    }
}

enum Suggestions {
    static func fetch(for query: String) async -> [String] {
        var components = URLComponents(string: "https://duckduckgo.com/ac/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "list"),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let lists = try? JSONDecoder().decode([[String]].self, from: data) {
                return Array(lists.flatMap { $0 }.prefix(6))
            }
            if let phrases = try? JSONDecoder().decode([Phrase].self, from: data) {
                return Array(phrases.map(\.phrase).prefix(6))
            }
            return []
        } catch {
            return []
        }
    }

    private struct Phrase: Decodable {
        let phrase: String
    }
}
