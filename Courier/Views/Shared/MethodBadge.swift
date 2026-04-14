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
        switch method.uppercased() {
        case "GET": return .green
        case "POST": return .orange
        case "PUT": return .blue
        case "PATCH": return .purple
        case "DELETE": return .red
        case "HEAD": return .teal
        case "OPTIONS": return .gray
        default: return .secondary
        }
    }
}
