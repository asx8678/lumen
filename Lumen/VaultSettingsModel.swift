//
//  VaultSettingsModel.swift
//  Lumen
//
//  App-level observable wrapper around the per-vault `VaultConfig` (P1.19).
//  Loads `.lumen/config.json` on vault open and persists on change. Per-vault
//  preferences (currently the default new-note location) live here; app-global
//  ergonomics (theme P1.17, typography P1.13) stay in UserDefaults.
//

import Foundation
import LumenCore
import Observation
import os

/// Observable per-vault preferences, backed by `.lumen/config.json`.
@MainActor
@Observable
public final class VaultSettingsModel {
    /// The current vault's config. Mutations persist to `.lumen/config.json`.
    public private(set) var config: VaultConfig = .default

    @ObservationIgnored private var vaultRoot: URL?
    @ObservationIgnored private let logger = Logger(
        subsystem: "ai.Lumen", category: "VaultSettings")

    public init() {}

    /// Loads the config for a newly-opened vault (or resets when closed).
    public func load(vaultRoot: URL?) {
        self.vaultRoot = vaultRoot
        if let vaultRoot {
            config = VaultConfigStore.load(vaultRoot: vaultRoot)
        } else {
            config = .default
        }
    }

    /// The default new-note directory for the current vault (root unless a
    /// per-vault location is configured).
    public func defaultNoteDirectory() -> URL? {
        guard let vaultRoot else { return nil }
        return config.defaultNoteDirectory(vaultRoot: vaultRoot)
    }

    /// Updates the default new-note location (relative path; `nil` = root) and
    /// persists. Writing to `.lumen/` does not disturb indexing/FSEvents — the
    /// directory is hidden and excluded from enumeration + the indexer.
    public func setDefaultNoteLocation(_ relativePath: String?) {
        let normalized = relativePath?.trimmingCharacters(in: .whitespaces)
        config.defaultNoteLocation = (normalized?.isEmpty ?? true) ? nil : normalized
        persist()
    }

    private func persist() {
        guard let vaultRoot else { return }
        do {
            try VaultConfigStore.save(config, vaultRoot: vaultRoot)
        } catch {
            logger.error("Save config failed: \(String(describing: error), privacy: .public)")
        }
    }
}
