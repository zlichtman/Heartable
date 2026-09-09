import Foundation

/// Cross-service dedup identity for a track. Two tracks from different services
/// collapse into one master row when their normalized title + primary artist
/// match. The rule is aggressive but deliberately conservative: it strips only
/// noise, keeps anything that could define a genuinely different version, and
/// never merges when unsure.
///
/// Normalization rule
/// ------------------
///  1. Featured-artist credits are removed (`feat.`, `ft.`, `featuring …`) from
///     both title and artist, because services credit features inconsistently.
///  2. Parenthetical / bracketed / `- suffix` qualifiers are classified:
///       - VERSION-DEFINING (live, acoustic, remix, demo, instrumental, edit,
///         "taylor's version", sped up, slowed, cover, …) are KEPT so real
///         alternates stay distinct.
///       - Pure NOISE (remaster, explicit, deluxe, bonus, mono/stereo,
///         anniversary, "album version", "radio edit", …) is DROPPED.
///       - Anything unrecognized is KEPT (safer to keep two rows than to merge
///         two different songs).
///  3. The remainder is diacritic- and case-folded, stripped of punctuation, and
///     whitespace-collapsed.
///  4. Only the PRIMARY (first-credited) artist is used, because services differ
///     in how many featured artists they list and in what order.
struct UnifiedTrackIdentity: Hashable, Sendable, Codable {
    /// `"{normalizedTitle}|{normalizedArtist}"` — the grouping key.
    let key: String
    let normalizedTitle: String
    let normalizedArtist: String

    static func make(title: String, artist: String) -> UnifiedTrackIdentity {
        let normTitle = normalizeTitle(title)
        let normArtist = normalizeArtist(artist)
        // A title that normalizes to nothing (it was only a qualifier) falls back
        // to the raw folded title so two such tracks don't collapse into one
        // empty-keyed row.
        let safeTitle = normTitle.isEmpty ? basicFold(title) : normTitle
        return UnifiedTrackIdentity(
            key: "\(safeTitle)|\(normArtist)",
            normalizedTitle: safeTitle,
            normalizedArtist: normArtist
        )
    }

    // MARK: - Title

    static func normalizeTitle(_ raw: String) -> String {
        var s = stripParentheticals(raw)
        s = stripFeat(s)
        s = stripDashQualifier(s)
        return basicFold(s)
    }

    // MARK: - Artist

    static func normalizeArtist(_ raw: String) -> String {
        basicFold(stripFeat(primaryArtist(raw)))
    }

    /// First credited artist only — split on the first collaboration separator.
    private static func primaryArtist(_ raw: String) -> String {
        let separators = [",", " & ", " feat", " ft", " featuring", " x ", " × ", " with "]
        let lowered = raw.lowercased()
        var cut = raw.count
        for sep in separators {
            if let r = lowered.range(of: sep) {
                cut = min(cut, lowered.distance(from: lowered.startIndex, to: r.lowerBound))
            }
        }
        let idx = raw.index(raw.startIndex, offsetBy: cut)
        return String(raw[..<idx])
    }

    // MARK: - Qualifier classification

    /// Presence of one of these in a qualifier keeps it (a distinct version).
    private static let keepTokens = [
        "live", "acoustic", "remix", "demo", "instrumental", "unplugged",
        "reprise", "session", "sped up", "spedup", "slowed", "cover",
        "karaoke", "taylor's version", "taylors version", "re-recorded",
        "rerecorded", "extended", "vip"
    ]
    /// Presence of one of these (without a keep token) drops it (pure noise).
    private static let noiseTokens = [
        "remaster", "remastered", "explicit", "deluxe", "bonus", "mono",
        "stereo", "anniversary", "expanded", "reissue", "clean"
    ]
    /// Whole-qualifier phrases that are always noise even though they contain a
    /// keep token like "version"/"edit"/"mix".
    private static let noiseExact: Set<String> = [
        "album version", "single version", "original version", "original mix",
        "radio edit", "radio version", "main version", "original", "lp version",
        "7\" version", "12\" version", "original single version"
    ]

    /// Does a qualifier's inner text mark a distinct version (keep) or noise (drop)?
    /// Unrecognized -> keep.
    private static func isNoiseQualifier(_ inner: String) -> Bool {
        let t = inner.lowercased().trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        if noiseExact.contains(t) { return true }
        if keepTokens.contains(where: { t.contains($0) }) { return false }
        // Featured-artist parentheticals are noise for identity purposes.
        if t.hasPrefix("feat") || t.hasPrefix("ft") || t.hasPrefix("with ") { return true }
        if noiseTokens.contains(where: { t.contains($0) }) { return true }
        return false
    }

    /// Remove `(…)` / `[…]` groups that are pure noise; keep the rest. Single-level.
    private static func stripParentheticals(_ s: String) -> String {
        var out = ""
        var buffer = ""
        var inside = false
        var open: Character = "("
        for ch in s {
            if !inside, ch == "(" || ch == "[" {
                inside = true
                open = ch
                buffer = ""
            } else if inside, (open == "(" && ch == ")") || (open == "[" && ch == "]") {
                inside = false
                if !isNoiseQualifier(buffer) {
                    out.append(open)
                    out.append(buffer)
                    out.append(ch)
                }
            } else if inside {
                buffer.append(ch)
            } else {
                out.append(ch)
            }
        }
        // Unterminated group — append what we buffered so nothing is silently lost.
        if inside { out.append(open); out.append(buffer) }
        return out
    }

    /// Truncate a trailing `feat …` / `ft …` credit that isn't inside parentheses.
    private static func stripFeat(_ s: String) -> String {
        let lowered = s.lowercased()
        let markers = [" feat.", " feat ", " ft.", " ft ", " featuring "]
        var cut = s.count
        for m in markers {
            if let r = lowered.range(of: m) {
                cut = min(cut, lowered.distance(from: lowered.startIndex, to: r.lowerBound))
            }
        }
        guard cut < s.count else { return s }
        let idx = s.index(s.startIndex, offsetBy: cut)
        return String(s[..<idx])
    }

    /// Drop trailing `- Qualifier` segments that are noise (e.g. `- Remastered 2011`),
    /// keeping version-defining ones (`- Live at Wembley`).
    private static func stripDashQualifier(_ s: String) -> String {
        var segments = s.components(separatedBy: " - ")
        guard segments.count > 1 else { return s }
        while segments.count > 1, isNoiseQualifier(segments[segments.count - 1]) {
            segments.removeLast()
        }
        return segments.joined(separator: " - ")
    }

    // MARK: - Folding

    /// Lowercase, drop diacritics, reduce to alphanumerics + single spaces.
    static func basicFold(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var scalars = String.UnicodeScalarView()
        for sc in folded.unicodeScalars {
            scalars.append(CharacterSet.alphanumerics.contains(sc) ? sc : " ")
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }
}
