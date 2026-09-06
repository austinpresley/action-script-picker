import AppKit
import SwiftUI

struct ScriptPreview: View {
    let script: String
    let didCopy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(PickerStyle.accent)
                Text("AppleScript")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Spacer(minLength: 4)
                Image(systemName: "lock")
                    .font(.system(size: 9))
                Text("Read only")
                    .font(.system(size: 10))
            }
            .foregroundStyle(PickerStyle.secondary)
            .padding(.horizontal, 16)
            .frame(height: 41)
            .background(PickerStyle.panel)

            Rectangle().fill(PickerStyle.rule).frame(height: 1)
                .overlay {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, PickerStyle.accent, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 110, height: 2)
                            .offset(x: -110 + sweep * (geometry.size.width + 110))
                            .opacity(sweep < 1 ? 1 : 0)
                    }
                    .clipped()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }

            SelectableScriptText(text: script)
                .modifier(ContentArrival(trigger: script))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PickerStyle.editor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(didCopy ? PickerStyle.success : PickerStyle.rule, lineWidth: didCopy ? 1.5 : 1)
        }
        .overlay {
            if didCopy && !reduceMotion { CopyTrace() }
        }
        .overlay(alignment: .bottomTrailing) {
            if didCopy {
                CopiedSeal()
                    .padding(18)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)),
                        removal: .opacity.combined(with: .offset(y: -8))
                    ))
            }
        }
        .shadow(color: .black.opacity(0.025), radius: 12, y: 5)
        .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.8), value: didCopy)
        .task(id: script) {
            guard !reduceMotion else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { sweep = 0 }
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.9)) { sweep = 1 }
        }
    }
}

private struct CopyTrace: View {
    @State private var progress = 0.0

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .trim(from: 0, to: progress)
            .stroke(PickerStyle.success, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .onAppear { withAnimation(.easeOut(duration: 0.7)) { progress = 1 } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct CopiedSeal: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(PickerStyle.success.opacity(0.12))
                Path { path in
                    path.move(to: CGPoint(x: 8, y: 14))
                    path.addLine(to: CGPoint(x: 12, y: 18))
                    path.addLine(to: CGPoint(x: 20, y: 10))
                }
                .trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
                .stroke(PickerStyle.success, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 28, height: 28)
            Text("Copied to clipboard")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PickerStyle.ink)
        }
        .padding(10)
        .background(PickerStyle.paper, in: RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(PickerStyle.success.opacity(0.3)) }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.15)) { drawn = true } }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

private struct SelectableScriptText: NSViewRepresentable {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor(PickerStyle.ink)
        textView.textContainerInset = NSSize(width: 16, height: 18)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.setAccessibilityLabel(String(localized: "Generated AppleScript preview"))
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let appearanceChanged = context.coordinator.colorScheme != colorScheme || context.coordinator.contrast != contrast
        guard textView.string != text || appearanceChanged else { return }

        let sourceChanged = textView.string != text
        let selection = textView.selectedRanges
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.lineBreakMode = .byWordWrapping
        let source = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: contrast == .increased ? NSColor.labelColor : NSColor(PickerStyle.ink),
            .paragraphStyle: paragraph
        ])

        // Only presentation attributes change. Source, whitespace, and copied text stay exact.
        if contrast != .increased, let tokens = Coordinator.tokens {
            let fullRange = NSRange(text.startIndex..., in: text)
            for match in tokens.matches(in: text, range: fullRange) {
                let isString = (text as NSString).substring(with: match.range).hasPrefix("\"")
                source.addAttribute(
                    .foregroundColor,
                    value: NSColor(isString ? PickerStyle.string : PickerStyle.keyword),
                    range: match.range
                )
            }
        }

        textView.textStorage?.setAttributedString(source)
        if sourceChanged {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollToBeginningOfDocument(nil)
        } else {
            textView.selectedRanges = selection
        }
        context.coordinator.colorScheme = colorScheme
        context.coordinator.contrast = contrast
    }

    final class Coordinator {
        var colorScheme: ColorScheme?
        var contrast: ColorSchemeContrast?
        static let tokens = try? NSRegularExpression(
            pattern: #""(?:\\.|[^"\\])*"|\b(?:tell|application|id|activate|do|action|from|end|linefeed|return|tab)\b"#
        )
    }
}
