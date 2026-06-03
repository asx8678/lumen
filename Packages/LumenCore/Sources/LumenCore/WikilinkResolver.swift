//
//  WikilinkResolver.swift
//  LumenCore
//
//  Pure, side-effect-free resolution of an Obsidian-style wikilink target
//  (`[[Note]]`, `[[Note|alias]]`, `[[folder/Note#heading]]`, `[[Note#^block]]`)
//  to a vault-relative note path, given the set of indexed note paths.
//
//  Resolution rule (Obsidian-compatible, deterministic):
//  1. Strip the alias (`|…`) and any heading/block reference (`#…`) from the
//     target — only the note name/path part participates in matching.
//  2. Prefer an exact match on the full vault-relative path (with or without
//     the `.md` extension), case-insensitively.
//  3. Otherwise match on the note's basename (last path segment) against the
//     last segment of the target.
//  4. When several candidates remain, pick deterministically: the shortest
//     path (fewest `/` segments, then fewest characters, then lexicographic).
//
//  Kept free of any I/O so it is headlessly testable over a `[String]` of
//  paths — the host queries `NotesIndex` for the paths and turns the resulting
//  relative path into a file URL against the vault root.
//

import Foundation

/// Pure resolution of a wikilink target to a vault-relative note path.
public enum WikilinkResolver {
    /// Resolves `target` (the raw inner text of a `[[…]]`) to one of `paths`.
    ///
    /// - Parameters:
    ///   - target: The wikilink inner text, e.g. `"folder/Note#Heading"` or
    ///     `"Note|alias"`. Alias and heading/block parts are ignored.
    ///   - paths: Vault-relative note paths (e.g. `"folder/Note.md"`).
    /// - Returns: The best-matching path, or `nil` when nothing matches.
    public static func resolve(target: String, among paths: [String]) -> String? {
        let name = noteName(from: target)
        guard !name.isEmpty else { return nil }
        let lowerName = name.lowercased()
        let targetLast = lastSegment(of: lowerName)

        var pathMatches: [String] = []
        var baseMatches: [String] = []
        for path in paths {
            let noExt = droppingMarkdownExtension(path).lowercased()
            if noExt == lowerName {
                pathMatches.append(path)
            }
            if lastSegment(of: noExt) == targetLast {
                baseMatches.append(path)
            }
        }

        let pool = pathMatches.isEmpty ? baseMatches : pathMatches
        return best(from: pool)
    }

    /// The note-name part of a wikilink target: alias (`|…`) and heading/block
    /// (`#…`) references removed, whitespace trimmed. May contain `/` segments.
    public static func noteName(from target: String) -> String {
        let beforePipe =
            target.split(separator: "|", maxSplits: 1).first.map(String.init) ?? target
        let beforeHash =
            beforePipe.split(separator: "#", maxSplits: 1).first.map(String.init) ?? beforePipe
        return droppingMarkdownExtension(
            beforeHash.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Helpers

    private static func droppingMarkdownExtension(_ string: String) -> String {
        string.lowercased().hasSuffix(".md") ? String(string.dropLast(3)) : string
    }

    private static func lastSegment(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Deterministically selects the "closest" path: fewest segments, then
    /// fewest characters, then lexicographically first.
    private static func best(from paths: [String]) -> String? {
        paths.min { lhs, rhs in
            let lSegments = lhs.split(separator: "/").count
            let rSegments = rhs.split(separator: "/").count
            if lSegments != rSegments { return lSegments < rSegments }
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs < rhs
        }
    }
}
