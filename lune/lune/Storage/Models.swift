import Foundation
import SwiftData

@Model
final class TabRecord {
    var urlString: String
    var title: String
    var order: Int
    var selected: Bool
    @Attribute(.externalStorage) var snapshot: Data?

    init(urlString: String, title: String, order: Int, selected: Bool, snapshot: Data? = nil) {
        self.urlString = urlString
        self.title = title
        self.order = order
        self.selected = selected
        self.snapshot = snapshot
    }
}

@Model
final class HistoryEntry {
    @Attribute(.unique) var urlString: String
    var title: String
    var visitedAt: Date

    init(urlString: String, title: String, visitedAt: Date = .now) {
        self.urlString = urlString
        self.title = title
        self.visitedAt = visitedAt
    }
}

@Model
final class Favorite {
    @Attribute(.unique) var urlString: String
    var title: String
    var addedAt: Date

    init(urlString: String, title: String, addedAt: Date = .now) {
        self.urlString = urlString
        self.title = title
        self.addedAt = addedAt
    }
}
