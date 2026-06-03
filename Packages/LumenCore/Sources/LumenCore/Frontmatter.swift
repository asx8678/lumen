//
//  Frontmatter.swift
//  LumenCore
//
//  The metadata snapshot produced by parsing a note's YAML frontmatter (P1.7).
//  Pure, `Sendable` value types — this is what P1.8 will persist to the index
//  and P1.9 will feed through the indexing pipeline. No UI, no storage here.
//

import Foundation

/// A `Sendable` representation of an arbitrary YAML scalar/collection value, so
/// frontmatter keys we don't model explicitly are still preserved losslessly.
public enum YAMLValue: Sendable, Equatable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([YAMLValue])
    case dictionary([String: YAMLValue])

    /// The value as a `String` when it is a scalar (string/int/double/bool).
    public var stringValue: String? {
        switch self {
        case .string(let s): s
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .bool(let b): String(b)
        case .null, .array, .dictionary: nil
        }
    }

    /// The value normalized to `[String]` (a scalar becomes a single element).
    public var stringArray: [String] {
        switch self {
        case .array(let items): items.compactMap(\.stringValue)
        default: stringValue.map { [$0] } ?? []
        }
    }
}

/// A parsed metadata snapshot for a note.
///
/// Commonly-used fields are surfaced as typed properties; every key (including
/// the typed ones) is also available verbatim in ``raw`` for arbitrary access.
public struct Frontmatter: Sendable, Equatable {
    /// `title`, if present.
    public var title: String?
    /// `tags`, normalized from a scalar or array to `[String]`.
    public var tags: [String]
    /// `aliases`, normalized to `[String]`.
    public var aliases: [String]
    /// `created` / `date`, if parseable as a date.
    public var created: Date?
    /// `modified` / `updated`, if parseable as a date.
    public var modified: Date?
    /// Every top-level key/value, preserved verbatim.
    public var raw: [String: YAMLValue]

    public init(
        title: String? = nil,
        tags: [String] = [],
        aliases: [String] = [],
        created: Date? = nil,
        modified: Date? = nil,
        raw: [String: YAMLValue] = [:]
    ) {
        self.title = title
        self.tags = tags
        self.aliases = aliases
        self.created = created
        self.modified = modified
        self.raw = raw
    }
}

/// The full result of parsing a note: the (optional) frontmatter snapshot, the
/// body with the frontmatter block removed, and the location of the block in
/// the original text (so callers can map back).
public struct ParsedNote: Sendable, Equatable {
    /// The parsed frontmatter, or `nil` when there is none (or it was malformed).
    public var frontmatter: Frontmatter?
    /// The note body (original text with any frontmatter block stripped).
    public var body: String
    /// The character range of the entire frontmatter block (delimiters
    /// included) within the ORIGINAL text, or `nil` when there is none.
    public var frontmatterRange: Range<String.Index>?
    /// The 1-based line range of the frontmatter block, or `nil`.
    public var frontmatterLineRange: ClosedRange<Int>?
    /// True if a frontmatter block was detected but failed to parse as YAML.
    public var hadParseError: Bool

    public init(
        frontmatter: Frontmatter?,
        body: String,
        frontmatterRange: Range<String.Index>? = nil,
        frontmatterLineRange: ClosedRange<Int>? = nil,
        hadParseError: Bool = false
    ) {
        self.frontmatter = frontmatter
        self.body = body
        self.frontmatterRange = frontmatterRange
        self.frontmatterLineRange = frontmatterLineRange
        self.hadParseError = hadParseError
    }
}
