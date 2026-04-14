import SwiftUI

// MARK: - Hover Button Sizes

enum HoverButtonSize {
    case small, regular, large

    var dimension: CGFloat {
        switch self {
        case .small: return 24
        case .regular: return 28
        case .large: return 32
        }
    }

    var symbolSize: CGFloat {
        switch self {
        case .small: return 12
        case .regular: return 14
        case .large: return 16
        }
    }
}

// MARK: - Button Styles

struct HoverButtonStyle: ButtonStyle {
    let size: HoverButtonSize
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size.dimension, height: size.dimension)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(
                        configuration.isPressed ? 0.15 :
                        isHovered ? 0.08 : 0
                    ))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension ButtonStyle where Self == HoverButtonStyle {
    static func courierHover(size: HoverButtonSize = .regular) -> HoverButtonStyle {
        HoverButtonStyle(size: size)
    }
}

struct HoverTextButtonStyle: ButtonStyle {
    let size: HoverButtonSize
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(height: size.dimension)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(
                        configuration.isPressed ? 0.15 :
                        isHovered ? 0.08 : 0
                    ))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension ButtonStyle where Self == HoverTextButtonStyle {
    static func courierHoverText(size: HoverButtonSize = .regular) -> HoverTextButtonStyle {
        HoverTextButtonStyle(size: size)
    }
}

struct HoverMenuStyle: MenuStyle {
    let size: HoverButtonSize
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: size.dimension, height: size.dimension)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension MenuStyle where Self == HoverMenuStyle {
    static func courierHover(size: HoverButtonSize = .regular) -> HoverMenuStyle {
        HoverMenuStyle(size: size)
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    init(material: NSVisualEffectView.Material = .sidebar, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Color Extensions

extension Color {
    static let courierAccent = Color.accentColor
    static let courierSecondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let courierTertiaryLabel = Color(nsColor: .tertiaryLabelColor)
    static let courierSeparator = Color(nsColor: .separatorColor)
    static let courierControlBackground = Color(nsColor: .controlBackgroundColor)
    static let courierWindowBackground = Color(nsColor: .windowBackgroundColor)

    static let courierCardSurface = Color(nsColor: .controlBackgroundColor)
}

// MARK: - Content Card Constants

enum ContentCardMetrics {
    static let cornerRadius: CGFloat = 10
    static let padding: CGFloat = 10
    static let tabBarHeight: CGFloat = 36
}

// MARK: - View Extensions

extension View {
    func formGroupBackground() -> some View {
        self.background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        }
    }
}
