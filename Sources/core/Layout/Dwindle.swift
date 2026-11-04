//
//  Dwindle.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics

/// A Hyprland-style dwindle layout: a binary tree whose leaves are windows.
/// A split's direction comes from its rect at layout time: wider than tall
/// lays children side by side, otherwise stacked.
public final class DwindleTree {

    final class Node {

        var window: WindowID?          // set on leaves
        var first: Node?, second: Node?  // set on splits
        var ratio: CGFloat = 0.5       // first child's share
        weak var parent: Node?

        init(window: WindowID) { self.window = window }
        init(first: Node, second: Node) {
            self.first = first
            self.second = second
            first.parent = self
            second.parent = self
        }

        var leaves: [Node] {
            if window != nil { return [self] }
            return (first?.leaves ?? []) + (second?.leaves ?? [])
        }
    }

    var root: Node?

    public init() {}

    public var windows: [WindowID] { root?.leaves.compactMap(\.window) ?? [] }

    public func contains(_ w: WindowID) -> Bool { leaf(w) != nil }

    func leaf(_ w: WindowID) -> Node? { root?.leaves.first { $0.window == w } }

    /// Splits `target`'s leaf (or the last leaf) in two; `w` takes the second half.
    public func insert(_ w: WindowID, splitting target: WindowID?) {
        guard !contains(w) else { return }
        guard let old = target.flatMap(leaf) ?? root?.leaves.last else {
            root = Node(window: w)
            return
        }
        split(old, adding: Node(window: w), first: false)
    }

    /// Replaces `old` with a split of `old` and `new`; `new` goes first when `first`.
    func split(_ old: Node, adding new: Node, first: Bool) {
        let parent = old.parent
        let wasFirst = parent?.first === old
        let node = first ? Node(first: new, second: old) : Node(first: old, second: new)
        node.parent = parent
        if let parent {
            if wasFirst { parent.first = node } else { parent.second = node }
        } else {
            root = node
        }
    }

    /// The layout without its nodes, kept across restarts.
    public indirect enum Shape: Codable, Equatable, Sendable {

        case window(WindowID)
        case split(ratio: CGFloat, first: Shape, second: Shape)
    }

    public var shape: Shape? {
        func shape(_ n: Node) -> Shape {
            if let w = n.window { return .window(w) }
            return .split(ratio: n.ratio, first: shape(n.first!), second: shape(n.second!))
        }
        return root.map(shape)
    }

    /// Rebuilds the tree as `shape` with the windows it has now: windows the
    /// shape no longer has drop out, windows it lacks are added after it.
    public func restore(_ shape: Shape) {
        let had = windows
        let have = Set(had)
        func build(_ s: Shape) -> Node? {
            switch s {
            case .window(let w):
                return have.contains(w) ? Node(window: w) : nil
            case .split(let ratio, let a, let b):
                switch (build(a), build(b)) {
                case let (x?, y?):
                    let n = Node(first: x, second: y)
                    n.ratio = ratio
                    return n
                case let (x, y):
                    return x ?? y
                }
            }
        }
        root = build(shape)
        root?.parent = nil
        for w in had where !contains(w) { insert(w, splitting: nil) }
    }

    public func remove(_ w: WindowID) {
        guard let node = leaf(w) else { return }
        guard let parent = node.parent else { root = nil; return }
        let sibling = parent.first === node ? parent.second! : parent.first!
        sibling.parent = parent.parent
        if let grand = parent.parent {
            if grand.first === parent { grand.first = sibling } else { grand.second = sibling }
        } else {
            root = sibling
        }
    }

    public func frames(in rect: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
        var out: [WindowID: CGRect] = [:]
        walk(rect, gap: gap) { node, r in
            if let w = node.window { out[w] = r }
        }
        return out
    }

    /// Visits every node with its rect, parents before children.
    func walk(_ rect: CGRect, gap: CGFloat, _ visit: (Node, CGRect) -> Void) {
        func go(_ n: Node, _ r: CGRect) {
            visit(n, r)
            guard let a = n.first, let b = n.second else { return }
            let (ra, rb) = Self.divide(r, ratio: n.ratio, gap: gap)
            go(a, ra)
            go(b, rb)
        }
        if let root { go(root, rect) }
    }

    static func sideBySide(_ r: CGRect) -> Bool { r.width >= r.height }

    static func divide(_ r: CGRect, ratio: CGFloat, gap: CGFloat) -> (CGRect, CGRect) {
        if sideBySide(r) {
            let w = (r.width - gap) * ratio
            return (CGRect(x: r.minX, y: r.minY, width: w, height: r.height),
                    CGRect(x: r.minX + w + gap, y: r.minY, width: r.width - w - gap, height: r.height))
        }
        let h = (r.height - gap) * ratio
        return (CGRect(x: r.minX, y: r.minY, width: r.width, height: h),
                CGRect(x: r.minX, y: r.minY + h + gap, width: r.width, height: r.height - h - gap))
    }
}

extension DwindleTree {

    public func swap(_ a: WindowID, _ b: WindowID) {
        guard let la = leaf(a), let lb = leaf(b) else { return }
        la.window = b
        lb.window = a
    }

    /// Moves `w` into `target`'s cell; `w` goes first if it came from the
    /// left or top of `target`, second otherwise.
    public func warp(_ w: WindowID, onto target: WindowID, from d: Direction) {
        guard w != target, contains(w), contains(target) else { return }
        remove(w)
        split(leaf(target)!, adding: Node(window: w), first: d == .left || d == .up)
    }

    /// `.y` flips side-by-side splits (left/right), `.x` flips stacked ones.
    public func mirror(_ axis: Axis, in rect: CGRect) {
        var flip: [Node] = []
        walk(rect, gap: 0) { n, r in
            if n.window == nil, Self.sideBySide(r) == (axis == .y) { flip.append(n) }
        }
        for n in flip {
            (n.first, n.second) = (n.second, n.first)
            n.ratio = 1 - n.ratio
        }
    }

    public func balance() {
        walk(.zero, gap: 0) { n, _ in n.ratio = 0.5 }
    }

    /// Moves the edge of `w` shared with its nearest sibling on each axis by
    /// `delta`, by changing that split's ratio (clamped to 0.1...0.9).
    public func resize(_ w: WindowID, by delta: CGSize, in rect: CGRect, gap: CGFloat) {
        guard let start = leaf(w) else { return }
        var rects: [ObjectIdentifier: CGRect] = [:]
        walk(rect, gap: gap) { n, r in rects[ObjectIdentifier(n)] = r }

        for (amount, sideBySide) in [(delta.width, true), (delta.height, false)] where amount != 0 {
            var node = start
            while let parent = node.parent {
                let r = rects[ObjectIdentifier(parent)]!
                if Self.sideBySide(r) == sideBySide {
                    let extent = (sideBySide ? r.width : r.height) - gap
                    parent.ratio = min(0.9, max(0.1, parent.ratio + amount / extent))
                    break
                }
                node = parent
            }
        }
    }
}
