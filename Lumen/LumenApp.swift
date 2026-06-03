//
//  LumenApp.swift
//  Lumen
//
//  App entry point. Wires the VaultManager into the environment and adds the
//  vault File-menu commands (P1.4).
//

import LumenCore
import SwiftUI

@main
struct LumenApp: App {
    /// The app-wide vault state. Reopens the last vault on launch.
    @State private var vaultManager = VaultManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(vaultManager)
        }
        .commands {
            VaultCommands(manager: vaultManager)
        }
    }
}
