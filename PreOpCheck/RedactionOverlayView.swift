//
//  RedactionOverlayView.swift
//  PreOpCheck
//
//  Blurs the lines of a scanned page that identify the patient. One frosted
//  bar per line, sitting between the camera picture and the drug markers.
//
//  Bars glide rather than jump: a new rect is paired with the existing bar it
//  overlaps and that bar animates to the new place. Bars appear on first
//  sighting and linger for `hold` after the line was last seen, because a
//  bar that blinks off for one frame shows the name. The view only ever sees
//  rectangles; it never learns what the text said.
//

import UIKit

final class RedactionOverlayView: UIView {

    private final class Bar {
        let view: UIVisualEffectView
        var lastSeen: Date
        init(view: UIVisualEffectView, lastSeen: Date) {
            self.view = view
            self.lastSeen = lastSeen
        }
    }

    private var bars: [Bar] = []

    /// How long a bar stays after its line was last seen. Longer than the
    /// drug markers' hold on purpose: a lingering bar is harmless.
    private let hold: TimeInterval = 1.5
    private let glide: TimeInterval = 0.18
    private let blur = UIBlurEffect(style: .systemThinMaterial)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `lines` are the identifying text lines, in this view's coordinates.
    func update(with lines: [CGRect]) {
        let now = Date()
        var unpaired = bars
        var moves: [(bar: Bar, rect: CGRect)] = []
        var fresh: [CGRect] = []

        for rect in lines.map(RedactionOverlayView.barRect) {
            if let i = unpaired.firstIndex(where: { $0.view.frame.intersects(rect) }) {
                let bar = unpaired.remove(at: i)
                bar.lastSeen = now
                moves.append((bar, rect))
            } else {
                fresh.append(rect)
            }
        }

        UIView.animate(withDuration: glide, delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState]) {
            for move in moves {
                move.bar.view.frame = move.rect
                move.bar.view.layer.cornerRadius = RedactionOverlayView.cornerRadius(for: move.rect)
            }
        }

        for rect in fresh {
            bars.append(makeBar(at: rect, now: now))
        }

        for bar in unpaired where now.timeIntervalSince(bar.lastSeen) > hold {
            remove(bar, animated: true)
        }
    }

    func clear() {
        for bar in bars {
            bar.view.removeFromSuperview()
        }
        bars.removeAll()
    }

    // MARK: Bars

    private func makeBar(at rect: CGRect, now: Date) -> Bar {
        let view = UIVisualEffectView(effect: nil)
        view.frame = rect
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = RedactionOverlayView.cornerRadius(for: rect)
        view.contentView.backgroundColor = .redactionTint
        addSubview(view)

        // Fading the effect in is the supported way to animate a blur;
        // animating the view's alpha is not.
        UIView.animate(withDuration: 0.12) {
            view.effect = self.blur
        }
        return Bar(view: view, lastSeen: now)
    }

    private func remove(_ bar: Bar, animated: Bool) {
        bars.removeAll { $0 === bar }
        guard animated else {
            bar.view.removeFromSuperview()
            return
        }
        UIView.animate(withDuration: glide, animations: {
            bar.view.effect = nil
            bar.view.contentView.backgroundColor = .clear
        }, completion: { _ in
            bar.view.removeFromSuperview()
        })
    }

    /// A little room around the text so the letters' edges are covered too.
    private static func barRect(_ line: CGRect) -> CGRect {
        line.insetBy(dx: -line.height * 0.35, dy: -line.height * 0.25)
    }

    private static func cornerRadius(for rect: CGRect) -> CGFloat {
        min(10, rect.height * 0.3)
    }
}
