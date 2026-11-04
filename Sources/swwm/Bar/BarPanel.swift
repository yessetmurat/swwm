//
//  BarPanel.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// The bar of one display. Never becomes key, so clicking it leaves keyboard
/// focus where it was.
final class BarPanel: NSPanel {

    private let tint = NSView()
    private let left = BarPanel.stack()
    private let right = BarPanel.stack()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit pushes windows below the menu bar's level down out of its way;
    /// the bar must stay at the top edge, under the auto-hidden menu.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // At the menu bar's own level: below it, the (invisible) menu bar window
        // takes every click. The bar steps aside when the menu is revealed
        // (BarController.cursorMoved).
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hasShadow = false
        animationBehavior = .none  // AppKit's default zooms the window; fade() only fades
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        // A plain blur of what is behind plus the tint (radius 30);
        // NSVisualEffectView materials add their own darkening.
        let blur = NSView()
        contentView = blur

        tint.wantsLayer = true
        for v in [tint, left, right] {
            v.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(v)
        }
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            tint.topAnchor.constraint(equalTo: blur.topAnchor),
            tint.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            left.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 10),
            left.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -10),
            right.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -4),
        ])
        orderFrontRegardless()
        Self.setBlurRadius(30, of: windowNumber)
    }

    /// SkyLight's window background blur; private
    /// but needs no SIP change. Missing symbol: no blur, tint only.
    private static func setBlurRadius(_ radius: Int32, of window: Int) {
        typealias SetBlur = @convention(c) (Int32, UInt32, Int32) -> Int32
        _ = SkyLight.symbol("SLSSetWindowBackgroundBlurRadius", as: SetBlur.self)?(SkyLight.connection, UInt32(window), radius)
    }

    private var fadeTimer: Timer?
    private var shown: CGFloat = 1  // 0 hidden ... 1 shown

    /// Fades out (then orders out) or fades in without changing the
    /// frame. Alpha and the blur radius move together: WindowServer draws the
    /// blur regardless of the window's alpha, so a fade of alpha alone would
    /// make the blurred background pop in at once.
    func fade(visible: Bool, since start: Date = Date()) {
        fadeTimer?.invalidate()
        // The macOS menu (layer 24, under the bar) slides away for ~250 ms
        // after the cursor leaves; fading in while it still sits fully in
        // place would be invisible, so start as soon as it starts moving.
        // With a dropdown open the user is still in the menu: keep waiting.
        if visible, !isVisible {
            let (inPlace, dropdown) = menuState()
            if waitForMenu(menuInPlace: inPlace, dropdownOpen: dropdown, waited: Date().timeIntervalSince(start)) {
                fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: false) { [weak self] _ in
                    self?.fade(visible: true, since: start)
                }
                return
            }
        }
        if visible, !isVisible {
            apply(0)
            orderFrontRegardless()
        }
        let target: CGFloat = visible ? 1 : 0
        // 0.05 s each way (3 frames at 60 fps).
        let step: CGFloat = 1 / 3
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            let next = target > self.shown ? min(target, self.shown + step) : max(target, self.shown - step)
            self.apply(next)
            guard next == target else { return }
            timer.invalidate()
            if !visible { self.orderOut(nil) }
        }
        RunLoop.main.add(fadeTimer!, forMode: .common)
    }

    /// Is the macOS menu bar fully in place over this bar, and is a dropdown menu open?
    private func menuState() -> (inPlace: Bool, dropdown: Bool) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let bar = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        let list = WindowServer.onScreen()
        let inPlace = list.contains {
            $0.layer == Int(CGWindowLevelForKey(.mainMenuWindow)) && $0.bounds.intersects(bar) && $0.bounds.minY >= bar.minY
        }
        let dropdown = list.contains { $0.layer == Int(CGWindowLevelForKey(.popUpMenuWindow)) }
        return (inPlace, dropdown)
    }

    private func apply(_ value: CGFloat) {
        shown = value
        alphaValue = value
        Self.setBlurRadius(Int32((30 * value).rounded()), of: windowNumber)
    }

    func render(_ state: BarState, _ status: Status, style: BarStyle, onClick: @escaping (String) -> Void) {
        tint.layer?.backgroundColor = NSColor(argb: style.background).cgColor
        let fg = NSColor(argb: style.foreground)
        let bg = NSColor(argb: style.itemBackground)
        let labelFont = Fonts.font(style.labelFont)

        var leftItems: [NSView] = state.workspaces.map { ws in
            let item = BarItem(text: ws.label, symbol: nil, font: Fonts.font(style.workspaceFont), color: fg,
                               background: ws.active ? bg : .clear)
            item.onClick = { onClick(ws.name) }
            return item
        }
        let app = BarItem(text: state.app, symbol: nil, font: labelFont, color: fg, background: bg, truncates: true)
        leftItems.append(app)

        // On screen, left to right: language, volume, battery, clock (clock at the edge).
        var rightItems: [NSView] = []
        if let lang = status.language {
            rightItems.append(BarItem(text: lang, symbol: nil, font: labelFont, color: fg, background: bg))
        }
        for item in [status.volume, status.battery].compactMap({ $0 }) {
            rightItems.append(BarItem(text: item.text, symbol: item.symbol, font: labelFont, color: fg, background: bg))
        }
        rightItems.append(BarItem(text: status.clock, symbol: nil, font: labelFont, color: fg, background: bg))
        Self.replace(left, with: leftItems)
        Self.replace(right, with: rightItems)
    }

    private static func stack() -> NSStackView {
        let s = NSStackView()
        s.orientation = .horizontal
        s.spacing = 4
        s.alignment = .centerY
        return s
    }

    private static func replace(_ stack: NSStackView, with views: [NSView]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach(stack.addArrangedSubview)
    }
}
