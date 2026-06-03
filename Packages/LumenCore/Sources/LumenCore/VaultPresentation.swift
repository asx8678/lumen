//
//  VaultPresentation.swift
//  LumenCore
//
//  Pure, UI-agnostic presentation helpers for vault state. Kept here (rather
//  than in the app target) so the logic is unit-testable; the app target has no
//  test target and otherwise relies on the build.
//

import Foundation

/// Derives user-facing strings and command-enablement from vault state.
public enum VaultPresentation {
    /// The main window title for the given vault (or its absence).
    /// - Parameter vault: The open vault, or `nil`.
    /// - Returns: e.g. `"Lumen — Notes"` or `"Lumen — No Vault"`.
    public static func windowTitle(for vault: Vault?) -> String {
        if let vault {
            return "Lumen — \(vault.name)"
        }
        return "Lumen — No Vault"
    }

    /// Whether vault-scoped file commands (New Note / New Folder / Close Vault)
    /// should be enabled.
    /// - Parameter vault: The open vault, or `nil`.
    /// - Returns: `true` only when a vault is open.
    public static func canActOnVault(_ vault: Vault?) -> Bool {
        vault != nil
    }
}
