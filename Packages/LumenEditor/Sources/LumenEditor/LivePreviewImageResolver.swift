//
//  LivePreviewImageResolver.swift
//  LumenEditor
//
//  Pure, side-effect-free resolution of an inline-image source (the URL/path
//  in `![alt](src)` or the embed target in `![[src]]`) to a loadable `URL`,
//  given the note's base directory. Mirrors the reading view's
//  `MarkdownImageView.resolvedURL` rule so Live Preview and Reading resolve
//  images identically:
//
//  * A source with a scheme (`https://…`, `file://…`) is a remote/absolute URL
//    and is used verbatim.
//  * Anything else is treated as a path relative to the note's directory
//    (`baseURL`); the vault's security-scoped access is already granted.
//  * With no `baseURL`, fall back to interpreting the source as a bare URL.
//
//  Kept I/O-free so it is headlessly testable; the actual pixel load happens in
//  the editor coordinator (file read / `URLSession`) keyed on this URL.
//

import Foundation

/// Pure resolution of an inline-image source to a loadable URL.
public enum LivePreviewImageResolver {
    /// Resolves `source` against the note's `baseURL`.
    ///
    /// - Parameters:
    ///   - source: The raw image source from the Markdown (`![…](source)` or
    ///     `![[source]]`). A leading/trailing whitespace-only source is `nil`.
    ///   - baseURL: The note's directory, for vault-relative paths.
    /// - Returns: A URL to load, or `nil` when the source is empty.
    public static func resolvedURL(source: String, baseURL: URL?) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        if let baseURL {
            return URL(fileURLWithPath: trimmed, relativeTo: baseURL)
        }
        return URL(string: trimmed)
    }

    /// Whether `url` points at a local file (so it can be loaded synchronously).
    public static func isLocalFile(_ url: URL) -> Bool {
        url.isFileURL
    }
}
