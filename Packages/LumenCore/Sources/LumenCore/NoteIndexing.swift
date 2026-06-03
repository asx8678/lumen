//
//  NoteIndexing.swift
//  LumenCore
//
//  Pure, UI-agnostic helpers for the index (P1.8): content hashing, change
//  detection against a stored record, and building a `NoteRecord` from a file's
//  metadata + a parsed note (P1.7). The enumeration/orchestration loop is P1.9.
//

import CryptoKit
import Foundation

/// Stateless indexing helpers.
public enum NoteIndexing {
    /// SHA-256 of `text`, hex-encoded — the definitive change detector.
    public static func contentHash(of text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether a file needs (re)indexing versus its stored record.
    ///
    /// Cheap path first (mtime + size differ → definitely changed); otherwise
    /// the content hash is authoritative. A `nil` existing record (never
    /// indexed) always needs indexing.
    /// - Parameters:
    ///   - existing: The stored record, if any.
    ///   - mtime: Current file modification time (epoch seconds).
    ///   - size: Current file size in bytes.
    ///   - hash: Current content hash (SHA-256 hex).
    public static func needsReindex(
        existing: NoteRecord?,
        mtime: Double,
        size: Int64,
        hash: String
    ) -> Bool {
        guard let existing else { return true }
        if existing.size != size { return true }
        if existing.contentHash != hash { return true }
        // mtime alone is advisory; content hash already matched above.
        return false
    }

    /// Builds a `NoteRecord` from file metadata + a parsed note (P1.7).
    ///
    /// - Parameters:
    ///   - relativePath: Path relative to the vault root (the unique key).
    ///   - text: The file's full contents.
    ///   - mtime: File modification time (epoch seconds).
    ///   - size: File size in bytes.
    ///   - parsed: The P1.7 parse result (frontmatter + body).
    public static func makeRecord(
        relativePath: String,
        text: String,
        mtime: Double,
        size: Int64,
        parsed: ParsedNote
    ) -> NoteRecord {
        let stem = (relativePath as NSString).lastPathComponent
        let fallbackTitle = (stem as NSString).deletingPathExtension
        let title = parsed.frontmatter?.title ?? fallbackTitle
        return NoteRecord(
            path: relativePath,
            title: title,
            mtime: mtime,
            size: size,
            frontmatter: NoteRecord.encodeFrontmatter(parsed.frontmatter),
            contentHash: contentHash(of: text))
    }
}
