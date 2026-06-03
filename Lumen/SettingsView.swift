//
//  SettingsView.swift
//  Lumen
//
//  Settings scene STUB (P1.2). The full preferences UI — appearance, editor
//  typography, per-vault settings — is P1.19. This exists only so the standard
//  ⌘, Settings scene is present and wired.
//

import SwiftUI

/// Placeholder Settings content. Replaced by the real preferences UI in P1.19.
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Settings")
                .font(.headline)
            Text("Preferences arrive in a later update.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 420, height: 220)
    }
}

#Preview {
    SettingsView()
}
