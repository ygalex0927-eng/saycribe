import AppKit
import SwiftUI

/// Black + terracotta, terminal-style. Orange is the only accent; everything else is ink and greys.
enum Brand {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static let orange = hex(0xD97757)
    static let accent = orange
    static let ink = hex(0x141413)
    /// Sidebar and raised surfaces sit a step above the ink background.
    static let surface = hex(0x1C1B1A)
    static let raised = hex(0x252422)
    static let cream = hex(0xF0EEE6)
    static let pill = ink
    /// Waveform: lighter at the top of each bar, deeper at the bottom.
    static let waveTop = hex(0xEC9A78)
    static let waveBottom = hex(0xC96442)
}

/// Smoothed microphone loudness. Not @Published: the waveform reads it every frame from a TimelineView,
/// so pushing ~50 updates/s through SwiftUI invalidation would be wasted work.
final class LevelMeter {
    private(set) var value: CGFloat = 0

    /// `rms` is raw signal RMS (0…1). Fast attack, slow release, perceptual curve.
    func push(rms: Float) {
        let target = min(1, CGFloat(rms).squareRoot() * 2.8)
        value = target > value ? value + (target - value) * 0.6 : value * 0.86 + target * 0.14
    }

    func reset() { value = 0 }
}

final class HUDModel: ObservableObject {
    enum Phase: Equatable { case listening, locked, thinking, done, error(String) }

    @Published var phase: Phase = .listening
    @Published var editing = false
    /// Target language label (e.g. "EN") while translating; nil for plain dictation.
    @Published var translateLabel: String?
    @Published var visible = false
    let meter = LevelMeter()
    var onCancel: () -> Void = {}
    var onFinish: () -> Void = {}
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if model.visible {
                pill
                    .transition(.scale(scale: 0.86, anchor: .bottom).combined(with: .opacity))
                    .padding(.bottom, 14)
            }
        }
        .frame(width: HUDController.size.width, height: HUDController.size.height)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.visible)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: model.phase)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: model.editing)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: model.translateLabel)
    }

    private var pill: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, horizontalPadding)
            .frame(width: width, height: 36)
            .background(
                Capsule(style: .continuous).fill(Brand.pill)
                    .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            )
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
            .environment(\.colorScheme, .dark)
    }

    private var width: CGFloat? {
        let extra = (model.editing ? 22 : 0) + (model.translateLabel.map { 26 + CGFloat($0.count) * 8 } ?? 0)
        switch model.phase {
        case .listening: return 100 + extra
        case .locked: return 152 + extra
        case .thinking: return 100
        case .done: return 36
        case .error: return nil
        }
    }

    private var horizontalPadding: CGFloat {
        switch model.phase {
        case .done: return 0
        case .locked: return 6
        default: return 14
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .listening:
            modeGlyph
            LiveWave(meter: model.meter)
        case .locked:
            PillButton(symbol: "xmark", filled: false, action: model.onCancel)
            modeGlyph
            LiveWave(meter: model.meter)
            PillButton(symbol: "arrow.up", filled: true, action: model.onFinish)
        case .thinking:
            ThinkingWave()
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.orange)
                .transition(.scale.combined(with: .opacity))
        case let .error(message):
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder private var modeGlyph: some View {
        if let label = model.translateLabel {
            HStack(spacing: 4) {
                Image(systemName: "globe").font(.system(size: 11.5, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).fixedSize()
            }
            .foregroundStyle(.white.opacity(0.85))
        } else if model.editing {
            editGlyph
        }
    }

    private var editGlyph: some View {
        Image(systemName: "pencil.line")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
    }
}

/// Nine bars with a centre-weighted envelope; height follows the voice, with a gentle per-bar wobble so it feels alive.
struct LiveWave: View {
    let meter: LevelMeter

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let n = 9, barW: CGFloat = 3, gap: CGFloat = 3.5
                let level = meter.value
                var x = (size.width - CGFloat(n) * barW - CGFloat(n - 1) * gap) / 2
                for i in 0..<n {
                    let fromCenter = abs(CGFloat(i) - 4) / 4
                    let envelope = 1 - 0.6 * fromCenter * fromCenter
                    let wobble = 0.72 + 0.28 * CGFloat(sin(t * 9.5 + Double(i) * 1.7))
                    let idle = 0.13 + 0.04 * CGFloat(sin(t * 2.4 + Double(i) * 0.8))
                    let h = max(barW, size.height * min(1, max(idle, level * envelope * wobble)))
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barW, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2),
                             with: .linearGradient(Gradient(colors: [Brand.waveTop, Brand.waveBottom]),
                                                   startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                   endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                    x += barW + gap
                }
            }
        }
        .frame(width: 60, height: 20)
    }
}

/// A soft travelling wave across the same nine bars while the text is being cleaned.
struct ThinkingWave: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let n = 9, barW: CGFloat = 3, gap: CGFloat = 3.5
                var x = (size.width - CGFloat(n) * barW - CGFloat(n - 1) * gap) / 2
                for i in 0..<n {
                    let s = max(0, sin(t * 5.2 - Double(i) * 0.62))
                    let k = CGFloat(s * s)
                    let h = barW + (size.height * 0.55 - barW) * k
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barW, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(Brand.orange.opacity(0.35 + 0.65 * k)))
                    x += barW + gap
                }
            }
        }
        .frame(width: 60, height: 20)
    }
}

struct PillButton: View {
    let symbol: String
    let filled: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(filled ? Brand.pill : .white.opacity(hover ? 1 : 0.75))
                .frame(width: 24, height: 24)
                .background(Circle().fill(filled ? Brand.orange.opacity(hover ? 1 : 0.9) : .white.opacity(hover ? 0.18 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Floating capsule near the bottom of the active screen. Never takes focus; only clickable in hands-free mode.
final class HUDController {
    static let size = CGSize(width: 420, height: 80)
    let model = HUDModel()
    private var hideWork: DispatchWorkItem?

    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: HUDView(model: model))
        return p
    }()

    /// `translate`: pass `.some(label)` to set or `.some(nil)` to clear the translate badge; omit to keep it.
    func show(_ phase: HUDModel.Phase, editing: Bool? = nil, translate: String?? = nil) {
        hideWork?.cancel()
        if phase == .listening && model.phase != .locked { model.meter.reset() }
        if let editing { model.editing = editing }
        if let translate { model.translateLabel = translate }
        model.phase = phase
        panel.ignoresMouseEvents = phase != .locked
        if !panel.isVisible {
            position()
            panel.orderFrontRegardless()
        }
        model.visible = true
    }

    func hide(after delay: TimeInterval = 0) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.visible = false
            self.panel.ignoresMouseEvents = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !self.model.visible { self.panel.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 18))
    }
}
