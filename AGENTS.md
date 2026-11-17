# AGENTS.md

Documentation for AI agents working on lune.

---

## Project Overview

**Lune** is a lightweight, Arc-mobile-inspired iOS browser. Built with SwiftUI, WKWebView, and SwiftData. iOS 26 deployment target, Swift 6 with MainActor default isolation. No third-party dependencies.

**Philosophy**: native feel first. Spring animations, haptics, materials. One command bar at the bottom that expands into search with suggestions and history. Tabs as snapshot cards. Small codebase, fast builds, no ceremony.

---

## Project Structure

```
lune/
└── lune.xcodeproj            # Single app target, filesystem-synchronized groups (objectVersion 77)
    └── lune/
        ├── App/
        │   └── LuneApp.swift        # @main, modelContainer for TabRecord/HistoryEntry/Favorite
        ├── Browser/
        │   ├── Tab.swift            # One tab = one WKWebView. KVO publishers for url/title/loading.
        │   │                        # WebViewFactory shared config. WKNavigationDelegate.
        │   ├── BrowserModel.swift   # @Observable. Tab list, selection, overlay state, persistence,
        │   │                        # history, favorites, engine, website-data clearing.
        │   └── AddressParser.swift  # SearchEngine enum, typed-input -> URL or search,
        │                            # DuckDuckGo autocomplete fetch.
        ├── Storage/
        │   └── Models.swift         # SwiftData: TabRecord, HistoryEntry, Favorite
        └── Views/
            ├── BrowserView.swift    # Root ZStack: one selected BrowserPage, chrome, overlays.
            ├── WebViewHost.swift    # BrowserPage observes tab state; WebKit-backed view controller and find.
            ├── AddressBar.swift     # Bottom controls: tab thumbnail, plus, page actions. Swipe switches tabs.
            ├── CommandOverlay.swift # Arc-style dark search: favorites, history, autocomplete suggestions.
            ├── PageMenu.swift       # Page actions, zoom, desktop/user agent, share, site data.
            ├── TabOverview.swift    # Horizontally paged snapshot cards in dark gradient.
            ├── StartPageView.swift  # Blank tab: centered moon, gradient, optional favorites.
            ├── SettingsView.swift   # Engine picker, history/cache clearing, about.
            ├── Shared.swift         # LuneTheme, DarkBackdrop, DomainAvatar, Haptics, CardProgress.
            └── FaviconLoader.swift  # Browser/FaviconLoader.swift: cached DuckDuckGo icons + fallback avatars.
        └── Resources/
            ├── Assets.xcassets      # AccentColor #F2C04A, Logo (gold glyph PNG from lune-glass.svg)
            └── lune.icon            # Icon Composer: icon.json + Assets/lune-glass.svg
```

---

## Identity

- Bundle identifier: `sh.dunkirk.lune`
- Display name: `Lune`
- Accent: gold `#F2C04A` (logo gold)
- Dark background for the app icon: `#262626`
- Logo source SVGs: `~/Downloads/lune-{light,dark,glass}.svg` on Kieran's machine. `lune-glass.svg` is the glyph without background.

---

## Architecture notes

### Tabs and web views

Each `Tab` owns its `WKWebView` for its lifetime (page state survives tab switches). Only the selected tab mounts `BrowserPage`, which observes `@Published` tab state directly to avoid leaving the start page visible while a site loads. A blank `WKWebView` loads during tab creation to warm the renderer; restored tabs remain lazy until selected.

Find-in-page uses a themed SwiftUI overlay. WebKit JavaScript counts text nodes and invokes `window.find` to scroll to matches; do not confuse this with `WKWebView.findInteraction`, whose system overlay behaved unreliably in SwiftUI testing. See `FindInPageOverlay.swift` (currently under `Views`).

### Overlays

`BrowserModel.overlay` is a single enum: `.none`, `.command` (full-screen dark search), `.menu` (page detail sheet), `.overview` (fullScreenCover tab carousel), `.settings` (sheet).

### Persistence

SwiftData models are saved from `BrowserModel.persist()` (tab list replaced on each save, tiny n). Called on tab changes, navigation commits (via `Tab.onVisit` closure), and scenePhase background. History entries are unique on URL; revisits bump `visitedAt`.

### Performance decisions

- Default WKWebsiteDataStore (cookies/cache persist across launches)
- No shared process pool: WKProcessPool is deprecated on iOS 15+, WebKit handles it.
- Tab snapshots captured on deselect, navigation finish, overview open, and backgrounding. Persistence never forces synchronous screenshots.
- DuckDuckGo autocomplete has a 2s timeout and 200ms debounce; history matches are computed synchronously from a 200-entry fetch.

---

## Build and Test

```sh
# Build for the simulator (no signing needed)
xcodebuild -project lune/lune.xcodeproj -scheme lune \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Device (uses Kieran's team, M67B42LX8D)
xcodebuild -project lune/lune.xcodeproj -scheme lune \
  -destination 'platform=iOS,name=<device>' build
```

There is no test target yet. Manual verification: launch in simulator, type in the command bar, add/switch/close tabs, check favorites and history survive relaunch.

### Deep links and headless verification

The app handles `lune://` URLs: `lune://example.com` opens a host, and `lune://open?url=https%3A%2F%2Fexample.com` opens an encoded URL.

For simulator checks, the Debug build supports `-luneURL https://example.com`, `-luneOverlay start`, and `-luneOverlay command|menu|find|overview|settings` as launch arguments. Launch with `--terminate-running-process` so they apply on relaunch. These are compiled out of Release builds.

## Conventions

- MainActor by default (build setting `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Keep types isolation-consistent; WKWebView delegate code lives directly on `Tab`.
- Avoid new dependencies. Prefer system APIs (SwiftUI materials, UIWindow feedback generators, SwiftData).
- Haptics on every primary interaction (tap = light impact, tab switch = selection).
- Match ennote's project conventions: filesystem-synchronized groups in pbxproj, Icon Composer `.icon` folder instead of a classic AppIcon set.

### Matching Arc Search on device

Arc Search (`company.thebrowser.ArcMobile2`) is installed on Briony, so UI can be compared against the real app. Launch either app and screenshot it with:

```sh
xcrun devicectl device process launch --device <udid> --terminate-existing [--payload-url https://lobste.rs] <bundle-id>
xcrun devicectl device capture screenshot --device <udid> --destination /tmp/shot.png
```

Screenshots are 1206x2622 at 3x. Pass Lune launch arguments after `--` (for example `-- -luneURL https://lobste.rs -luneOverlay menu`). devicectl cannot tap, so only launch states are capturable.

Measured Arc metrics: bottom bar 76pt tall including the home indicator, with content centred 44pt above the screen bottom; plus pill 76x40; chevron circle 34; both filled at 12% white with a hairline stroke. The bar is a neutral dark gradient that warms toward the site's theme colour near the bottom. The search sheet has 40pt top corners, a 47pt capsule field, and 56pt rows with 17pt text and 21pt favicons.

### Headless UI probe (preferred for exploring Arc or Lune)

`LuneProbe` is a UI-test target whose runner executes on the phone, so it can tap, swipe and screenshot any installed app (including Arc Search) without touching the Mac's mouse. Do not use iPhone Mirroring with synthetic mouse events; it takes over Kieran's cursor and locks the phone.

```sh
tools/probe.sh build      # once, and after changing LuneProbe or Lune
tools/probe.sh run 'launch company.thebrowser.ArcMobile2; wait 2; shot home; tree home; tap 0.5 0.95; wait 1; shot sheet'
```

Commands are documented at the top of `lune/LuneProbe/LuneProbe.swift`. Coordinates are fractions of the screen. Output goes to `/tmp/lune-probe/<HHMMSS>/` as numbered PNG screenshots and `.txt` accessibility trees. `tree` gives exact element frames in points, which is the best source for matching Arc's metrics. A run takes about 20 seconds. The phone must be unlocked.

### Arc reference geometry (from probe trees, 402x874pt screen)

- Bottom bar: plus 76x40 at (163, 810); chevron circle 34 at (344, 813); tab icon at x 24.
- Tab switcher deck: focused card 281x569 at x 84, y 166, with its title 18pt above. Cards behind it scale by `1 - 0.02*d^2` and their centres sit `110*(1 - 0.33^d)` left of the focused card's centre. The next card starts at x 308. Lune implements this in `Deck` (TabOverview.swift) with a drag-driven `position`, not a ScrollView, because ScrollView snapping fought the deck maths.
- Search sheet: 370x48 field at x 16, placeholder text at x 40, 56pt rows with text at x 48. The page behind scales to 0.95, tucks just under the status bar, and sits over the gradient backdrop.
- Page menu: 48pt address strip, 16pt gap, 80pt tiles 16.6pt apart (label below, 103pt total), 48pt list rows with labels at x 68, and a separate group 16pt below.

### Chrome behaviour (matched to Arc)

- The bottom bar never hides. Arc keeps it fixed through fast flicks, so the page ends at the bar's top edge instead of sliding under it.
- The status-bar strip uses the page's `theme-color`, falling back to `underPageBackgroundColor` (WebKit's sampled page background). Lune no longer overrides `underPageBackgroundColor`, because overriding it hides the page colour.
- Load progress is a 2pt hairline on the bar's top edge, not a coloured line under the status bar.
- Buttons use `.pressable` (squish plus a soft haptic on touch-down). List rows use `.row` (highlight plus haptic). Do not call `Haptics.tap()` inside a button action, or the haptic fires twice.
- The tab deck is an in-place overlay, matched to a 30fps screen recording of Arc. Tabs are reordered most-recent-last when the deck opens, so the current tab sits in the right-hand peek slot and the previous tab gets focus. On open, the current card shrinks from `pageFrame` into the peek slot while the others grow out of `browser.tabButtonFrame`. Tapping a card expands it in place to `pageFrame` (about 0.28s spring) as the rest collapse into the tab button.
- The loading line is system blue, 2.5pt, on the top edge of the bottom bar.
- To sample an animation with the probe, issue several `shot` commands with no `wait` between them; each one lands about 100ms apart.
