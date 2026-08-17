import AppKit

/// Method colors and layout metrics.
///
/// Deliberately thin. Stock AppKit controls already handle Dark Mode, Increase
/// Contrast, and accent-color changes, so app code has no business redefining
/// label, separator, or selection colors — use the semantic system colors
/// directly. See REQUIREMENTS.md §10.2.
enum Theme {

    enum Metrics {
        // Column sizing follows Admiral: both side columns are bounded and
        // hold their width, and the middle column is the flexible one. The
        // reverse — a capped middle column — means dragging to widen the
        // settings hits its ceiling immediately and moves the sidebar instead.
        static let sidebarMinWidth: CGFloat = 200
        static let sidebarMaxWidth: CGFloat = 350

        /// Middle column — request settings. Deliberately has no maximum.
        static let settingsMinWidth: CGFloat = 400

        static let resultsMinWidth: CGFloat = 350

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
