//
//  FrontmatterParser.swift
//  LumenCore
//
//  Detects and parses a leading YAML frontmatter block (delimited by `---` on
//  line 1 and a closing `---`/`...`), via Yams, into a ``Frontmatter`` snapshot
//  plus the stripped body (P1.7). Pure utility — no storage, no UI.
//
//  Robustness contract: malformed YAML, a `---` that isn't a real frontmatter
//  fence, or an unterminated block all degrade gracefully to "no frontmatter +
//  full original body" — user content is NEVER lost.
//

import Foundation
import Yams

/// Parses YAML frontmatter out of Markdown notes.
public enum FrontmatterParser {
    /// Parses `text`, returning the frontmatter snapshot (if any) + body.
    ///
    /// - Parameter text: The note's full Markdown source.
    /// - Returns: A ``ParsedNote``. When there is no valid frontmatter, the
    ///   body equals the original `text` and `frontmatter` is `nil`.
    public static func parse(_ text: String) -> ParsedNote {
        guard let block = locateBlock(in: text) else {
            return ParsedNote(frontmatter: nil, body: text)
        }

        // Normalize CRLF so Yams (LF-oriented) parses Windows-authored notes.
        let yaml = String(text[block.yamlRange]).replacingOccurrences(of: "\r\n", with: "\n")
        let strippedBody = String(text[block.bodyStart...].dropLeadingNewline())

        // Empty frontmatter (`---\n---`) is valid: an empty snapshot.
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ParsedNote(
                frontmatter: Frontmatter(),
                body: strippedBody,
                frontmatterRange: text.startIndex..<block.bodyStart,
                frontmatterLineRange: 1...block.closingLine)
        }

        // Parse via Yams; any failure (or non-mapping root) preserves the body.
        guard let parsed = try? Yams.load(yaml: yaml),
            let mapping = parsed as? [String: Any]
        else {
            return ParsedNote(frontmatter: nil, body: text, hadParseError: true)
        }

        let frontmatter = makeFrontmatter(from: mapping)
        return ParsedNote(
            frontmatter: frontmatter,
            body: strippedBody,
            frontmatterRange: text.startIndex..<block.bodyStart,
            frontmatterLineRange: 1...block.closingLine)
    }

    // MARK: - Block location

    private struct Block {
        var yamlRange: Range<String.Index>  // content between the fences
        var bodyStart: String.Index  // first index after the closing fence line
        var closingLine: Int  // 1-based line index of the closing fence
    }

    /// Finds the frontmatter block, or `nil` when `text` doesn't open with a
    /// valid `---` fence on line 1 followed by a closing `---`/`...` fence.
    private static func locateBlock(in text: String) -> Block? {
        let lines = lineSlices(of: text)
        guard let first = lines.first, fence(first.content) == .open else { return nil }

        for index in 1..<lines.count {
            switch fence(lines[index].content) {
            case .open, .close:
                let yamlStart = lines[1].range.lowerBound
                let yamlEnd = lines[index].range.lowerBound
                let yamlRange =
                    yamlStart <= yamlEnd ? yamlStart..<yamlEnd : yamlStart..<yamlStart
                return Block(
                    yamlRange: yamlRange,
                    bodyStart: lines[index].range.upperBound,
                    closingLine: index + 1)
            case nil:
                continue
            }
        }
        return nil  // unterminated → not frontmatter
    }

    private enum Fence { case open, close }

    /// Classifies a line as an opening (`---`) or closing (`---`/`...`) fence.
    private static func fence(_ line: Substring) -> Fence? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "---": return .open
        case "...": return .close
        default: return nil
        }
    }

    /// Splits `text` into line slices (content without the newline) + the range
    /// of each line INCLUDING its trailing newline, preserving original indices.
    private static func lineSlices(
        of text: String
    ) -> [(content: Substring, range: Range<String.Index>)] {
        var result: [(Substring, Range<String.Index>)] = []
        var lineStart = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            // Swift treats "\r\n" as ONE Character, so `.isNewline` correctly
            // handles LF, CR, and CRLF line endings.
            if text[i].isNewline {
                let after = text.index(after: i)
                result.append((text[lineStart..<i], lineStart..<after))
                lineStart = after
            }
            i = text.index(after: i)
        }
        if lineStart < text.endIndex {
            result.append((text[lineStart..<text.endIndex], lineStart..<text.endIndex))
        }
        return result
    }

    // MARK: - Snapshot construction

    private static func makeFrontmatter(from mapping: [String: Any]) -> Frontmatter {
        var raw: [String: YAMLValue] = [:]
        for (key, value) in mapping {
            raw[key] = yamlValue(from: value)
        }

        let title = raw["title"]?.stringValue
        let tags = raw["tags"]?.stringArray ?? []
        let aliases = raw["aliases"]?.stringArray ?? []
        let created = date(forKeys: ["created", "date"], in: mapping)
        let modified = date(forKeys: ["modified", "updated"], in: mapping)

        return Frontmatter(
            title: title,
            tags: tags,
            aliases: aliases,
            created: created,
            modified: modified,
            raw: raw)
    }

    /// Recursively converts a Yams-decoded `Any` into a `Sendable` ``YAMLValue``.
    private static func yamlValue(from any: Any) -> YAMLValue {
        switch any {
        case let b as Bool: return .bool(b)
        case let i as Int: return .int(i)
        case let d as Double: return .double(d)
        case let s as String: return .string(s)
        case let date as Date: return .string(iso8601.string(from: date))
        case is NSNull: return .null
        case let array as [Any]: return .array(array.map(yamlValue(from:)))
        case let dict as [String: Any]: return .dictionary(dict.mapValues(yamlValue(from:)))
        default: return .string(String(describing: any))
        }
    }

    private static func date(forKeys keys: [String], in mapping: [String: Any]) -> Date? {
        for key in keys {
            guard let value = mapping[key] else { continue }
            if let date = value as? Date { return date }
            if let string = value as? String, let parsed = parseDate(string) { return parsed }
        }
        return nil
    }

    private static func parseDate(_ string: String) -> Date? {
        if let date = iso8601.date(from: string) { return date }
        if let date = dayFormatter.date(from: string) { return date }
        return nil
    }

    // Configured once and only read (parsing/formatting) thereafter; the
    // formatters are effectively immutable, so cross-actor reads are safe.
    nonisolated(unsafe) private static let iso8601 = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension Substring {
    /// Drops a single leading newline (`\n`, `\r`, or the `\r\n` grapheme).
    fileprivate func dropLeadingNewline() -> Substring {
        if first?.isNewline == true { return dropFirst() }
        return self
    }
}
