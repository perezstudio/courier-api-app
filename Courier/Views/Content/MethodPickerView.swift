import AppKit
import SwiftUI

/// SwiftUI wrapper around an AppKit method picker.
/// Renders a button styled like the URL field, tinted by the method color,
/// and presents a real NSMenu when clicked.
struct MethodPickerView: NSViewRepresentable {
    @Binding var method: String
    var onMethodChange: (String) -> Void

    func makeNSView(context: Context) -> MethodPickerNSView {
        let view = MethodPickerNSView()
        view.onMethodChange = { newMethod in
            method = newMethod
            onMethodChange(newMethod)
        }
        view.method = method
        return view
    }

    func updateNSView(_ nsView: MethodPickerNSView, context: Context) {
        nsView.method = method
    }
}

final class MethodPickerNSView: NSView {
    var method: String = "GET" {
        didSet {
            guard method != oldValue else { return }
            updateLabel(animated: true)
            invalidateIntrinsicContentSize()
            updateBackground(animated: true)
        }
    }

    var onMethodChange: ((String) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { updateBackground(animated: true) } }
    private var isPressed = false { didSet { updateBackground(animated: true) } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        setupSubviews()
        updateLabel(animated: false)
        updateBackground(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: NSSize {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let textWidth = (method.uppercased() as NSString)
            .size(withAttributes: [.font: font]).width
        // text + 4pt gap + 8pt chevron + 8pt left + 8pt right
        return NSSize(width: ceil(textWidth) + 4 + 8 + 16, height: 30)
    }

    private func setupSubviews() {
        label.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        // Layer-backed so we can crossfade the text on method change
        label.wantsLayer = true

        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 8, weight: .regular)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func updateLabel(animated: Bool) {
        if animated, let labelLayer = label.layer {
            let transition = CATransition()
            transition.duration = 0.18
            transition.type = .fade
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            labelLayer.add(transition, forKey: "fade")
        }
        label.stringValue = method.uppercased()
        label.textColor = HTTPMethod.color(for: method)
    }

    private func updateBackground(animated: Bool) {
        let methodColor = HTTPMethod.color(for: method)
        let baseOpacity: CGFloat = 0.12
        let hoverBoost: CGFloat = isPressed ? 0.10 : isHovered ? 0.05 : 0
        let newColor = methodColor.withAlphaComponent(baseOpacity + hoverBoost).cgColor

        if animated, let viewLayer = layer {
            let anim = CABasicAnimation(keyPath: "backgroundColor")
            anim.fromValue = viewLayer.backgroundColor
            anim.toValue = newColor
            anim.duration = 0.15
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            viewLayer.add(anim, forKey: "bg")
        }
        layer?.backgroundColor = newColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; isPressed = false }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        showMenu()
        isPressed = false
    }

    private func showMenu() {
        let menu = NSMenu()
        for m in HTTPMethod.all {
            let item = NSMenuItem(
                title: m,
                action: #selector(menuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = m
            if m == method.uppercased() {
                item.state = .on
            }
            // Color swatch for visual cue
            let swatch = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
                HTTPMethod.color(for: m).setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
            item.image = swatch
            menu.addItem(item)
        }
        // Pop up directly below the button, aligned to the leading edge
        let origin = NSPoint(x: 0, y: bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: self)
    }

    @objc private func menuItemSelected(_ sender: NSMenuItem) {
        guard let newMethod = sender.representedObject as? String else { return }
        method = newMethod
        onMethodChange?(newMethod)
    }
}
