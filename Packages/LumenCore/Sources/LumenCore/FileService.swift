//
//  FileService.swift
//  LumenCore
//
//  Off-main filesystem operations for a vault: enumerate, read, atomic write,
//  trash, rename, and create note/folder. Implemented as an `actor` so all IO
//  is isolated off the main thread (the app's "actors isolate IO" rule).
//
//  P1.5 scope: the data layer + operations only. No UI (P1.15), no FSEvents
//  (P1.6), no frontmatter (P1.7), no autosave loop (P1.11 — this provides the
//  atomic `write` primitive it will call). Security-scoped access to the vault
//  is held by `VaultManager` (P1.4); these ops run inside that scope.
//

import Foundation
import os

/// Typed errors for filesystem operations.
public enum FileServiceError: Error, Sendable, Equatable {
    /// The URL could not be read as UTF-8 text.
    case notUTF8
    /// A destination name was empty or invalid.
    case invalidName
    /// The underlying filesystem operation failed.
    case ioFailed(String)
}

/// Markdown file extensions recognized by Lumen.
private let markdownExtensions: Set<String> = ["md", "markdown"]

/// Directory / file names that are always skipped during enumeration.
private let excludedNames: Set<String> = [".lumen", ".git"]

/// An actor that performs vault filesystem operations off the main thread.
public actor FileService {
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "ai.Lumen", category: "FileService")

    /// Creates a file service.
    /// - Parameter fileManager: The file manager to use (injectable for tests).
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Enumerate

    /// Recursively enumerates the contents of `root`.
    ///
    /// Distinguishes folders, Markdown files, and other files (attachments).
    /// Skips hidden dotfiles and the `.lumen/` and `.git/` directories.
    /// - Parameter root: The vault root directory.
    /// - Returns: A sorted-by-nothing tree of ``VaultItem`` (caller sorts).
    public func enumerate(_ root: URL) throws -> [VaultItem] {
        try children(of: root)
    }

    private func children(of directory: URL) throws -> [VaultItem] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey,
        ]
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw FileServiceError.ioFailed(error.localizedDescription)
        }

        var items: [VaultItem] = []
        for url in entries {
            let name = url.lastPathComponent
            // Defense-in-depth: skip excluded + dotfiles even if not flagged hidden.
            if excludedNames.contains(name) || name.hasPrefix(".") { continue }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate

            if isDir {
                let kids = try children(of: url)
                items.append(
                    VaultItem(
                        url: url, kind: .folder, size: 0,
                        modificationDate: modified, children: kids))
            } else {
                let kind: VaultItemKind =
                    markdownExtensions.contains(url.pathExtension.lowercased())
                    ? .markdown : .other
                items.append(
                    VaultItem(
                        url: url, kind: kind, size: size, modificationDate: modified))
            }
        }
        return items
    }

    // MARK: - Read / Write

    /// Reads the file at `url` as UTF-8 text.
    public func read(_ url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FileServiceError.ioFailed(error.localizedDescription)
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw FileServiceError.notUTF8
        }
        return string
    }

    /// Writes `contents` to `url` **atomically** (temp write + atomic replace).
    ///
    /// This is the reliability-critical primitive the autosave system (P1.11)
    /// will call; a crash mid-write never corrupts the existing file.
    public func write(_ contents: String, to url: URL) throws {
        let data = Data(contents.utf8)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw FileServiceError.ioFailed(error.localizedDescription)
        }
    }

    // MARK: - Trash / Rename

    /// Moves the item at `url` to the system Trash (not a permanent delete).
    /// - Returns: The item's resulting URL inside the Trash, if provided.
    @discardableResult
    public func moveToTrash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        do {
            try fileManager.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            throw FileServiceError.ioFailed(error.localizedDescription)
        }
        return resulting as URL?
    }

    /// Renames the item at `url` to `newName`, resolving collisions.
    /// - Returns: The new URL.
    public func rename(_ url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FileServiceError.invalidName }

        let directory = url.deletingLastPathComponent()
        let destination = uniqueURL(in: directory, proposed: trimmed)
        do {
            try fileManager.moveItem(at: url, to: destination)
        } catch {
            throw FileServiceError.ioFailed(error.localizedDescription)
        }
        return destination
    }

    // MARK: - Create

    /// Creates a new Markdown note in `dir`, uniquifying the name on collision.
    /// - Parameters:
    ///   - dir: The destination directory.
    ///   - named: Desired file name (with or without extension). Defaults to
    ///     `"Untitled.md"`.
    /// - Returns: The created file's URL.
    public func createNote(in dir: URL, named: String? = nil) throws -> URL {
        let base =
            (named?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            } ?? "Untitled.md"
        let withExt =
            base.lowercased().hasSuffix(".md") || base.lowercased().hasSuffix(".markdown")
            ? base : base + ".md"
        let destination = uniqueURL(in: dir, proposed: withExt)
        do {
            try Data().write(to: destination, options: [.atomic])
        } catch {
            throw FileServiceError.ioFailed(error.localizedDescription)
        }
        return destination
    }

    /// Creates a new folder in `dir`, uniquifying the name on collision.
    /// - Returns: The created folder's URL.
    public func createFolder(in dir: URL, named: String? = nil) throws -> URL {
        let base =
            (named?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            } ?? "New Folder"
        let destination = uniqueURL(in: dir, proposed: base)
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        } catch {
            throw FileServiceError.ioFailed(error.localizedDescription)
        }
        return destination
    }

    // MARK: - Uniquify

    /// Returns a URL in `dir` for `proposed`, appending " 1", " 2", … before the
    /// extension until the name is free. Pure path math; does not touch disk
    /// beyond existence checks.
    func uniqueURL(in dir: URL, proposed: String) -> URL {
        let candidate = dir.appendingPathComponent(proposed)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (proposed as NSString).pathExtension
        let stem = (proposed as NSString).deletingPathExtension
        var index = 1
        while true {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let url = dir.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }
}
