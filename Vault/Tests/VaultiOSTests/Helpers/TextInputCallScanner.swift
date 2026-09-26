import Foundation

/// Finds the text inputs created in Swift source, and the modifiers chained onto each one.
///
/// It reads the text rather than a syntax tree, which is enough for how the app's views are written: a call to one of
/// `inputNames`, any trailing closures, then a chain of `.modifier(…)` calls. Comments and string literals are
/// skipped, so a field mentioned in a doc comment, or a bracket inside a label, doesn't throw it off.
enum TextInputCallScanner {
    /// SwiftUI's text inputs, and the app's own field built from them.
    static let inputNames = ["TextField", "SecureField", "TextEditor", "LabeledTextField"]

    struct Call: Equatable {
        var name: String
        /// 1-based, like a compiler diagnostic.
        var line: Int
        /// The names of the modifiers chained onto the call, in order.
        var modifiers: [String]
    }

    static func calls(in source: String) -> [Call] {
        let code = codeOnly(Array(source.utf8))
        let text = String(decoding: code, as: UTF8.self)
        let pattern = /(TextField|SecureField|TextEditor|LabeledTextField)\s*\(/
        return text.matches(of: pattern).compactMap { match in
            let start = text.utf8.distance(from: text.utf8.startIndex, to: match.range.lowerBound)
            // Part of a longer name, like `MyTextField`.
            if start > 0, code[start - 1].isIdentifierCharacter {
                return nil
            }
            let openParen = text.utf8.distance(from: text.utf8.startIndex, to: match.range.upperBound) - 1
            let line = code[..<start].count(where: { $0 == .newline }) + 1
            return Call(
                name: String(match.output.1),
                line: line,
                modifiers: modifierChain(in: code, afterCallAt: openParen),
            )
        }
    }

    // MARK: - Modifier chain

    /// Everything after the call's arguments: trailing closures, then `.name(…)` and `.name { … }` for as long as the
    /// chain goes on.
    private static func modifierChain(in code: [UInt8], afterCallAt openParen: Int) -> [String] {
        var modifiers: [String] = []
        var index = endOfGroup(in: code, openingAt: openParen)
        while true {
            index = skippingWhitespace(in: code, from: index)
            guard index < code.count else { break }
            if code[index] == .openBrace {
                // A trailing closure, possibly one of several (`} label: {`).
                index = endOfGroup(in: code, openingAt: index)
                let afterClosure = skippingWhitespace(in: code, from: index)
                if let labelEnd = endOfClosureLabel(in: code, from: afterClosure) {
                    index = labelEnd
                }
            } else if code[index] == .dot {
                let nameStart = index + 1
                var nameEnd = nameStart
                while nameEnd < code.count, code[nameEnd].isIdentifierCharacter {
                    nameEnd += 1
                }
                guard nameEnd > nameStart else { break }
                modifiers.append(String(decoding: code[nameStart ..< nameEnd], as: UTF8.self))
                index = nameEnd
                if index < code.count, code[index] == .openParen {
                    index = endOfGroup(in: code, openingAt: index)
                }
            } else {
                break
            }
        }
        return modifiers
    }

    /// With `index` at `label:` followed by `{`, where the closure starts.
    private static func endOfClosureLabel(in code: [UInt8], from index: Int) -> Int? {
        var end = index
        while end < code.count, code[end].isIdentifierCharacter {
            end += 1
        }
        guard end > index, end < code.count, code[end] == .colon else { return nil }
        let brace = skippingWhitespace(in: code, from: end + 1)
        return brace < code.count && code[brace] == .openBrace ? brace : nil
    }

    private static func skippingWhitespace(in code: [UInt8], from index: Int) -> Int {
        var index = index
        while index < code.count, code[index].isWhitespace {
            index += 1
        }
        return index
    }

    /// Just past the bracket that closes the one at `index`.
    private static func endOfGroup(in code: [UInt8], openingAt index: Int) -> Int {
        var depth = 0
        var index = index
        while index < code.count {
            switch code[index] {
            case .openParen, .openBrace, .openBracket: depth += 1
            case .closeParen, .closeBrace, .closeBracket: depth -= 1
            default: break
            }
            index += 1
            if depth == 0 {
                break
            }
        }
        return index
    }

    // MARK: - Comments and strings

    /// The source with every comment and string literal blanked out, keeping line breaks so lines still count.
    static func codeOnly(_ source: [UInt8]) -> [UInt8] {
        var code = source
        var index = 0
        while index < source.count {
            let end: Int
            if source.hasPrefix([.slash, .slash], at: index) {
                end = source[index...].firstIndex(of: .newline) ?? source.count
            } else if source.hasPrefix([.slash, .star], at: index) {
                end = endOfBlockComment(in: source, from: index)
            } else if let stringEnd = endOfStringLiteral(in: source, from: index) {
                end = stringEnd
            } else {
                index += 1
                continue
            }
            for blanked in index ..< end where code[blanked] != .newline {
                code[blanked] = .space
            }
            index = end
        }
        return code
    }

    /// Block comments nest in Swift.
    private static func endOfBlockComment(in source: [UInt8], from index: Int) -> Int {
        var depth = 0
        var index = index
        while index < source.count {
            if source.hasPrefix([.slash, .star], at: index) {
                depth += 1
                index += 2
            } else if source.hasPrefix([.star, .slash], at: index) {
                depth -= 1
                index += 2
                if depth == 0 {
                    return index
                }
            } else {
                index += 1
            }
        }
        return source.count
    }

    /// If a string literal starts at `index` (`"…"`, `"""…"""` or raw `#"…"#`), just past its end.
    private static func endOfStringLiteral(in source: [UInt8], from index: Int) -> Int? {
        var hashes = 0
        while index + hashes < source.count, source[index + hashes] == .hash {
            hashes += 1
        }
        let quote = index + hashes
        guard quote < source.count, source[quote] == .quote else { return nil }
        let isMultiline = source.hasPrefix([.quote, .quote, .quote], at: quote)
        let delimiter = [UInt8](repeating: .quote, count: isMultiline ? 3 : 1) + [UInt8](
            repeating: .hash,
            count: hashes,
        )
        let escape = [UInt8.backslash] + [UInt8](repeating: .hash, count: hashes)

        var position = quote + (isMultiline ? 3 : 1)
        while position < source.count {
            if source.hasPrefix(delimiter, at: position) {
                return position + delimiter.count
            } else if source.hasPrefix(escape, at: position) {
                let escaped = position + escape.count
                if escaped < source.count, source[escaped] == .openParen {
                    position = endOfInterpolation(in: source, openingAt: escaped)
                } else {
                    position = escaped + 1
                }
            } else {
                position += 1
            }
        }
        return source.count
    }

    /// An interpolation is code, so it can hold brackets and string literals of its own.
    private static func endOfInterpolation(in source: [UInt8], openingAt index: Int) -> Int {
        var depth = 0
        var index = index
        while index < source.count {
            if let stringEnd = endOfStringLiteral(in: source, from: index) {
                index = stringEnd
                continue
            }
            if source[index] == .openParen {
                depth += 1
            } else if source[index] == .closeParen {
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            }
            index += 1
        }
        return source.count
    }
}

extension [UInt8] {
    fileprivate func hasPrefix(_ prefix: [UInt8], at index: Int) -> Bool {
        index + prefix.count <= count && self[index ..< index + prefix.count].elementsEqual(prefix)
    }
}

extension UInt8 {
    fileprivate static let newline = UInt8(ascii: "\n")
    fileprivate static let space = UInt8(ascii: " ")
    fileprivate static let slash = UInt8(ascii: "/")
    fileprivate static let star = UInt8(ascii: "*")
    fileprivate static let hash = UInt8(ascii: "#")
    fileprivate static let quote = UInt8(ascii: "\"")
    fileprivate static let backslash = UInt8(ascii: "\\")
    fileprivate static let dot = UInt8(ascii: ".")
    fileprivate static let colon = UInt8(ascii: ":")
    fileprivate static let openParen = UInt8(ascii: "(")
    fileprivate static let closeParen = UInt8(ascii: ")")
    fileprivate static let openBrace = UInt8(ascii: "{")
    fileprivate static let closeBrace = UInt8(ascii: "}")
    fileprivate static let openBracket = UInt8(ascii: "[")
    fileprivate static let closeBracket = UInt8(ascii: "]")

    fileprivate var isWhitespace: Bool {
        self == .space || self == .newline || self == UInt8(ascii: "\t") || self == UInt8(ascii: "\r")
    }

    fileprivate var isIdentifierCharacter: Bool {
        (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(self)
            || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(self)
            || (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(self)
            || self == UInt8(ascii: "_")
    }
}
