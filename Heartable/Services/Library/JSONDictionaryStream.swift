import Foundation

/// Reads one member of a JSON object at a time. Used only for the old playlist
/// cache migration, whose single document can contain an entire large library.
/// Nested strings, escapes, arrays and objects are preserved for JSONDecoder.
final class JSONDictionaryStream {
    enum Failure: Error { case malformed, oversizedValue }
    private let handle: FileHandle
    private var buffer = Data()
    private var position = 0
    private var lookahead: UInt8?
    // Reject a corrupt cache without allocating an unbounded token.
    private let maximumValueBytes = 64 * 1_024 * 1_024

    init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }
    deinit { try? handle.close() }

    private func next() throws -> UInt8? {
        if let byte = lookahead { lookahead = nil; return byte }
        if position == buffer.count {
            buffer = try handle.read(upToCount: 65_536) ?? Data()
            position = 0
        }
        guard position < buffer.count else { return nil }
        defer { position += 1 }
        return buffer[position]
    }

    private func significant() throws -> UInt8? {
        while let byte = try next() {
            if ![9, 10, 13, 32].contains(byte) { return byte }
        }
        return nil
    }

    private func expect(_ byte: UInt8) throws {
        guard try significant() == byte else { throw Failure.malformed }
    }

    private func string() throws -> Data {
        try expect(34)
        var result = Data([34])
        var escaped = false
        while let byte = try next() {
            result.append(byte)
            guard result.count <= maximumValueBytes else { throw Failure.oversizedValue }
            if escaped { escaped = false }
            else if byte == 92 { escaped = true }
            else if byte == 34 { return result }
        }
        throw Failure.malformed
    }

    private func value() throws -> Data {
        guard let start = try significant() else { throw Failure.malformed }
        if start == 34 { lookahead = start; return try string() }
        var result = Data([start])
        if start == 123 || start == 91 {
            var depth = 1
            var quoted = false
            var escaped = false
            while let byte = try next() {
                result.append(byte)
                guard result.count <= maximumValueBytes else { throw Failure.oversizedValue }
                if quoted {
                    if escaped { escaped = false }
                    else if byte == 92 { escaped = true }
                    else if byte == 34 { quoted = false }
                } else if byte == 34 { quoted = true }
                else if byte == 123 || byte == 91 { depth += 1 }
                else if byte == 125 || byte == 93 {
                    depth -= 1
                    if depth == 0 { return result }
                }
            }
            throw Failure.malformed
        }
        while let byte = try next() {
            if byte == 44 || byte == 125 { lookahead = byte; return result }
            result.append(byte)
            guard result.count <= maximumValueBytes else { throw Failure.oversizedValue }
        }
        throw Failure.malformed
    }

    func mapEntries<Result>(named name: String, transform: (String, Data) throws -> Result) throws
        -> (fields: [String: Data], entries: [String: Result]) {
        var fields: [String: Data] = [:]
        var entries: [String: Result] = [:]
        var found = false
        try expect(123)
        while true {
            if try significantIsEnd() { break }
            let key = try JSONDecoder().decode(String.self, from: string())
            try expect(58)
            if key == name {
                guard !found else { throw Failure.malformed }
                found = true
                try expect(123)
                while true {
                    if try significantIsEnd() { break }
                    let entryKey = try JSONDecoder().decode(String.self, from: string())
                    try expect(58)
                    let data = try value()
                    entries[entryKey] = try transform(entryKey, data)
                    guard let delimiter = try significant() else { throw Failure.malformed }
                    if delimiter == 125 { break }
                    guard delimiter == 44 else { throw Failure.malformed }
                }
            } else { fields[key] = try value() }
            guard let delimiter = try significant() else { throw Failure.malformed }
            if delimiter == 125 { break }
            guard delimiter == 44 else { throw Failure.malformed }
        }
        guard found, try significant() == nil else { throw Failure.malformed }
        return (fields, entries)
    }

    private func significantIsEnd() throws -> Bool {
        guard let byte = try significant() else { throw Failure.malformed }
        if byte == 125 { return true }
        lookahead = byte
        return false
    }
}

extension LibraryCacheIO {
    func transformDictionary<Result: Sendable>(at url: URL,
        transform: @Sendable (String, Data) throws -> Result) throws -> (fields: [String: Data], entries: [String: Result]) {
        try JSONDictionaryStream(url: url).mapEntries(named: "entries", transform: transform)
    }
}
