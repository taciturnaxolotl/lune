import UIKit
import SwiftUI

@MainActor
final class FaviconLoader {
    static let shared = FaviconLoader()
    private let cache = NSCache<NSString, UIImage>()

    func image(for domain: String) async -> UIImage? {
        if let image = cache.object(forKey: domain as NSString) {
            return image
        }
        guard !domain.isEmpty,
              let imageURL = URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico")
        else { return nil }

        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = UIImage(data: data),
              image.size.width > 1,
              image.cgImage != nil
        else { return nil }

        cache.setObject(image, forKey: domain as NSString)
        return image
    }
}

struct SiteIcon: View {
    let urlString: String
    var size: CGFloat = 32

    @State private var image: UIImage?
    @State private var attempted = false

    private var domain: String {
        guard let host = URL(string: urlString)?.host() else {
            return urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else {
                DomainAvatar(domain: domain, size: size)
            }
        }
        .frame(width: size, height: size)
        .opacity(attempted || image != nil ? 1 : 0.92)
        .task(id: domain) {
            attempted = false
            image = await FaviconLoader.shared.image(for: domain)
            attempted = true
        }
    }
}
