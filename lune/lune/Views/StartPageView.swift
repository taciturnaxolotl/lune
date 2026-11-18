import SwiftData
import SwiftUI

struct StartPageView: View {
    @Bindable var browser: BrowserModel
    @Query(sort: \Favorite.addedAt) private var favorites: [Favorite]

    var body: some View {
        ZStack(alignment: .bottom) {
            DarkBackdrop()

            VStack(spacing: 26) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 176, height: 176)
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 8)

                HStack(spacing: 7) {
                    PrivacyEye(closed: true, size: 16)
                    Text("Incognito")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(LuneTheme.violet)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(LuneTheme.violet.opacity(0.14), in: Capsule())
                .opacity(browser.isPrivate ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.bottom, 90)

            if !favorites.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(favorites.prefix(8)) { favorite in
                            Button {
                                if let url = URL(string: favorite.urlString) {
                                    browser.openURL(url)
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    SiteIcon(urlString: favorite.urlString, size: 42)
                                    Text(favorite.title.isEmpty ? favorite.urlString : favorite.title)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                                .frame(width: 62)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 76)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
