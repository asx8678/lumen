//
//  LumenApp.swift
//  Lumen
//
//  App entry point + composition root wiring (P1.2).
//
//  - A single main `Window` (multi-window/split is Phase 3).
//  - One `AppEnvironment` constructed once and injected via `.environment`.
//  - A structured menu-bar `Commands` tree (file/vault, sidebar, settings).
//  - `ScenePhase` lifecycle: release the vault's security-scoped access on exit.
//

import LumenCore
import LumenDesignSystem
import SwiftUI

@main
struct LumenApp: App {
    /// The composition root: built once, injected everywhere. Reopens the last
    /// vault on launch via `VaultManager` (P1.4).
    @State private var env = AppEnvironment()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        // One window for now; `Window` (not `WindowGroup`) prevents duplicate
        // windows and gives automatic frame autosave/restoration keyed by id.
        Window(VaultPresentation.windowTitle(for: env.vault.current), id: "main") {
            ContentView()
                .environment(env)
                .environment(env.theme)
                .frame(minWidth: 720, minHeight: 460)
                .navigationTitle(VaultPresentation.windowTitle(for: env.vault.current))
                .tint(env.theme.theme.accentColor)
                .preferredColorScheme(env.theme.preferredColorScheme)
        }
        .defaultSize(width: 1_100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            VaultCommands(env: env)
            SidebarCommands()  // adds View ▸ Toggle Sidebar (⌃⌘S)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // Balance VaultManager's security-scoped access on the way out.
                env.vault.releaseAccessForTermination()
            }
        }

        // ⌘, Settings scene — stub only; full UI is P1.19.
        Settings {
            SettingsView()
                .environment(env.theme)
                .tint(env.theme.theme.accentColor)
                .preferredColorScheme(env.theme.preferredColorScheme)
        }
    }
}
