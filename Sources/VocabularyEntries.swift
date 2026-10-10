import Foundation

/// Parses the custom vocabulary and applies its explicit corrections.
///
/// An entry is either a plain term ("Higgsfield") or a term followed by the
/// ways speech recognition mishears it, in parentheses:
/// "Higgsfield (XField, X-Field)". Whisper never sees the vocabulary, and the
/// cleanup model does not connect "XField" to "Higgsfield" on its own, so the
/// listed variants are replaced in code, deterministically.
enum VocabularyEntries {
    struct Entry: Equatable {
        let term: String
        let variants: [String]

        /// The entry as it is written in the vocabulary.
        var written: String {
            variants.isEmpty ? term : "\(term) (\(variants.joined(separator: ", ")))"
        }
    }

    /// Entries are separated by newlines, commas or semicolons, except inside
    /// parentheses, where commas separate the variants of one entry.
    static func entries(in vocabulary: String) -> [Entry] {
        var rawEntries: [String] = []
        var current = ""
        var depth = 0
        for character in vocabulary {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if depth == 0, character == "\n" || character == "," || character == ";" {
                rawEntries.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        rawEntries.append(current)

        return rawEntries.compactMap(entry(from:))
    }

    /// The terms alone, without their variants, deduplicated case-insensitively.
    static func terms(in vocabulary: String) -> [String] {
        var seen = Set<String>()
        return entries(in: vocabulary)
            .map(\.term)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    /// Replaces every listed variant with its term. A variant only matches as
    /// a whole word, ignoring case, and spaces or hyphens inside it match any
    /// run of spaces or hyphens, so "X Field" also catches "X-Field".
    static func applyingCorrections(to text: String, vocabulary: String) -> String {
        let corrections = entries(in: vocabulary)
            .flatMap { entry in entry.variants.map { (variant: $0, term: entry.term) } }
            .filter { $0.variant.lowercased() != $0.term.lowercased() }
            // Longest first, so "X Field Studio" wins over "X Field".
            .sorted { $0.variant.count > $1.variant.count }

        var result = text
        for correction in corrections {
            guard let regex = variantPattern(correction.variant) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: correction.term)
            )
        }
        return result
    }

    private static func entry(from raw: String) -> Entry? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard trimmed.hasSuffix(")"),
              let open = trimmed.firstIndex(of: "(") else {
            return Entry(term: trimmed, variants: [])
        }

        let term = trimmed[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        let inner = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        let variants = inner
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !term.isEmpty else { return Entry(term: trimmed, variants: []) }
        return Entry(term: term, variants: variants)
    }

    private static func variantPattern(_ variant: String) -> NSRegularExpression? {
        let separators: (Character) -> Bool = { $0.isWhitespace || "-\u{2010}\u{2011}".contains($0) }
        let parts = variant.split(whereSeparator: separators).map {
            NSRegularExpression.escapedPattern(for: String($0))
        }
        guard !parts.isEmpty else { return nil }
        let body = parts.joined(separator: "[\\s\\-\\x{2010}\\x{2011}]+")
        return try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])\(body)(?![\\p{L}\\p{N}])",
            options: [.caseInsensitive]
        )
    }
}
