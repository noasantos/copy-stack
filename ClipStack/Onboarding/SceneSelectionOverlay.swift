import SwiftUI

/// Crosshair area capture: the dim covers everything outside the selection, the rectangle grows
/// from the anchor while the crosshair follows the drag, then flashes white and hands off to the popover.
struct SelectionOverlay: View {
    let cue: DemoTimeline.CaptureCue
    let anchor: CGPoint
    let size: CGSize

    @Environment(\.demoReduceMotion) private var reduceMotion

    private var selectionSize: CGSize { cue.dragged ? size : .zero }
    private var cursor: CGPoint {
        cue.dragged ? CGPoint(x: anchor.x + size.width, y: anchor.y + size.height) : anchor
    }
    private var selectionVisible: Bool {
        !(cue == .idle || cue == .keysDown || cue.landed)
    }

    private var dragCurve: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.3, 0.7, 0.3, 1, duration: 0.85)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            dim
            selectionRectangle
            crosshair
            sizeLabel
        }
        .frame(width: DemoGeometry.screen.width, height: DemoGeometry.screen.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private var dim: some View {
        Rectangle()
            .fill(.black)
            .opacity(cue.dimmed ? 0.28 : 0)
            .mask {
                Rectangle()
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .frame(width: selectionSize.width, height: selectionSize.height)
                            .offset(x: anchor.x, y: anchor.y)
                            .blendMode(.destinationOut)
                            .animation(dragCurve, value: selectionSize)
                    }
                    .compositingGroup()
            }
            .animation(.easeOut(duration: 0.15), value: cue.dimmed)
    }

    private var selectionRectangle: some View {
        // Concentric rings, outward from the edge: white 0–1.5 pt, black 1.5–3 pt.
        ZStack {
            Rectangle()
                .fill(cue == .release ? Color.white.opacity(0.35) : .clear)
                .animation(cue == .release ? .easeOut(duration: 0.1) : .easeOut(duration: 0.25), value: cue)
            Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 1.5).padding(-3)
            Rectangle().strokeBorder(.white.opacity(0.95), lineWidth: 1.5).padding(-1.5)
        }
        .frame(width: selectionSize.width, height: selectionSize.height)
            .offset(x: anchor.x, y: anchor.y)
            .opacity(selectionVisible ? 1 : 0)
            .animation(dragCurve, value: selectionSize)
            .animation(.easeOut(duration: 0.25), value: selectionVisible)
    }

    private var crosshair: some View {
        ZStack {
            Rectangle().fill(.white).frame(width: 28, height: 2)
            Rectangle().fill(.white).frame(width: 2, height: 28)
        }
        .shadow(color: .black.opacity(0.5), radius: 0.5)
        .frame(width: 28, height: 28)
        .offset(x: cursor.x - 14, y: cursor.y - 14)
        .opacity(cue.dimmed ? 1 : 0)
        .animation(dragCurve, value: cursor)
        .animation(.easeOut(duration: 0.15), value: cue.dimmed)
    }

    private var sizeLabel: some View {
        Text(verbatim: "\(Int(size.width * 2)) × \(Int(size.height * 2))")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: 0x1E1E1E, opacity: 0.85), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
            .offset(x: cursor.x + 14, y: cursor.y + 12)
            .opacity(cue == .drag ? 1 : 0)
            .animation(dragCurve, value: cursor)
            .animation(.easeOut(duration: 0.12), value: cue)
    }
}
