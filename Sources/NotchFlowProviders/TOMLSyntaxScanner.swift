struct TOMLSyntaxScanner {
    private let text: String
    private var brackets: [Character] = []
    private var quotedWith: Character?
    private var escaped = false
    private var inComment = false

    init(text: String) {
        self.text = text
    }

    mutating func isValid() -> Bool {
        for character in text where !consume(character) {
            return false
        }
        return quotedWith == nil && brackets.isEmpty
    }

    private mutating func consume(_ character: Character) -> Bool {
        if inComment {
            inComment = character != "\n"
        } else if let quote = quotedWith {
            consumeQuoted(character, quote: quote)
        } else if character == "#" {
            inComment = true
        } else if character == "\"" || character == "'" {
            quotedWith = character
        } else if character == "[" {
            brackets.append(character)
        } else if character == "]" {
            return brackets.popLast() != nil
        }
        return true
    }

    private mutating func consumeQuoted(_ character: Character, quote: Character) {
        if quote == "\"", character == "\\", !escaped {
            escaped = true
            return
        }
        if character == quote, !escaped {
            quotedWith = nil
        }
        escaped = false
    }
}
