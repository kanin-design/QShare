import SwiftUI
import AppKit

/// The "looking for devices" mark: arc pairs launched from a central source,
/// expanding outward and fading.
///
/// Used at two sizes — large in the empty discovery card, and small in the
/// Nearby devices header once devices are found and that card is gone. One
/// implementation serves both so they cannot drift apart, but it *adapts*
/// rather than merely shrinking: see `Cascade`.
///
/// # Why this is drawn on layers
///
/// Everything here is pre-drawn once, and only `opacity` and `transform` are
/// animated. Nothing redraws content per frame, and that constraint is the
/// whole design.
///
/// This window is a translucent material over the desktop, so any per-frame
/// redraw invalidates and recomposites it. Measured on the idle Send tab, as a
/// percentage of one CPU core:
///
///   | animation                                            | cost  |
///   |------------------------------------------------------|-------|
///   | SwiftUI `.symbolEffect(.variableColor, .repeating)`   | 5.4%  |
///   | SwiftUI `scaleEffect` + `opacity` on three rings      | 5.5%  |
///   | SwiftUI `opacity` fade on one 20pt glyph              | 5.3%  |
///   | AppKit `NSImageView.addSymbolEffect`                  | 1.8%  |
///   | …the same, at `.speed(0.45)`                          | 1.0%  |
///   | **this, at full size**                                | 0.16% |
///   | **this, at header size**                              | 0.00% |
///   | nothing animating at all                             | 0.10% |
///
/// Two things to take from that. In SwiftUI the cost barely moves with how
/// much is animated — one fading glyph cost the same as three scaling rings —
/// because what costs is the per-frame trip through the view graph, not the
/// drawing. And moving to AppKit is not enough on its own: a symbol effect
/// still re-rasterises the symbol every frame, which is why it only reached
/// 1%. Only once nothing is redrawn does it reach the floor — at which point
/// elaborateness is free, and a rotating gradient costs the same as a still
/// image.
///
/// A well-known SwiftUI trap rather than anything peculiar to this app — see
/// e.g. AuroraView, which hit the same wall animating blurred shapes. If you
/// change this, measure it; reasoning about it has a poor track record.
struct SearchingSymbol: View {
    /// How big to draw it. The geometry derives from the view's bounds, so the
    /// same code serves the empty-state mark and the header one.
    var size = CGSize(width: 58, height: 52)
    /// False when the Send tab isn't the visible one. SwiftUI does not stop an
    /// indefinite animation in a view it isn't drawing, and both tabs stay
    /// mounted so switching between them can't resize the window.
    var isActive: Bool

    var body: some View {
        Cascade(isActive: isActive)
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)   // "Looking for devices…" already says this
    }
}

// MARK: - Shared

private enum Art {
    /// The source dot at the centre of the mark.
    static func dotLayer(radius: CGFloat, centre: CGPoint, tint: NSColor) -> CAShapeLayer {
        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                            width: radius * 2, height: radius * 2),
                          transform: nil)
        dot.fillColor = tint.cgColor
        return dot
    }
}

/// Layer-backed view that draws once and animates properties.
private class AnimatedArtView: NSView {
    var tint: NSColor = .systemBlue { didSet { if tint != oldValue { rebuildAndRestart() } } }
    private(set) var animating = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        rebuildAndRestart()
    }

    func setAnimating(_ on: Bool) {
        guard on != animating else { return }
        animating = on
        if on { addAnimations() } else { removeAnimations() }
    }

    private func rebuildAndRestart() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        build()
        if animating { addAnimations() }
    }

    /// Draw everything once. Subclasses override.
    func build() {}
    /// Attach property animations. Subclasses override.
    func addAnimations() {}

    func removeAnimations() {
        layer?.sublayers?.forEach { $0.removeAllAnimations() }
    }
}

// MARK: - Cascade

/// Arc pairs launched from the centre one after another, growing outward and
/// fading as they go.
///
/// Adapts to the space it is given rather than merely shrinking into it. At
/// full size that is three expanding waves; in a section header there is only
/// about 8pt of radius to work with, and three waves' worth of spacing and
/// travel both fall below the size at which they read as anything. So the
/// compact form drops to the source and a single arc pair lighting in turn,
/// with no expansion — the same idea told with two elements instead of seven.
private struct Cascade: NSViewRepresentable {
    var isActive: Bool

    func makeNSView(context: Context) -> ArtView { ArtView() }
    func updateNSView(_ view: ArtView, context: Context) {
        view.tint = NSColor(Theme.accent)
        view.setAnimating(isActive)
    }

    final class ArtView: AnimatedArtView {
        private var waves: [CALayer] = []
        private var source = CAShapeLayer()
        private var compact = false

        private static let waveCount = 3
        private static let period: CFTimeInterval = 3.1
        /// Below this, there is not enough radius for expanding waves to read.
        private static let compactBelow: CGFloat = 30
        /// Waves are drawn at a fraction of the space available and then scaled
        /// past it, so they carry on travelling outward instead of stopping at
        /// the radius they were drawn at.
        private static let drawnFraction = 0.82
        private static let finalScale = 1.0 / 0.82

        // Compact form.
        private static let compactPeriod: CFTimeInterval = 1.7
        private static let compactStagger = 0.30
        private static let compactRise = 0.07
        private static let compactDecay = 0.42
        /// Kept clearly visible at rest: at this size a part that fades out
        /// entirely just looks like it is missing.
        private static let compactResting: Float = 0.3

        override func build() {
            let centre = CGPoint(x: bounds.midX, y: bounds.midY)
            let extent = min(bounds.width, bounds.height)
            compact = extent < Self.compactBelow

            let outer = extent / 2 - (compact ? 1 : 2)
            guard outer > 0 else { return }
            let radius = compact ? outer : outer * Self.drawnFraction
            let stroke = max(1.0, radius * (compact ? 0.14 : 0.085))
            let span = CGFloat.pi / 4.6            // a touch under ±40°

            func arcPair(at radius: CGFloat) -> CALayer {
                let pair = CALayer()
                pair.frame = bounds
                for mid in [CGFloat(0), CGFloat.pi] {   // right side, then left
                    let arc = CAShapeLayer()
                    let path = CGMutablePath()
                    path.addArc(center: centre, radius: radius,
                                startAngle: mid - span, endAngle: mid + span,
                                clockwise: false, transform: .identity)
                    arc.path = path
                    arc.frame = bounds
                    arc.fillColor = nil
                    arc.strokeColor = tint.cgColor
                    // Kept thin: at full size the layer transform scales the
                    // stroke too, so a wave drawn heavy ends up heavier still
                    // by the time it reaches its widest.
                    arc.lineWidth = stroke
                    arc.lineCap = .round               // soft ends, not cut off
                    pair.addSublayer(arc)
                }
                layer?.addSublayer(pair)
                return pair
            }

            if compact {
                waves = [arcPair(at: radius)]
                waves.forEach { $0.opacity = Self.compactResting }
            } else {
                waves = (0..<Self.waveCount).map { _ in
                    let pair = arcPair(at: radius)
                    pair.opacity = 0
                    return pair
                }
            }

            // The source. Its own layer so it can flash as each wave leaves —
            // the waves then read as being emitted by something, rather than
            // just appearing near the middle.
            source = Art.dotLayer(radius: max(1.3, radius * (compact ? 0.20 : 0.135)),
                                  centre: centre, tint: tint)
            layer?.addSublayer(source)
        }

        override func addAnimations() {
            compact ? addCompactAnimations() : addFullAnimations()
        }

        /// Source and arc pair lighting in turn, no expansion.
        private func addCompactAnimations() {
            let start = CACurrentMediaTime()
            let parts: [CALayer] = [source] + waves

            for (index, part) in parts.enumerated() {
                let onset = Double(index) * Self.compactStagger
                let peak  = min(onset + Self.compactRise, 0.95)
                let done  = min(peak + Self.compactDecay, 0.97)

                // keyTimes must begin at 0 and end at 1, or Core Animation
                // discards the schedule outright — which looks exactly like an
                // animation with no fade rather than like an error.
                let pulse = CAKeyframeAnimation(keyPath: "opacity")
                pulse.values   = [Self.compactResting, Self.compactResting,
                                  1, Self.compactResting, Self.compactResting]
                pulse.keyTimes = [0,
                                  NSNumber(value: onset),
                                  NSNumber(value: peak),
                                  NSNumber(value: done),
                                  1]
                pulse.timingFunctions = [
                    CAMediaTimingFunction(name: .linear),
                    CAMediaTimingFunction(name: .easeOut),
                    CAMediaTimingFunction(name: .linear),
                    CAMediaTimingFunction(name: .linear)
                ]
                pulse.duration = Self.compactPeriod
                pulse.beginTime = start
                pulse.repeatCount = .greatestFiniteMagnitude
                part.add(pulse, forKey: "radiate")
            }
        }

        /// Three waves launched from the centre, expanding and fading.
        private func addFullAnimations() {
            let start = CACurrentMediaTime()
            for (index, wave) in waves.enumerated() {
                let grow = CABasicAnimation(keyPath: "transform.scale")
                // Starts tight to the dot, so there is as much travel as the
                // space allows before it fades.
                grow.fromValue = 0.16
                grow.toValue = Self.finalScale

                // Full strength at the peak — capping it below 1 just makes the
                // accent colour read as a washed-out version of itself. Most of
                // that brightness is then held well past halfway before
                // dropping away, so the wave is still clearly visible as it
                // reaches its widest.
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values   = [0.0, 1.0, 0.72, 0.0]
                fade.keyTimes = [0, 0.16, 0.62, 1]

                let group = CAAnimationGroup()
                group.animations = [grow, fade]
                group.duration = Self.period
                group.beginTime = start + Double(index) * Self.period / Double(Self.waveCount)
                group.repeatCount = .greatestFiniteMagnitude
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                group.fillMode = .backwards
                wave.add(group, forKey: "cascade")
            }

            // One flash per wave, on the beat each one leaves. Short, and never
            // all the way down — the source should read as steady and pulsing,
            // not as blinking on and off.
            let flash = CAKeyframeAnimation(keyPath: "opacity")
            flash.values   = [1.0, 0.62, 1.0]
            flash.keyTimes = [0, 0.22, 1]
            flash.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeInEaseOut)
            ]
            flash.duration = Self.period / Double(Self.waveCount)
            flash.beginTime = start
            flash.repeatCount = .greatestFiniteMagnitude
            source.add(flash, forKey: "emit")
        }

        override func removeAnimations() {
            super.removeAnimations()
            source.opacity = 1
            waves.forEach { $0.opacity = compact ? 1 : 0 }
        }
    }
}
