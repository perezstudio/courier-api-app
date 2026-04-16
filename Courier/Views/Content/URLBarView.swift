import SwiftUI

struct URLBarView: View {
    @Binding var method: String
    @Binding var urlString: String
    var onMethodChange: (String) -> Void
    var onURLChange: (String) -> Void
    var onSend: () -> Void

    @State private var isURLHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Method picker — AppKit-backed, opens NSMenu
            MethodPickerView(method: $method, onMethodChange: onMethodChange)
                .fixedSize()
                .frame(height: 30)

            // URL field
            TextField("Enter URL...", text: $urlString)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isURLHovered ? 0.08 : 0.05))
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isURLHovered = hovering
                    }
                }
                .onSubmit {
                    onURLChange(urlString)
                    onSend()
                }

            // Send button
            Button {
                onURLChange(urlString)
                onSend()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SendButtonStyle())
        }
    }
}

/// Filled accent button with hover/press feedback. Hit area covers full frame.
private struct SendButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(
                        configuration.isPressed ? 0.75 :
                        isHovered ? 0.85 : 1.0
                    ))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}
