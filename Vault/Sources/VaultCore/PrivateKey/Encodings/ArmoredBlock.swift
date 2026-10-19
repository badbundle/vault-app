import Foundation
import FoundationExtensions

/// A block of Base64 between `-----BEGIN LABEL-----` and `-----END LABEL-----` lines, as PEM (RFC 7468), OpenSSH and
/// OpenPGP (RFC 9580, section 6.2) all write keys.
struct ArmoredBlock: Equatable {
    /// What the BEGIN line names, such as "OPENSSH PRIVATE KEY".
    var label: String
    /// The `Name: Value` lines before the Base64, which OpenPGP's armor and legacy encrypted PEM keys have.
    var headers: [(name: String, value: String)]
    /// The Base64, decoded.
    var data: [UInt8]
    /// The OpenPGP armor's CRC-24, from its `=` line, if it has one.
    var checksum: UInt32?

    static func == (lhs: ArmoredBlock, rhs: ArmoredBlock) -> Bool {
        lhs.label == rhs.label && lhs.data == rhs.data && lhs.checksum == rhs.checksum
            && lhs.headers.map(\.name) == rhs.headers.map(\.name)
            && lhs.headers.map(\.value) == rhs.headers.map(\.value)
    }

    enum ParseResult: Equatable {
        case block(ArmoredBlock)
        /// A BEGIN line, but no END line for it, or Base64 that can't be read.
        case unreadable(label: String)
        /// No BEGIN line.
        case none
    }

    /// The label of the first BEGIN line in `text`, if there is one.
    static func label(in text: String) -> String? {
        lines(of: text).lazy.compactMap(beginLabel(of:)).first
    }

    /// The first armored block in `text`. Anything before its BEGIN line or after its END line is ignored, as RFC
    /// 7468 says parsers should allow ("Parsers MAY ... ignore ... explanatory text").
    static func parse(_ text: String) -> ParseResult {
        let allLines = lines(of: text)
        guard
            let beginIndex = allLines.firstIndex(where: { beginLabel(of: $0) != nil }),
            let label = beginLabel(of: allLines[beginIndex])
        else { return .none }
        guard let endIndex = allLines[(beginIndex + 1)...].firstIndex(of: "-----END \(label)-----") else {
            return .unreadable(label: label)
        }

        var bodyLines = Array(allLines[(beginIndex + 1) ..< endIndex])
        var headers = [(name: String, value: String)]()
        // Headers, if any, come first, and end at a blank line.
        if let blank = bodyLines.firstIndex(of: ""), bodyLines[..<blank].allSatisfy({ $0.contains(":") }) {
            for line in bodyLines[..<blank] {
                let parts = line.split(separator: ":", maxSplits: 1)
                headers.append((
                    name: String(parts[0]).trimmingCharacters(in: .whitespaces),
                    value: parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "",
                ))
            }
            bodyLines.removeSubrange(...blank)
        }
        bodyLines.removeAll(where: \.isEmpty)

        var checksum: UInt32?
        if let last = bodyLines.last, last.hasPrefix("="), last.count == 5 {
            guard
                let checksumBytes = Data(base64Encoded: String(last.dropFirst())),
                checksumBytes.count == 3
            else { return .unreadable(label: label) }
            checksum = checksumBytes.reduce(0) { $0 << 8 | UInt32($1) }
            bodyLines.removeLast()
        }

        guard
            let data = Data(base64Encoded: bodyLines.joined()),
            data.isNotEmpty
        else { return .unreadable(label: label) }
        return .block(ArmoredBlock(label: label, headers: headers, data: Array(data), checksum: checksum))
    }

    private static func lines(of text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func beginLabel(of line: String) -> String? {
        let prefix = "-----BEGIN "
        let suffix = "-----"
        guard line.hasPrefix(prefix), line.hasSuffix(suffix), line.count > prefix.count + suffix.count else {
            return nil
        }
        return String(line.dropFirst(prefix.count).dropLast(suffix.count))
    }
}
