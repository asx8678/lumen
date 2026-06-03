//
//  NoteRecord.swift
//  LumenCore
//
//  The persisted row of the derived `notes` index (P1.8). The vault files are
//  the source of truth; this record is a rebuildable cache entry. The P1.7
//  frontmatter snapshot is serialized to JSON in the `frontmatter` column.
//

import Foundation
import GRDB

/// One row of the `notes` table — a cached snapshot of a Markdown file.
public struct NoteRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    /// Path relative to the vault root (unique key).
    public var path: String
    /// `title` from frontmatter, else the filename stem (best-effort display).
    public var title: String?
    /// File modification time (epoch seconds) at index time.
    public var mtime: Double
    /// File size in bytes at index time.
    public var size: Int64
    /// The serialized P1.7 ``Frontmatter`` snapshot (JSON), or `nil`.
    public var frontmatter: String?
    /// SHA-256 of the file contents (definitive change detector).
    public var contentHash: String

    public init(
        path: String,
        title: String?,
        mtime: Double,
        size: Int64,
        frontmatter: String?,
        contentHash: String
    ) {
        self.path = path
        self.title = title
        self.mtime = mtime
        self.size = size
        self.frontmatter = frontmatter
        self.contentHash = contentHash
    }

    public static let databaseTableName = "notes"

    // MARK: - Frontmatter (de)serialization

    /// Decodes the stored ``Frontmatter`` snapshot, if present/valid.
    public var decodedFrontmatter: Frontmatter? {
        guard let frontmatter, let data = frontmatter.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Frontmatter.self, from: data)
    }

    /// Serializes a ``Frontmatter`` snapshot to a JSON string for storage.
    public static func encodeFrontmatter(_ frontmatter: Frontmatter?) -> String? {
        guard let frontmatter, let data = try? JSONEncoder().encode(frontmatter) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
