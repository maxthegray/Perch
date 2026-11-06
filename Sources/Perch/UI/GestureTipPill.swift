import SwiftUI

/// The on-card pill for a `GestureTip`: a keycap and a few words over a material capsule.
/// Purely visual; the host view decides what the card's clicks do, so the pill never
/// takes one.
struct GestureTipPill: View {
    let tip: GestureTip

    var body: some View {
        HStack(spacing: 6) {
            Keycap(glyph: tip.key, size: 10.5)
            Text(tip.text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.leading, 5)
        .padding(.trailing, 9)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Shows `tip` near the bottom of the card: springs in, fades out.
    func gestureTipOverlay(_ tip: GestureTip?) -> some View {
        overlay(alignment: .bottom) {
            if let tip {
                GestureTipPill(tip: tip)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85, anchor: .bottom)
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.32, dampingFraction: 0.68)),
                        removal: .opacity.animation(.easeOut(duration: 0.35))
                    ))
            }
        }
    }
}
