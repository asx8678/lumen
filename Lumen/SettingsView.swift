//
//  SettingsView.swift
//  Lumen
//
//  The Settings scene (P1.19): a tabbed preferences window surfacing the
//  existing models — appearance/accent (P1.17 ThemeManager), editor typography
//  (P1.13 EditorTypography), and the per-vault default new-note location
//  (P1.19 VaultConfig / .lumen/config.json).
//
//  Layering: appearance + typography are app-global (UserDefaults — they travel
//  with the user across vaults); the default new-note location is per-vault.
//

import LumenCore
import LumenDesignSystem
import LumenEditor
import SwiftUI

/// Tabbed app preferences.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            EditorSettings()
                .tabItem { Label("Editor", systemImage: "textformat") }
            VaultSettings()
                .tabItem { Label("Vault", systemImage: "folder") }
        }
        .frame(width: 460, height: 320)
    }
}

// MARK: - Appearance (app-global, P1.17)

private struct AppearanceSettings: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        @Bindable var theme = theme
        Form {
            Picker("Theme", selection: $theme.appearance) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Accent", selection: $theme.accent) {
                ForEach(AccentColor.allCases) { Text($0.label).tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Editor typography (app-global, P1.13)

private struct EditorSettings: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let store = env.editorTypography
        let t = store.typography
        let mode = env.editorMode
        Form {
            Picker(
                "Default editing mode",
                selection: Binding(
                    get: { mode.defaultEditingMode },
                    set: { mode.defaultEditingMode = $0 })
            ) {
                Text("Source").tag(EditorViewMode.source)
                Text("Live Preview").tag(EditorViewMode.livePreview)
            }
            .pickerStyle(.segmented)
            Text("The mode new tabs open in.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "Font",
                selection: Binding(
                    get: { t.fontKind },
                    set: { store.typography.fontKind = $0 })
            ) {
                Text("Monospace").tag(EditorTypography.FontKind.monospace)
                Text("Proportional").tag(EditorTypography.FontKind.proportional)
            }
            .pickerStyle(.segmented)

            Stepper(
                value: Binding(
                    get: { t.fontSize },
                    set: { store.typography.fontSize = EditorTypography.clampSize($0) }),
                in: EditorTypography.minFontSize...EditorTypography.maxFontSize,
                step: 1
            ) {
                Text("Font Size: \(Int(t.fontSize)) pt")
            }

            Picker(
                "Line Width",
                selection: Binding(
                    get: { t.lineWidth },
                    set: { store.typography.lineWidth = $0 })
            ) {
                ForEach(EditorTypography.LineWidth.allCases, id: \.self) { width in
                    Text(width.rawValue.capitalized).tag(width)
                }
            }

            Slider(
                value: Binding(
                    get: { t.lineSpacing },
                    set: { store.typography.lineSpacing = EditorTypography.clampSpacing($0) }),
                in: EditorTypography.minLineSpacing...EditorTypography.maxLineSpacing,
                step: 0.1
            ) {
                Text("Line Spacing")
            }
            Text(String(format: "Line spacing: %.1f x", t.lineSpacing))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Vault (per-vault, P1.19)

private struct VaultSettings: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let settings = env.vaultSettings
        Form {
            if env.vault.current != nil {
                Picker(
                    "New notes go to",
                    selection: Binding(
                        get: { settings.config.defaultNoteLocation ?? "" },
                        set: { settings.setDefaultNoteLocation($0.isEmpty ? nil : $0) })
                ) {
                    Text("Vault Root").tag("")
                    ForEach(folderChoices, id: \.self) { relative in
                        Text(relative).tag(relative)
                    }
                }
                Text("Stored per-vault in .lumen/config.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open a vault to edit its preferences.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Relative paths of folders in the current vault (for the location picker).
    private var folderChoices: [String] {
        guard let root = env.vault.current?.root else { return [] }
        var out: [String] = []
        collect(env.fileTree.items, root: root, into: &out)
        return out.sorted()
    }

    private func collect(_ items: [VaultItem], root: URL, into out: inout [String]) {
        for item in items where item.isDirectory {
            if let relative = TabSupport.relativePath(of: item.url, root: root) {
                out.append(relative)
            }
            collect(item.children, root: root, into: &out)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment(vault: VaultManager(reopenLast: false)))
        .environment(ThemeManager())
}
