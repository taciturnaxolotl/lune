import SwiftUI
import UIKit

enum Haptics {
    /// Finger lands on a control.
    static func press() { play(.button) }

    /// A discrete commit: closing a tab, deleting.
    static func tap() { play(.commit) }

    /// Stepping through values or snapping between tabs.
    static func select() { play(.tick) }

    static func play(_ role: HapticRole) {
        HapticTuning.shared.play(role)
    }
}

/// Every place Lune buzzes. Each role is tuned independently in Settings > Haptics.
enum HapticRole: String, CaseIterable, Identifiable {
    case button, newTab, row, commit, tick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .button: "Buttons"
        case .newTab: "New Tab"
        case .row: "List Rows"
        case .commit: "Close and Delete"
        case .tick: "Ticks"
        }
    }

    var detail: String {
        switch self {
        case .button: "Bar, menu and deck buttons on touch-down"
        case .newTab: "The plus button"
        case .row: "Search results and history rows"
        case .commit: "Closing a tab, deleting history"
        case .tick: "Snapping between tabs, zoom steps, pinning"
        }
    }

    var defaultSetting: HapticSetting {
        switch self {
        case .button: HapticSetting(style: .soft, intensity: 0.75)
        case .newTab: HapticSetting(style: .soft, intensity: 0.35)
        case .row: HapticSetting(style: .soft, intensity: 0.75)
        case .commit: HapticSetting(style: .rigid, intensity: 0.6)
        case .tick: HapticSetting(style: .selection, intensity: 1)
        }
    }
}

enum HapticStyle: String, CaseIterable, Identifiable {
    case off, selection, soft, light, medium, rigid, heavy

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var takesIntensity: Bool { self != .off && self != .selection }

    var impactStyle: UIImpactFeedbackGenerator.FeedbackStyle? {
        switch self {
        case .soft: .soft
        case .light: .light
        case .medium: .medium
        case .rigid: .rigid
        case .heavy: .heavy
        case .off, .selection: nil
        }
    }
}

struct HapticSetting: Equatable {
    var style: HapticStyle
    var intensity: Double
}

@MainActor
@Observable
final class HapticTuning {
    static let shared = HapticTuning()

    private(set) var settings: [HapticRole: HapticSetting] = [:]
    private var impacts: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        let defaults = UserDefaults.standard
        for role in HapticRole.allCases {
            let fallback = role.defaultSetting
            let style = defaults.string(forKey: "haptic.\(role.rawValue).style").flatMap(HapticStyle.init) ?? fallback.style
            let intensity = defaults.object(forKey: "haptic.\(role.rawValue).intensity") as? Double ?? fallback.intensity
            settings[role] = HapticSetting(style: style, intensity: intensity)
        }
        selection.prepare()
    }

    func setting(for role: HapticRole) -> HapticSetting {
        settings[role] ?? role.defaultSetting
    }

    func update(_ role: HapticRole, _ setting: HapticSetting) {
        settings[role] = setting
        UserDefaults.standard.set(setting.style.rawValue, forKey: "haptic.\(role.rawValue).style")
        UserDefaults.standard.set(setting.intensity, forKey: "haptic.\(role.rawValue).intensity")
    }

    func reset() {
        for role in HapticRole.allCases { update(role, role.defaultSetting) }
    }

    func play(_ role: HapticRole) {
        play(setting(for: role))
    }

    func play(_ setting: HapticSetting) {
        if setting.style == .selection {
            selection.selectionChanged()
            selection.prepare()
            return
        }
        guard let style = setting.style.impactStyle else { return }
        let generator = impacts[style] ?? {
            let made = UIImpactFeedbackGenerator(style: style)
            impacts[style] = made
            return made
        }()
        generator.impactOccurred(intensity: setting.intensity)
        generator.prepare()
    }
}

/// Buttons squish and tick the moment a finger lands, like Arc's.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.9
    var haptic: HapticRole = .button

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.play(haptic) }
            }
    }
}

/// List rows highlight instead of shrinking.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0))
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.25), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.play(.row) }
            }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    static func pressable(scale: CGFloat = 0.9, haptic: HapticRole = .button) -> PressableButtonStyle {
        PressableButtonStyle(scale: scale, haptic: haptic)
    }
}

extension ButtonStyle where Self == RowButtonStyle {
    static var row: RowButtonStyle { RowButtonStyle() }
}

enum LuneTheme {
    static let gold = Color(red: 0.949, green: 0.753, blue: 0.290)
    static let panel = Color(red: 0.158, green: 0.148, blue: 0.172)
    static let input = Color(red: 0.204, green: 0.189, blue: 0.219)
    static let tile = Color(red: 0.243, green: 0.227, blue: 0.258)
    static let divider = Color.white.opacity(0.12)

    static let backdrop = LinearGradient(
        colors: [
            Color(red: 0.024, green: 0.031, blue: 0.067),
            Color(red: 0.094, green: 0.078, blue: 0.113),
            Color(red: 0.196, green: 0.157, blue: 0.145),
        ],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )
}

struct DarkBackdrop: View {
    var body: some View {
        ZStack {
            LuneTheme.backdrop.ignoresSafeArea()
            RadialGradient(
                colors: [LuneTheme.gold.opacity(0.08), .clear],
                center: .bottom,
                startRadius: 20,
                endRadius: 460
            )
            .ignoresSafeArea()
        }
    }
}

struct DomainAvatar: View {
    let domain: String
    var size: CGFloat = 30

    var color: Color {
        var hash: UInt64 = 5381
        for byte in domain.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.62, brightness: 0.78)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.gradient)
            Text(domain.prefix(1).uppercased())
                .font(.system(size: size * 0.54, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}


extension Tab {
    static let chromeTop = Color(red: 0.180, green: 0.157, blue: 0.157)
    static let neutralChromeBottom = Color(red: 0.165, green: 0.153, blue: 0.176)

    var chromeBottom: Color {
        guard let themeColor else { return Tab.neutralChromeBottom }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        themeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let mix = 0.12
        return Color(
            red: red * mix + 0.20 * (1 - mix),
            green: green * mix + 0.16 * (1 - mix),
            blue: blue * mix + 0.165 * (1 - mix)
        )
    }
}
