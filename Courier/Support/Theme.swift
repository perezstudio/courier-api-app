import AppKit

/// Method colors and layout metrics.
///
/// Deliberately thin. Stock AppKit controls already handle Dark Mode, Increase
/// Contrast, and accent-color changes, so app code has no business redefining
/// label, separator, or selection colors — use the semantic system colors
/// directly. See REQUIREMENTS.md §10.2.
enum Theme {

    enum Metrics {
        static let sidebarMinWidth: CGFloat = 220
        static let sidebarIdealWidth: CGFloat = 260
        static let sidebarMaxWidth: CGFloat = 400

        static let editorMinWidth: CGFloat = 380
        static let responseMinWidth: CGFloat = 320

        static let urlBarHeight: CGFloat = 44
        static let standardPadding: CGFloat = 12
        static let tightPadding: CGFloat = 8
    }

    /// HTTP methods, in the order they appear in the picker.
    enum Method: String, CaseIterable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
        case head = "HEAD"
        case options = "OPTIONS"

        var color: NSColor {
            switch self {
            case .get: .systemBlue
            case .post: .systemGreen
            case .put: .systemOrange
            case .patch: .systemPurple
            case .delete: .systemRed
            case .head, .options: .systemGray
            }
        }
    }

    static func color(forMethod method: String) -> NSColor {
        Method(rawValue: method.uppercased())?.color ?? .systemGray
    }

    /// Color for an HTTP status code, by class.
    static func color(forStatusCode code: Int) -> NSColor {
        switch code {
        case 200..<300: .systemGreen
        case 300..<400: .systemYellow
        case 400..<600: .systemRed
        default: .systemGray
        }
    }
}
