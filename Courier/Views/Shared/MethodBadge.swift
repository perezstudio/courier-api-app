import AppKit
import SwiftUI

struct MethodBadge: View {
    let method: String

    var body: some View {
        Text(shortLabel)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(methodColor)
    }

    private var shortLabel: String {
        switch method.uppercased() {
        case "DELETE": return "DEL"
        case "OPTIONS": return "OPT"
        case "PATCH": return "PAT"
        default: return method.uppercased()
        }
    }

    private var methodColor: Color {
        Color(nsColor: HTTPMethod.color(for: method))
    }
}

/// Shared color/label resolver for HTTP methods — used by SwiftUI badges and AppKit picker.
enum HTTPMethod {
    static let all = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    static func color(for method: String) -> NSColor {
        switch method.uppercased() {
        case "GET": return .systemGreen
        case "POST": return .systemYellow
        case "PUT": return .systemBlue
        case "PATCH": return .systemPurple
        case "DELETE": return .systemRed
        case "HEAD": return .systemTeal
        case "OPTIONS": return .systemPink
        default: return .secondaryLabelColor
        }
    }
}
