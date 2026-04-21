import Foundation
import os

/// Dedicated logger for sidebar drag-and-drop. Filter in Console.app:
///   subsystem:com.courier.sidebar category:drag
/// Or in Xcode console with: `drag |`
enum SidebarLog {
    static let drag = Logger(subsystem: "com.courier.sidebar", category: "drag")
}
