import Foundation

enum PhotoshopTargetAddress: Equatable, Sendable {
    case bundleIdentifier(String)
    case applicationPath(String)
}

enum AppleScriptString {
    static func expression(for value: String) -> String {
        var pieces: [String] = []
        var literal = ""

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            pieces.append("\"\(literal)\"")
            literal = ""
        }

        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 9, 10, 13:
                flushLiteral()
                pieces.append("character id \(scalar.value)")
            case 0...8, 11, 12, 14...31, 127:
                flushLiteral()
                pieces.append("character id \(scalar.value)")
            case 34:
                literal += "\\\""
            case 92:
                literal += "\\\\"
            default:
                literal.unicodeScalars.append(scalar)
            }
        }
        flushLiteral()

        if pieces.isEmpty { return "\"\"" }
        if pieces.count == 1 { return pieces[0] }
        return "(" + pieces.joined(separator: " & ") + ")"
    }
}

enum AppleScriptGenerator {
    static func generate(
        actionName: String,
        setName: String,
        target: PhotoshopTargetAddress
    ) -> String {
        let applicationReference: String
        switch target {
        case .bundleIdentifier(let identifier):
            applicationReference = "id \(AppleScriptString.expression(for: identifier))"
        case .applicationPath(let path):
            applicationReference = AppleScriptString.expression(for: path)
        }

        return """
        tell application \(applicationReference)
            activate
            do action \(AppleScriptString.expression(for: actionName)) from \(AppleScriptString.expression(for: setName))
        end tell
        """ + "\n"
    }
}
