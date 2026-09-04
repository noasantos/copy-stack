import SwiftUI

/// 14" MacBook Pro drawn at canonical size and scaled ONCE. Nothing inside knows it is small.
/// Canonical: lid 1560×1030 at x 110, display 1512×982 at (24, 24), camera housing 186×37,
/// base 1780×40 at y 1030 → total canvas 1780×1070.
struct MacBookFrame<Screen: View>: View {
    static var scale: CGFloat { 0.28 }
    static var canonicalSize: CGSize { CGSize(width: 1780, height: 1070) }
    static var displaySize: CGSize { CGSize(width: 1512, height: 982) }
    static var displayedSize: CGSize {
        CGSize(width: (canonicalSize.width * scale).rounded(),
               height: (canonicalSize.height * scale).rounded())
    }

    @ViewBuilder var screen: () -> Screen

    private var lidShape: UnevenRoundedRect {
        UnevenRoundedRect(topLeading: 44, topTrailing: 44, bottomLeading: 6, bottomTrailing: 6)
    }

    private var bezelShape: UnevenRoundedRect {
        // Concentric with the lid: inner radius = outer − inset.
        UnevenRoundedRect(topLeading: 37, topTrailing: 37, bottomLeading: 4, bottomTrailing: 4)
    }

    private var baseShape: UnevenRoundedRect {
        UnevenRoundedRect(topLeading: 3, topTrailing: 3, bottomLeading: 26, bottomTrailing: 26)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            base
            lid
        }
        .frame(width: Self.canonicalSize.width, height: Self.canonicalSize.height, alignment: .topLeading)
        .scaleEffect(Self.scale, anchor: .topLeading)
        .frame(width: Self.displayedSize.width, height: Self.displayedSize.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    // The base is wider than the lid — the frontal perspective of an open laptop.
    private var base: some View {
        baseShape
            .fill(LinearGradient(stops: [
                .init(color: Color(hex: 0xE4E4E8), location: 0),
                .init(color: Color(hex: 0xC6C6CB), location: 0.55),
                .init(color: Color(hex: 0x9C9CA2), location: 1)
            ], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                UnevenRoundedRect(bottomLeading: 10, bottomTrailing: 10)
                    .fill(LinearGradient(colors: [.black.opacity(0.22), .black.opacity(0.06)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 300, height: 12)
            }
            .overlay(baseShape.strokeBorder(edgeHighlight(top: .white.opacity(0.7), bottom: .black.opacity(0.25)), lineWidth: 1))
            .frame(width: 1780, height: 40)
            .shadow(color: .black.opacity(0.16), radius: 30, y: 30)
            .shadow(color: .black.opacity(0.10), radius: 8, y: 8)
            .offset(y: 1030)
    }

    private var lid: some View {
        ZStack(alignment: .topLeading) {
            lidShape
                .fill(LinearGradient(colors: [Color(hex: 0x34343A), Color(hex: 0x232327)],
                                     startPoint: .top, endPoint: .bottom))
                // Light aluminium edge: 2 pt ring outside the lid, matching the artboard's outer box-shadow.
                .overlay(lidShape.inset(by: -1).stroke(Color(hex: 0xBEBEC6, opacity: 0.55), lineWidth: 2))
                .overlay(lidShape.strokeBorder(edgeHighlight(top: .white.opacity(0.18), bottom: .clear), lineWidth: 1))

            bezelShape
                .fill(Color(hex: 0x050507))
                .padding(7)

            screen()
                .frame(width: Self.displaySize.width, height: Self.displaySize.height)
                .clipShape(UnevenRoundedRect(topLeading: 20, topTrailing: 20))
                .offset(x: 24, y: 24)

            // Camera housing, attached to the top edge of the display.
            UnevenRoundedRect(bottomLeading: 10, bottomTrailing: 10)
                .fill(.black)
                .overlay(alignment: .top) {
                    Circle()
                        .fill(Color(hex: 0x0B0B10))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.04), lineWidth: 1))
                        .frame(width: 9, height: 9)
                        .padding(.top, 13)
                }
                .frame(width: 186, height: 37)
                .offset(x: 687, y: 24)
        }
        .frame(width: 1560, height: 1030, alignment: .topLeading)
        .offset(x: 110)
    }

    private func edgeHighlight(top: Color, bottom: Color) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: top, location: 0),
            .init(color: .clear, location: 0.03),
            .init(color: .clear, location: 0.97),
            .init(color: bottom, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
}
