import AppKit
import SwiftUI
import simd

// MARK: - Mood

/// What the mark is reacting to. The ribbon is the window's only ornament, so it reports the
/// same state the rest of the window reports: quiet at rest, alert while Photoshop is answering,
/// settled once a script is ready, loose when the selection cannot produce one, and lit for a
/// moment after a copy.
enum RibbonMood: Equatable {
    case idle
    case working
    case armed
    case unsettled
    case delivered
}

/// The dial positions one mood asks for. Blending two tempers is how the mark changes its mind
/// without a cut. Every rate here is deliberately slow: the mark should read as drifting, not
/// spinning.
struct RibbonTemper {
    /// Radians per second of turn. A full lap at 0.09 takes about seventy seconds.
    var spin: Double
    /// Radians of turn between the first loop in the family and the last. This is what opens
    /// the stack into a rosette instead of a single traced line.
    var spread: Double
    /// How far each loop lifts out of its own plane, as a fraction of the loop's own short axis.
    /// A warp, not a stack: every loop stays centred on the axis. Measuring it against the short
    /// axis is what stops it smearing the void shut on the narrower signatures.
    var swell: Double
    /// How much of the signature's finer harmonics survive.
    var order: Double
    /// How many of the in-between strands are drawn, as an opacity, so density can change
    /// without a strand ever popping into existence.
    var weave: Double
    var bloom: Double
    var tint: Double
    var scan: Double

    static func blend(_ from: RibbonTemper, _ to: RibbonTemper, _ amount: Double) -> RibbonTemper {
        RibbonTemper(
            spin: mix(from.spin, to.spin, amount),
            spread: mix(from.spread, to.spread, amount),
            swell: mix(from.swell, to.swell, amount),
            order: mix(from.order, to.order, amount),
            weave: mix(from.weave, to.weave, amount),
            bloom: mix(from.bloom, to.bloom, amount),
            tint: mix(from.tint, to.tint, amount),
            scan: mix(from.scan, to.scan, amount)
        )
    }
}

extension RibbonMood {
    var temper: RibbonTemper {
        switch self {
        case .idle:
            return RibbonTemper(spin: 0.070, spread: 1.90, swell: 0.62, order: 0.86, weave: 0.58, bloom: 0.50, tint: 0, scan: 0)
        case .working:
            return RibbonTemper(spin: 0.165, spread: 2.30, swell: 0.48, order: 1.00, weave: 1.00, bloom: 0.72, tint: 0.30, scan: 1)
        case .armed:
            return RibbonTemper(spin: 0.088, spread: 2.02, swell: 0.72, order: 1.00, weave: 1.00, bloom: 0.82, tint: 0, scan: 0)
        case .unsettled:
            return RibbonTemper(spin: 0.038, spread: 0.95, swell: 0.30, order: 0.70, weave: 0.14, bloom: 0.12, tint: 0.50, scan: 0)
        case .delivered:
            return RibbonTemper(spin: 0.112, spread: 2.14, swell: 0.80, order: 1.00, weave: 1.00, bloom: 1.00, tint: 0.30, scan: 0)
        }
    }

    /// Which of the app's own colors the strands borrow while it is in this mood.
    var accent: KeyPath<RibbonPalette, RibbonRGB> {
        switch self {
        case .working: return \.signal
        case .delivered: return \.applause
        case .unsettled: return \.doubt
        case .idle, .armed: return \.copper
        }
    }
}

// MARK: - Color

/// Straight sRGB components. The strands are tinted per depth layer, and `Color` cannot be read
/// back or mixed on macOS 13, so the ribbon resolves the app's palette to numbers and does its
/// own arithmetic.
struct RibbonRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static func mix(_ from: RibbonRGB, _ to: RibbonRGB, _ amount: Double) -> RibbonRGB {
        let clamped = min(1, max(0, amount))
        return RibbonRGB(
            red: from.red + (to.red - from.red) * clamped,
            green: from.green + (to.green - from.green) * clamped,
            blue: from.blue + (to.blue - from.blue) * clamped
        )
    }

    func color(opacity: Double = 1) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: min(1, max(0, opacity)))
    }
}

struct RibbonPalette {
    var copper: RibbonRGB
    var ember: RibbonRGB
    var highlight: RibbonRGB
    var haze: RibbonRGB
    var signal: RibbonRGB
    var applause: RibbonRGB
    var doubt: RibbonRGB

    /// The two tones the mark owns. Everything else is borrowed from `PickerStyle` so the ribbon
    /// cannot drift away from the window it sits in.
    private static let highlightColor = PickerStyle.adaptive(light: 0xF6D6BE, dark: 0xFFEBD9)
    /// What a strand fades toward as it goes behind the form. Sits just off the surface it is
    /// drawn on, so distance reads without any strand disappearing outright.
    private static let hazeColor = PickerStyle.adaptive(light: 0xCFC7BA, dark: 0x2A2320)

    @MainActor
    static func resolved(scheme: ColorScheme, contrast: ColorSchemeContrast) -> RibbonPalette {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        var palette = RibbonPalette(
            copper: .init(red: 0.68, green: 0.28, blue: 0.17),
            ember: .init(red: 0.63, green: 0.30, blue: 0.19),
            highlight: .init(red: 0.96, green: 0.84, blue: 0.75),
            haze: .init(red: 0.81, green: 0.78, blue: 0.73),
            signal: .init(red: 0.19, green: 0.40, blue: 0.42),
            applause: .init(red: 0.23, green: 0.44, blue: 0.36),
            doubt: .init(red: 0.44, green: 0.44, blue: 0.43)
        )
        appearance.performAsCurrentDrawingAppearance {
            palette = RibbonPalette(
                copper: components(PickerStyle.accent),
                ember: components(PickerStyle.string),
                highlight: components(highlightColor),
                haze: components(hazeColor),
                signal: components(PickerStyle.keyword),
                applause: components(PickerStyle.success),
                doubt: components(PickerStyle.secondary)
            )
        }
        guard contrast == .increased else { return palette }
        // Increased contrast wants the far strands to stop receding rather than the near ones to
        // get brighter.
        palette.haze = RibbonRGB.mix(palette.haze, palette.copper, 0.55)
        return palette
    }

    private static func components(_ color: Color) -> RibbonRGB {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return RibbonRGB(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent)
        )
    }
}

// MARK: - Signature

/// A closed space curve written as a four-term Fourier series, seeded by the action reference the
/// copied script will name. Every coefficient is a plain number, so two signatures blend into
/// another closed curve: the mark can rewrite itself between actions without tearing open.
struct RibbonSignature {
    struct Harmonic {
        var amplitude: SIMD3<Double>
        var phase: SIMD3<Double>
    }

    var harmonics: [Harmonic]
    /// How much the loops through the middle of the family swell past the ones at either end.
    var bulge: Double
    /// Where the out-of-plane warp starts, so no two marks twist the same way.
    var wavePhase: Double
    var tilt: Double

    static let harmonicCount = 4

    /// The loop's short axis. The void at the centre of the mark is the disc this leaves empty,
    /// so the warp has to be measured against it.
    var minor: Double { harmonics[0].amplitude.y }

    /// Position on the curve. The first harmonic is a unit circle; the rest give the mark the
    /// character that makes one action's ribbon recognisably not another's.
    func point(at theta: Double, order: Double) -> SIMD3<Double> {
        var point = SIMD3<Double>.zero
        for index in harmonics.indices {
            let harmonic = harmonics[index]
            let angle = Double(index + 1) * theta
            let weight = index == 0 ? 1 : order
            point += harmonic.amplitude * weight * SIMD3(
                cos(angle + harmonic.phase.x),
                cos(angle + harmonic.phase.y),
                cos(angle + harmonic.phase.z)
            )
        }
        return point
    }

    func tangent(at theta: Double, order: Double) -> SIMD3<Double> {
        var slope = SIMD3<Double>.zero
        for index in harmonics.indices {
            let harmonic = harmonics[index]
            let rank = Double(index + 1)
            let angle = rank * theta
            let weight = (index == 0 ? 1 : order) * rank
            slope -= harmonic.amplitude * weight * SIMD3(
                sin(angle + harmonic.phase.x),
                sin(angle + harmonic.phase.y),
                sin(angle + harmonic.phase.z)
            )
        }
        return slope
    }

    static func blend(_ from: RibbonSignature, _ to: RibbonSignature, _ amount: Double) -> RibbonSignature {
        guard amount > 0 else { return from }
        guard amount < 1 else { return to }
        let harmonics = (0..<harmonicCount).map { index -> Harmonic in
            let left = from.harmonics[index]
            let right = to.harmonics[index]
            return Harmonic(
                amplitude: SIMD3(
                    mix(left.amplitude.x, right.amplitude.x, amount),
                    mix(left.amplitude.y, right.amplitude.y, amount),
                    mix(left.amplitude.z, right.amplitude.z, amount)
                ),
                phase: SIMD3(
                    mixAngle(left.phase.x, right.phase.x, amount),
                    mixAngle(left.phase.y, right.phase.y, amount),
                    mixAngle(left.phase.z, right.phase.z, amount)
                )
            )
        }
        return RibbonSignature(
            harmonics: harmonics,
            bulge: mix(from.bulge, to.bulge, amount),
            wavePhase: mixAngle(from.wavePhase, to.wavePhase, amount),
            tilt: mixAngle(from.tilt, to.tilt, amount)
        )
    }

    /// A stable hash. `Hasher` is seeded per process, and a mark that changed every launch would
    /// stop being a fingerprint.
    static func signature(for token: String) -> RibbonSignature {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in token.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        var source = RibbonEntropy(seed: hash)
        // An elongated first harmonic, not a circle. Turning a circle in its own plane leaves
        // it exactly where it was, and the whole family would collapse onto one loop.
        let first = Harmonic(
            amplitude: SIMD3(1, source.between(0.30, 0.48), source.between(0.02, 0.06)),
            phase: SIMD3(0, -.pi / 2, source.angle())
        )
        let second = Harmonic(
            amplitude: SIMD3(source.between(0.04, 0.13), source.between(0.03, 0.10), source.between(0.01, 0.05)),
            phase: SIMD3(source.angle(), source.angle(), source.angle())
        )
        let third = Harmonic(
            amplitude: SIMD3(source.between(0.02, 0.07), source.between(0.02, 0.06), source.between(0.01, 0.04)),
            phase: SIMD3(source.angle(), source.angle(), source.angle())
        )
        let fourth = Harmonic(
            amplitude: SIMD3(source.between(0.01, 0.04), source.between(0.01, 0.03), source.between(0.00, 0.02)),
            phase: SIMD3(source.angle(), source.angle(), source.angle())
        )
        return RibbonSignature(
            harmonics: [first, second, third, fourth],
            bulge: source.between(0.22, 0.52),
            wavePhase: source.angle(),
            tilt: source.angle()
        )
    }
}

/// SplitMix64. Small, deterministic, and good enough that neighbouring action names do not
/// produce neighbouring marks.
private struct RibbonEntropy {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func unit() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed = mixed ^ (mixed >> 31)
        return Double(mixed >> 11) / Double(UInt64(1) << 53)
    }

    mutating func between(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }
    mutating func angle() -> Double { unit() * 2 * .pi }
}

private func mix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
    from + (to - from) * min(1, max(0, amount))
}

/// Phases are angles. Interpolating 0.1 to 6.2 the long way round would spin the whole harmonic
/// backwards through a full turn.
private func mixAngle(_ from: Double, _ to: Double, _ amount: Double) -> Double {
    var delta = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
    if delta > .pi { delta -= 2 * .pi }
    if delta < -.pi { delta += 2 * .pi }
    return from + delta * min(1, max(0, amount))
}

// MARK: - Drawing

/// One sample of the base loop, in object space, with the light value that belongs to that point
/// of the lap. Every strand in the family reuses these; a strand differs only by how far round
/// its own axis it has been turned and how high up the family it sits.
private struct RibbonSample {
    var point: SIMD3<Double>
    var theta: Double
    var glint: Double
}

private struct RibbonDrawing: View, Animatable {
    var signature: RibbonSignature
    var temper: RibbonTemper
    var accent: RibbonRGB
    var celebration: Double
    var burstAge: Double
    var yaw: Double
    var clock: Double
    var still: Bool
    var palette: RibbonPalette
    var pointer: CGSize

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(pointer.width, pointer.height) }
        set { pointer = CGSize(width: newValue.first, height: newValue.second) }
    }

    private static let focal = 5.2
    /// Depth layers. Every strand is cut at these boundaries so the far side of the family can be
    /// drawn first and dimmer, which is what a flat wireframe never gets to do.
    private static let layers = 8

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard size.width > 8, size.height > 8 else { return }
            // Strand count follows the room available, not just the width. Packing a large
            // family into a short sidebar chip turns the moiré to mud.
            let extent = min(size.width, size.height * 1.7)
            let samples = max(52, min(100, Int(extent * 0.40)))
            let strands = max(15, min(40, Int(extent * 0.13)))
            draw(sweep(samples: samples), strands: strands, into: &context, size: size)
        }
    }

    // MARK: Geometry

    /// The base loop, normalised so every signature fills the same frame. The mark is this one
    /// loop drawn many times over, each copy turned a little further round and raised a little
    /// higher — a stack of loops whose envelope is the form you actually read.
    private func sweep(samples: Int) -> [RibbonSample] {
        var reach = 0.0001
        var points = [SIMD3<Double>](repeating: .zero, count: samples)
        for index in 0..<samples {
            let theta = 2 * .pi * Double(index) / Double(samples)
            let point = signature.point(at: theta, order: temper.order)
            points[index] = point
            reach = max(reach, simd_length(point))
        }
        let scale = 1 / reach
        return (0..<samples).map { index in
            let theta = 2 * .pi * Double(index) / Double(samples)
            return RibbonSample(point: points[index] * scale, theta: theta, glint: glint(at: theta))
        }
    }

    // MARK: Painting

    private func draw(_ samples: [RibbonSample], strands: Int, into context: inout GraphicsContext, size: CGSize) {
        let count = samples.count
        guard count > 3, strands > 2 else { return }

        let pitch = 0.60 + sin(clock * 0.079) * 0.09 + Double(pointer.height)
        let cosPitch = cos(pitch), sinPitch = sin(pitch)
        let swell = temper.swell * signature.minor * (1 + celebration * 0.08)
        let widest = 1 + signature.bulge

        // How far the family reaches, measured off the loop itself rather than off the outline it
        // happens to be casting. Fitting to the outline would make the mark swell and shrink
        // through every turn; this holds still.
        var radial = 0.0001
        var vertical = 0.0001
        for sample in samples {
            let across = sample.point.y * widest
            radial = max(radial, (sample.point.x * sample.point.x + across * across).squareRoot())
            vertical = max(vertical, abs(sample.point.z))
        }
        vertical += swell
        // Nearness taken partway in rather than at the closest point: the widest part of the
        // family is never also the nearest, and pairing the two extremes left the mark sitting a
        // fifth smaller than its frame.
        let nearest = Self.focal / max(0.9, Self.focal - 0.55 * (radial * sinPitch + vertical * cosPitch))
        let scale = min(
            size.width * 0.97 / (2 * radial * nearest),
            size.height * 0.97 / (2 * (radial * abs(cosPitch) + vertical * abs(sinPitch)) * nearest)
        )
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        let span = max(0.0001, radial * abs(sinPitch) + vertical * abs(cosPitch))

        // Every strand is chopped at the depth boundaries as it is traced, so one stroke per
        // layer draws the whole family at the right distance.
        var carried = [Path](repeating: Path(), count: Self.layers)
        var filling = [Path](repeating: Path(), count: Self.layers)
        var flare = Path()
        var spark = Path()

        for strand in 0..<strands {
            let along = Double(strand) / Double(strands - 1)
            let lean = yaw + signature.tilt + Double(pointer.width) + (along - 0.5) * temper.spread
            // Every loop is warped out of its own plane by a sine whose phase walks across the
            // family. Lifting the loops bodily instead would fill in the middle of the mark; this
            // twists them past each other and leaves the void.
            let warp = along * .pi + signature.wavePhase
            let cosWarp = swell * cos(warp), sinWarp = swell * sin(warp)
            // The loops through the middle of the family run wider than the ones at either end,
            // which is what gives the form its waist.
            let girth = 1 + signature.bulge * sin(.pi * along)
            let cosLean = cos(lean), sinLean = sin(lean)
            // Alternating strands fade as a group, so the family can thin out without a strand
            // ever blinking in or out.
            let odd = strand % 2 == 1

            var previous = CGPoint.zero
            var previousLayer = -1
            for step in 0...count {
                let sample = samples[step % count]
                let across = sample.point.y * girth
                let flat = SIMD2(
                    sample.point.x * cosLean - across * sinLean,
                    sample.point.x * sinLean + across * cosLean
                )
                let lifted = sample.point.z + sinWarp * cos(sample.theta) + cosWarp * sin(sample.theta)
                let depth = flat.y * sinPitch + lifted * cosPitch
                let nearness = Self.focal / max(0.9, Self.focal - depth)
                let screen = CGPoint(
                    x: middle.x + flat.x * nearness * scale,
                    y: middle.y - (flat.y * cosPitch - lifted * sinPitch) * nearness * scale
                )
                let slot = Int(min(Double(Self.layers - 1), max(0, (depth + span) / (2 * span) * Double(Self.layers))))
                if previousLayer >= 0 {
                    let target = min(slot, previousLayer)
                    if odd {
                        filling[target].move(to: previous)
                        filling[target].addLine(to: screen)
                    } else {
                        carried[target].move(to: previous)
                        carried[target].addLine(to: screen)
                    }
                    if sample.glint > 0.55 {
                        flare.move(to: previous)
                        flare.addLine(to: screen)
                    } else if sample.glint > 0.20 {
                        spark.move(to: previous)
                        spark.addLine(to: screen)
                    }
                }
                previous = screen
                previousLayer = slot
            }
        }

        let drift = sin(clock * 0.061)
        for index in 0..<Self.layers {
            let depth = (Double(index) + 0.5) / Double(Self.layers)
            let tone = RibbonRGB.mix(palette.copper, accent, temper.tint)
            let near = RibbonRGB.mix(palette.haze, tone, 0.26 + 0.74 * depth)
            let warm = RibbonRGB.mix(palette.haze, palette.ember, 0.22 + 0.78 * depth)
            let lit = RibbonRGB.mix(near, palette.highlight, 0.34 * depth)
            let strength = 0.16 + 0.55 * depth
            let weight = 0.42 + 0.30 * depth

            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [
                    warm.color(opacity: strength * 0.72),
                    near.color(opacity: strength),
                    lit.color(opacity: strength * 0.9)
                ]),
                startPoint: CGPoint(x: size.width * 0.06, y: size.height * (0.5 + 0.36 * drift)),
                endPoint: CGPoint(x: size.width * 0.96, y: size.height * (0.5 - 0.36 * drift))
            )
            // A wide, very faint pass under the near layers. Copper this fine still throws a
            // little light onto the paper behind it.
            if temper.bloom > 0.05 && depth > 0.5 {
                context.stroke(
                    carried[index],
                    with: .color(near.color(opacity: 0.022 * temper.bloom * depth)),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
            }
            context.stroke(carried[index], with: shading, style: StrokeStyle(lineWidth: weight, lineCap: .round))
            guard temper.weave > 0.02 else { continue }
            context.stroke(
                filling[index],
                with: .color(near.color(opacity: strength * temper.weave)),
                style: StrokeStyle(lineWidth: weight, lineCap: .round)
            )
        }

        // The travelling light, drawn over the family so it reads as something passing across the
        // strands rather than as the strands changing colour.
        let flareColor = RibbonRGB.mix(accent, palette.highlight, 0.55)
        context.stroke(spark, with: .color(flareColor.color(opacity: 0.26)), style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
        context.stroke(flare, with: .color(flareColor.color(opacity: 0.66)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
    }

    /// The travelling highlight: a slow scan while Photoshop is answering, and one wave riding
    /// once around the family on copy.
    private func glint(at theta: Double) -> Double {
        var value = 0.0
        if temper.scan > 0.01 && !still {
            value += temper.scan * peak(theta, at: clock * 1.05, width: 0.5)
        }
        if celebration > 0.01 {
            value += celebration * peak(theta, at: burstAge * 4.2, width: 0.7)
        }
        return min(1, value)
    }

    private func peak(_ theta: Double, at position: Double, width: Double) -> Double {
        var delta = (theta - position).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return exp(-(delta * delta) / (2 * width * width))
    }
}

// MARK: - View

/// The generative mark. Its shape is a fingerprint of the action reference the copied script will
/// name, and its behaviour is the app's own state: only this canvas ticks, and inactive windows
/// and Reduce Motion still it.
struct ScriptRibbon: View {
    var token: String
    var mood: RibbonMood

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var rewrite: Rewrite
    @State private var phase: Phase
    @State private var deliveredAt: Date?
    @State private var pointer = CGSize.zero

    /// How long the mark takes to redraw itself as a different action.
    private static let rewriteDuration = 1.5
    /// How long a change of mood takes to arrive.
    private static let settleDuration = 0.9
    /// Reduce Motion still needs a pose. This one shows the twist and both waists of the weave.
    private static let stillClock = 11.4

    init(token: String = "", mood: RibbonMood = .idle) {
        self.token = token
        self.mood = mood
        let signature = RibbonSignature.signature(for: token)
        _rewrite = State(initialValue: Rewrite(from: signature, to: signature, start: .distantPast))
        _phase = State(initialValue: Phase(
            from: mood.temper,
            fromAccent: mood.accent,
            to: mood.temper,
            toAccent: mood.accent,
            start: Date(),
            yaw: 0
        ))
    }

    var body: some View {
        let palette = RibbonPalette.resolved(scheme: colorScheme, contrast: contrast)
        GeometryReader { proxy in
            content(palette: palette, bounds: proxy.size)
        }
        .accessibilityHidden(true)
    }

    private func content(palette: RibbonPalette, bounds: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || activeState == .inactive)) { timeline in
            let now = timeline.date
            let age = deliveredAt.map { now.timeIntervalSince($0) } ?? .infinity
            RibbonDrawing(
                signature: signature(at: now),
                temper: temper(at: now),
                accent: accent(at: now, palette: palette),
                celebration: reduceMotion ? 0 : celebration(age: age),
                burstAge: age,
                yaw: reduceMotion ? 0 : yaw(at: now),
                clock: reduceMotion ? Self.stillClock : now.timeIntervalSinceReferenceDate,
                still: reduceMotion,
                palette: palette,
                pointer: pointer
            )
        }
        .onContinuousHover { hover in
            guard !reduceMotion, bounds.width > 1, bounds.height > 1 else { return }
            switch hover {
            case .active(let point):
                // Parallax, not a pan: the weave leans toward the pointer and no further.
                pointer = CGSize(
                    width: (point.x / bounds.width - 0.5) * 0.30,
                    height: (point.y / bounds.height - 0.5) * -0.22
                )
            case .ended:
                pointer = .zero
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 1.5, dampingFraction: 0.95), value: pointer)
        .onChange(of: token) { newToken in
            let now = Date()
            rewrite = Rewrite(from: signature(at: now), to: .signature(for: newToken), start: now)
        }
        .onChange(of: mood) { newMood in
            let now = Date()
            phase = Phase(
                from: temper(at: now),
                fromAccent: phase.toAccent,
                to: newMood.temper,
                toAccent: newMood.accent,
                start: now,
                yaw: yaw(at: now)
            )
            deliveredAt = newMood == .delivered ? now : nil
        }
    }

    // MARK: State

    private struct Rewrite {
        var from: RibbonSignature
        var to: RibbonSignature
        var start: Date
    }

    private struct Phase {
        var from: RibbonTemper
        var fromAccent: KeyPath<RibbonPalette, RibbonRGB>
        var to: RibbonTemper
        var toAccent: KeyPath<RibbonPalette, RibbonRGB>
        var start: Date
        var yaw: Double
    }

    private func signature(at now: Date) -> RibbonSignature {
        guard !reduceMotion else { return rewrite.to }
        let elapsed = now.timeIntervalSince(rewrite.start) / Self.rewriteDuration
        guard elapsed < 1 else { return rewrite.to }
        let amount = min(1, max(0, elapsed))
        // Smoothstep, not a spring. The mark should arrive at the new action without overshooting
        // past it and settling back.
        return .blend(rewrite.from, rewrite.to, amount * amount * (3 - 2 * amount))
    }

    private func settle(at now: Date) -> Double {
        let amount = min(1, max(0, now.timeIntervalSince(phase.start) / Self.settleDuration))
        return amount * amount * (3 - 2 * amount)
    }

    private func temper(at now: Date) -> RibbonTemper {
        .blend(phase.from, phase.to, settle(at: now))
    }

    private func accent(at now: Date, palette: RibbonPalette) -> RibbonRGB {
        .mix(palette[keyPath: phase.fromAccent], palette[keyPath: phase.toAccent], settle(at: now))
    }

    /// Yaw is integrated rather than multiplied out of the wall clock. Reading the angle as
    /// `time * speed` would snap the mark a quarter of the way around the moment a mood changed
    /// its speed.
    private func yaw(at now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(phase.start))
        let ramp = min(elapsed, Self.settleDuration)
        let from = phase.from.spin, to = phase.to.spin
        let during = from * ramp + (to - from) * ramp * ramp / (2 * Self.settleDuration)
        let after = elapsed > Self.settleDuration ? (elapsed - Self.settleDuration) * to : 0
        return phase.yaw + during + after
    }

    private func celebration(age: Double) -> Double {
        guard age >= 0, age < 3.2 else { return 0 }
        return min(1, age / 0.18) * exp(-max(0, age - 0.18) * 0.95)
    }
}
