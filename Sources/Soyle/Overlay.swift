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

/// The floating pill shown while recording / transcribing.
struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        Group {
            switch model.state {
            case .hidden:
                EmptyView()
            case .recording:
                pill {
                    Waveform(level: model.level)
                    Text("Parle…").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            case .transcribing:
                pill {
                    ProgressView().controlSize(.small).tint(.nvidia)
                    Text("Transcription…").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            case .done(let text):
                pill {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.nvidia)
                    Text(text.isEmpty ? "Rien entendu" : "Copié ✓")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
            case .error(let msg):
                pill {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(msg).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.state)
    }

    @ViewBuilder
    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(Color.nvidia.opacity(0.55), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

/// Lightweight live level meter (bars react to mic RMS).
struct Waveform: View {
    var level: Float
    private let bars = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule()
                    .fill(Color.nvidia)
                    .frame(width: 3, height: height(for: i))
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.12), value: level)
    }

    private func height(for index: Int) -> CGFloat {
        // Center bars taller; modulate by level with a small per-bar phase.
        let base: CGFloat = 4
        let lvl = CGFloat(max(0, min(1, level)))
        let phase: [CGFloat] = [0.55, 0.85, 1.0, 0.8, 0.5]
        return base + lvl * 16 * phase[index % phase.count]
    }
}

/// Manages the borderless floating NSPanel that hosts the overlay.
final class OverlayController {
    let model = OverlayModel()
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 64),
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
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
    }

    func show(_ state: OverlayState, autoHideAfter seconds: Double? = nil) {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.model.state = state
            self.positionAndOrder()
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
            self.model.state = .hidden
            self.panel?.orderOut(nil)
        }
    }

    private func positionAndOrder() {
        guard let panel, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.minY + 96
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }
}
