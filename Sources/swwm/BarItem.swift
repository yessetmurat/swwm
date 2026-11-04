//
//  BarItem.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// One rounded item: optional SF Symbol, then text; 10pt padding outside,
/// 8pt between icon and text.
final class BarItem: NSView {

    var onClick: (() -> Void)?

    /// Only a `truncates` item gives up width when the bar is short (the app
    /// name); every other label keeps its full size.
    init(text: String, symbol: String?, font: NSFont, color: NSColor, background: NSColor, truncates: Bool = false) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = background.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        if truncates { label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }

        var views: [NSView] = [label]
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let icon = NSImageView(image: image)
            icon.symbolConfiguration = .init(pointSize: font.pointSize, weight: .semibold)
            icon.contentTintColor = color
            views.insert(icon, at: 0)
        }
        let row = NSStackView(views: views)
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if let onClick { onClick() } else { super.mouseDown(with: event) }
    }
}
