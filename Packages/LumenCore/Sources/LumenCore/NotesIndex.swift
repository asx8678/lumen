//
//  NotesIndex.swift
//  LumenCore
//
//  The SQLite index persistence layer (P1.8). Opens a GRDB `DatabaseQueue` at
//  `<vaultRoot>/.lumen/index.sqlite`, applies migrations, and exposes thread-
//  safe CRUD + change detection over the `notes` table.
//
//  Architecture: the vault files are the SOURCE OF TRUTH; this DB is a derived,
//  rebuildable cache. Deleting `.lumen/` loses only the cache, never notes.
//  `DatabaseQueue` is `Sendable` and serializes access, so P1.9's background
//  actor can drive this store safely.
//

import Foundation
import GRDB

/// A thread-safe store over the derived `notes` index for one vault.
public struct NotesIndex: Sendable {
    /// The directory name of the per-vault cache.
    public static let cacheDirectoryName = ".lumen"
    /// The index database filename.
    public static let databaseFilename = "index.sqlite"

    private let dbQueue: DatabaseQueue

    /// Opens (creating if needed) the index DB for `vaultRoot`.
    ///
    /// Creates `<vaultRoot>/.lumen/` if missing and applies migrations.
    /// - Parameter vaultRoot: The vault's root directory.
    public init(vaultRoot: URL) throws {
        let cacheDir = vaultRoot.appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let dbURL = cacheDir.appendingPathComponent(Self.databaseFilename)
        self.dbQueue = try DatabaseQueue(path: dbURL.path)
        try Self.migrator.migrate(dbQueue)
    }

    /// Opens an in-memory index (for tests).
    public init() throws {
        self.dbQueue = try DatabaseQueue()
        try Self.migrator.migrate(dbQueue)
    }

    // MARK: - Migrations

    /// The schema migrator. Add new migrations here; never edit shipped ones.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createNotes") { db in
            try db.create(table: NoteRecord.databaseTableName) { table in
                table.primaryKey("path", .text)
                table.column("title", .text)
                table.column("mtime", .double).notNull()
                table.column("size", .integer).notNull()
                table.column("frontmatter", .text)
                table.column("contentHash", .text).notNull()
            }
        }
        return migrator
    }

    // MARK: - CRUD

    /// Inserts or replaces a record (keyed by `path`).
    public func upsert(_ record: NoteRecord) throws {
        try dbQueue.write { db in
            try record.save(db)
        }
    }

    /// Inserts or replaces many records in a single transaction.
    public func upsert(_ records: [NoteRecord]) throws {
        try dbQueue.write { db in
            for record in records { try record.save(db) }
        }
    }

    /// Fetches the record for a relative path, if present.
    public func record(forPath path: String) throws -> NoteRecord? {
        try dbQueue.read { db in
            try NoteRecord.fetchOne(db, key: path)
        }
    }

    /// All records, ordered by path.
    public func allRecords() throws -> [NoteRecord] {
        try dbQueue.read { db in
            try NoteRecord.order(Column("path")).fetchAll(db)
        }
    }

    /// All indexed relative paths (cheap, for reconciliation in P1.9).
    public func allPaths() throws -> Set<String> {
        try dbQueue.read { db in
            try String.fetchSet(db, NoteRecord.select(Column("path")))
        }
    }

    /// Deletes the record for a relative path. Returns `true` if a row was removed.
    @discardableResult
    public func deleteRecord(path: String) throws -> Bool {
        try dbQueue.write { db in
            try NoteRecord.deleteOne(db, key: path)
        }
    }

    /// Removes every record (e.g. before a full rebuild).
    public func deleteAll() throws {
        _ = try dbQueue.write { db in
            try NoteRecord.deleteAll(db)
        }
    }

    /// Record count.
    public func count() throws -> Int {
        try dbQueue.read { db in
            try NoteRecord.fetchCount(db)
        }
    }

    // MARK: - Change detection

    /// Whether the file at `path` needs (re)indexing given current metadata.
    public func needsReindex(path: String, mtime: Double, size: Int64, hash: String) throws -> Bool
    {
        let existing = try record(forPath: path)
        return NoteIndexing.needsReindex(existing: existing, mtime: mtime, size: size, hash: hash)
    }
}
