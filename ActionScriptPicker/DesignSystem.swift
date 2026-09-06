import AppKit
import SwiftUI

enum PickerStyle {
    static let ink = adaptive(light: 0x292F32, dark: 0xF0EDE7)
    static let secondary = adaptive(light: 0x6F716D, dark: 0xA6ABA7)
    static let paper = adaptive(light: 0xFAF9F5, dark: 0x202423)
    static let sidebar = adaptive(light: 0xEEEDE6, dark: 0x1A1E1D)
    static let panel = adaptive(light: 0xF5F4EF, dark: 0x242927)
    static let editor = adaptive(light: 0xFFFFFF, dark: 0x181D1C)
    static let accent = adaptive(light: 0xAE482C, dark: 0xF0A080)
    static let accentWash = adaptive(light: 0xEDDDCF, dark: 0x3B3029)
    static let rule = adaptive(light: 0xDCDDD5, dark: 0x3A403C)
    static let success = adaptive(light: 0x3B705B, dark: 0x9BC7AC)
    static let keyword = adaptive(light: 0x31676B, dark: 0x8DC5C5)
    static let string = adaptive(light: 0xA24C30, dark: 0xE7AF8E)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255,
                alpha: 1
            )
        })
    }
}

struct Eyebrow: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(PickerStyle.secondary)
    }
}

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(PickerStyle.ink.opacity(0.06), in: Capsule())
            .accessibilityHidden(true)
    }
}

struct PickerMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(
                    colors: [PickerStyle.accent, PickerStyle.accent.opacity(0.82)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            HStack(spacing: size * 0.045) {
                Image(systemName: "chevron.left")
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.23, weight: .bold))
                Image(systemName: "chevron.right")
            }
            .font(.system(size: size * 0.25, weight: .medium))
            .foregroundStyle(PickerStyle.paper)
        }
        .frame(width: size, height: size)
        .shadow(color: PickerStyle.accent.opacity(0.17), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

/// Replays a small entrance without replacing the native text view or its selection.
struct ContentArrival: ViewModifier {
    let trigger: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = true

    func body(content: Content) -> some View {
        content
            .opacity(arrived || reduceMotion ? 1 : 0.35)
            .offset(y: arrived || reduceMotion ? 0 : 6)
            .task(id: trigger) {
                guard !reduceMotion else { arrived = true; return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { arrived = false }
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) { arrived = true }
            }
    }
}

struct PickerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    var prominent = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(prominent && isEnabled ? PickerStyle.paper : PickerStyle.ink)
            .background(
                prominent && isEnabled ? PickerStyle.accent : PickerStyle.ink.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(contrast == .increased ? PickerStyle.ink : PickerStyle.rule.opacity(prominent ? 0 : 0.7))
            }
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, .white.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 44)
                        .rotationEffect(.degrees(18))
                        .offset(x: isHovered ? geometry.size.width + 30 : -65)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: isHovered)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .allowsHitTesting(false)
                .opacity(prominent && isEnabled && !reduceMotion ? 1 : 0)
            }
            .shadow(color: PickerStyle.accent.opacity(prominent && isHovered && isEnabled ? 0.2 : 0), radius: 10, y: 4)
            .offset(y: isHovered && isEnabled && !reduceMotion ? -1 : 0)
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovered)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PickerRowSurface: ViewModifier {
    let selected: Bool
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .foregroundStyle(PickerStyle.ink)
            .background(
                selected ? PickerStyle.accentWash : PickerStyle.ink.opacity(isHovered ? 0.045 : 0),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(PickerStyle.accent.opacity(selected ? 0.22 : 0))
            }
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
    }
}

struct RefreshGlyph: View {
    let isBusy: Bool
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turns = 0.0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(turns))
            .task(id: isBusy && !reduceMotion && activeState != .inactive) {
                guard isBusy, !reduceMotion, activeState != .inactive else { return }
                while !Task.isCancelled {
                    withAnimation(.linear(duration: 0.8)) { turns += 360 }
                    do { try await Task.sleep(nanoseconds: 800_000_000) }
                    catch { return }
                }
            }
    }
}
