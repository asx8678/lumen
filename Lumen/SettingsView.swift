//
//  SettingsView.swift
//  Lumen
//
//  Settings scene with a MINIMAL appearance/accent picker (P1.17) so theme
//  switching can be exercised. The full preferences UI — editor typography,
//  per-vault settings — is P1.19.
//

import LumenDesignSystem
import SwiftUI

/// Minimal theme settings. Replaced/expanded by the real preferences UI (P1.19).
struct SettingsView: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        @Bindable var theme = theme
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme.appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Accent", selection: $theme.accent) {
                    ForEach(AccentColor.allCases) { accent in
                        Text(accent.label).tag(accent)
                    }
                }
            }

            Section {
                Text("More preferences arrive in a later update.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 240)
    }
}

#Preview {
    SettingsView()
        .environment(ThemeManager())
}
