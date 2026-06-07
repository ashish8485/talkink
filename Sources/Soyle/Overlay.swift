import AppKit
import SwiftUI

/// NVIDIA green.
extension Color {
    static let nvidia = Color(red: 0x76 / 255, green: 0xB9 / 255, blue: 0x00 / 255)
}
extension NSColor {
    static let nvidia = NSColor(red: 0x76 / 255, green: 0xB9 / 255, blue: 0x00 / 255, alpha: 1)
}

enum OverlayState: Equatable {
    case hidden
    case recording
    case transcribing
    case done(String)
    case error(String)
}

/// Observable state shared between the panel and SwiftUI view.
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .hidden
    @Published var level: Float = 0
}

// MARK: - View

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ZStack {
            if model.state != .hidden {
                pill
                    .transition(.scale(scale: 0.85, anchor: .bottom)
                        .combined(with: .opacity)
                        .combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // center the pill in the panel
        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: model.state)
    }

    private var pill: some View {
        HStack(spacing: 11) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minWidth: 150)
        .background(
            ZStack {
                // Dark HUD so white text stays readable on ANY background (incl. white).
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.55))
            }
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.nvidia.opacity(0.7), lineWidth: 1.2)
            )
        )
        .compositingGroup()
        .shadow(color: .nvidia.opacity(0.35), radius: 16)
        .shadow(color: .black.opacity(0.30), radius: 10, y: 5)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .hidden:
            EmptyView()
        case .recording:
            RecordingDot()
            LiveWaveform(level: model.level)
            label("Speak…")
        case .transcribing:
            BouncingDots()
            label("Transcribing…")
        case .done(let text):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.nvidia)
                .transition(.scale.combined(with: .opacity))
            label(text.isEmpty ? "Nothing heard" : "Copied")
        case .error(let msg):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.orange)
            label(msg)
        }
    }

    private func label(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Animated pieces

/// Pulsing green "recording" dot.
private struct RecordingDot: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Color.nvidia)
            .frame(width: 9, height: 9)
            .shadow(color: .nvidia.opacity(0.8), radius: pulse ? 5 : 1)
            .opacity(pulse ? 1 : 0.4)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// Live waveform that breathes continuously and grows with the mic level.
private struct LiveWaveform: View {
    var level: Float
    private let bars = 7

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule()
                        .fill(Color.nvidia)
                        .frame(width: 3.2, height: height(i, t))
                }
            }
            .frame(height: 24)
        }
    }

    private func height(_ i: Int, _ t: Double) -> CGFloat {
        let lvl = Double(max(0.05, min(1, level)))
        let phase = Double(i) * 0.8
        let wave = (sin(t * 8 + phase) + 1) / 2            // 0...1
        let amp = 5 + lvl * 19 * (0.45 + 0.55 * wave)
        return CGFloat(amp)
    }
}

/// Three green dots bouncing in sequence (transcribing indicator).
private struct BouncingDots: View {
    private let n = 3
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<n, id: \.self) { i in
                    Circle()
                        .fill(Color.nvidia)
                        .frame(width: 6.5, height: 6.5)
                        .offset(y: -CGFloat(max(0, sin(t * 6 - Double(i) * 0.7))) * 5)
                }
            }
            .frame(height: 24)
        }
    }
}

// MARK: - Controller

/// Manages the borderless floating NSPanel that hosts the overlay.
final class OverlayController {
    let model = OverlayModel()
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    private let panelSize = NSSize(width: 340, height: 120)

    init() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: OverlayView(model: model))
        host.frame = NSRect(origin: .zero, size: panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
    }

    func show(_ state: OverlayState, autoHideAfter seconds: Double? = nil) {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.position()
            self.panel?.orderFrontRegardless()
            self.model.state = state
            if let seconds {
                let work = DispatchWorkItem { [weak self] in self?.hide() }
                self.hideWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
            }
        }
    }

    func updateLevel(_ level: Float) {
        DispatchQueue.main.async { self.model.level = level }
    }

    func hide() {
        DispatchQueue.main.async {
            self.model.state = .hidden               // plays the exit transition
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.model.state == .hidden else { return }
                self.panel?.orderOut(nil)
            }
            self.hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.midX - panelSize.width / 2
        let y = vf.minY + 120
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
