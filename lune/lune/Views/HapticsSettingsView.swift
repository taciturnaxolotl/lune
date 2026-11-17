import SwiftUI

/// Lets Kieran tune every haptic by feel. Changes save immediately and play as you adjust them.
struct HapticsSettingsView: View {
    @State private var tuning = HapticTuning.shared

    var body: some View {
        List {
            Section {
                Text("Pick a style and strength for each kind of feedback. Each change plays as you make it, and the Test buttons replay it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(HapticRole.allCases) { role in
                Section {
                    RoleEditor(role: role, tuning: tuning)
                } header: {
                    Text(role.title)
                } footer: {
                    Text(role.detail)
                }
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    tuning.reset()
                    Haptics.select()
                }
            }
        }
        .navigationTitle("Haptics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RoleEditor: View {
    let role: HapticRole
    let tuning: HapticTuning

    private var setting: Binding<HapticSetting> {
        Binding(
            get: { tuning.setting(for: role) },
            set: { tuning.update(role, $0) }
        )
    }

    var body: some View {
        Picker("Style", selection: setting.style) {
            ForEach(HapticStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .onChange(of: setting.wrappedValue.style) {
            tuning.play(role)
        }

        if setting.wrappedValue.style.takesIntensity {
            HStack {
                Text("Strength")
                Slider(value: setting.intensity, in: 0.05...1, step: 0.05) { editing in
                    if !editing { tuning.play(role) }
                }
                Text("\(Int((setting.wrappedValue.intensity * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }

        Button("Test") {
            tuning.play(role)
        }
        .disabled(setting.wrappedValue.style == .off)
    }
}
