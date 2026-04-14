import SwiftUI

struct URLBarView: View {
    @Binding var method: String
    @Binding var urlString: String
    var onMethodChange: (String) -> Void
    var onURLChange: (String) -> Void
    var onSend: () -> Void

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    var body: some View {
        HStack(spacing: 8) {
            // Method picker
            Menu {
                ForEach(methods, id: \.self) { m in
                    Button {
                        method = m
                        onMethodChange(m)
                    } label: {
                        Text(m)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    MethodBadge(method: method)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // URL field
            TextField("Enter URL...", text: $urlString)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
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
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
