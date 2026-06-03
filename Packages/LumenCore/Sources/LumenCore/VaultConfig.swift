//
//  VaultConfig.swift
//  LumenCore
//
//  Per-vault PREFERENCES, persisted as human-readable JSON at
//  `<vaultRoot>/.lumen/config.json` (P1.19).
//
//  Source-of-truth principle: this file holds only preferences/caches — never
//  note content. Deleting `.lumen/` must lose only prefs + the index cache, so
//  loading a missing/corrupt config silently falls back to defaults.
//
//  Layering: app-global ergonomics (theme, editor typography) live in
//  UserDefaults and travel with the user across every vault. Genuinely
//  vault-specific choices live here — at present the default new-note location,
//  which only makes sense relative to a particular vault's folder structure.
//

import Foundation

/// Per-vault preferences stored in `.lumen/config.json`.
public struct VaultConfig: Codable, Sendable, Equatable {
    /// Where `New Note` creates files when nothing is selected, as a path
    /// relative to the vault root. `nil` or empty means the vault root itself.
    public var defaultNoteLocation: String?

    public init(defaultNoteLocation: String? = nil) {
        self.defaultNoteLocation = defaultNoteLocation
    }

    /// The default configuration (new notes go to the vault root).
    public static let `default` = VaultConfig()

    /// Resolves the directory where a new note should be created when there is
    /// no sidebar selection: the configured location, or the vault root.
    public func defaultNoteDirectory(vaultRoot: URL) -> URL {
        guard let relative = defaultNoteLocation,
            !relative.trimmingCharacters(in: .whitespaces).isEmpty
        else { return vaultRoot }
        return vaultRoot.appendingPathComponent(relative, isDirectory: true)
    }
}

/// Loads and saves ``VaultConfig`` under a vault's `.lumen/` directory.
public enum VaultConfigStore {
    /// The per-vault cache/prefs directory name (shared with the index).
    public static let directoryName = ".lumen"
    /// The config file name.
    public static let fileName = "config.json"

    /// The on-disk location of the config for `vaultRoot`.
    public static func configURL(forVaultRoot vaultRoot: URL) -> URL {
        vaultRoot
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Loads the config for `vaultRoot`, returning ``VaultConfig/default`` when
    /// the file is missing or unreadable (never throws — prefs are best-effort).
    public static func load(vaultRoot: URL) -> VaultConfig {
        let url = configURL(forVaultRoot: vaultRoot)
        guard let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(VaultConfig.self, from: data)
        else { return .default }
        return config
    }

    /// Writes the config as pretty-printed, key-sorted JSON, creating `.lumen/`
    /// if needed.
    public static func save(_ config: VaultConfig, vaultRoot: URL) throws {
        let directory = vaultRoot.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL(forVaultRoot: vaultRoot), options: .atomic)
    }
}
