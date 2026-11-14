// SPDX-License-Identifier: GPL-3.0-or-later
// The bundled app icon lifts into a blue glow, catches a sweep of light, then
// gives way to Home. AppOpening owns readiness, the clock and Home's reveal.

import SwiftUI

struct OpeningView: View {
    @ObservedObject private var opening = AppOpening.shared

    // xtool ships this PNG at the bundle root for both variants. Use the same
    // artwork as the Home Screen rather than maintaining another drawn logo.
    private let iconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String ?? "AppIcon"

    var body: some View {
        TimelineView(.animation(paused: opening.phase == .done || (opening.reduceMotion && opening.phase != .leaving))) { tl in
            let t = tl.date.timeIntervalSince(opening.clock)
            let leaving = opening.leftAt.map { tl.date.timeIntervalSince($0) }
            let fade = leaving.map { OpeningTime.progress($0, 0, 0.4) } ?? 0
            GeometryReader { geometry in
                let side = min(min(geometry.size.width, geometry.size.height) * 0.48, 212)
                ZStack {
                    PP.background
                    EllipticalGradient(colors: [PP.raised, PP.background], startRadiusFraction: 0, endRadiusFraction: 0.72)
                        .opacity(opening.reduceMotion ? 1 : OpeningTime.progress(t, 0, 0.7))
                    icon(at: t, side: side, leaving: fade)
                    Text("pcios")
                        .font(PP.display(23, .semibold))
                        .tracking(3)
                        .foregroundStyle(PP.soft)
                        .opacity(opening.reduceMotion ? 1 : OpeningTime.progress(t, 0.65, 0.45))
                        .offset(y: side / 2 + 35)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(1 - fade)
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGPoint.self) { p in
            let f = p.frame(in: .global)
            return CGPoint(x: f.midX, y: f.midY)
        } action: { opening.center = $0 }
        .allowsHitTesting(opening.phase == .intro || opening.phase == .holding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("pcios is starting")
    }

    private func icon(at t: Double, side: CGFloat, leaving: Double) -> some View {
        let reduced = opening.reduceMotion
        let appear = reduced ? 1 : OpeningTime.progress(t, 0.08, 0.55)
        let settle = reduced ? 1 : OpeningTime.progress(t, 0.08, 0.85)
        let scale = OpeningTime.keys(settle, [(0, 0.82), (0.7, 1.035), (1, 1)])
        let sweep = OpeningTime.progress(t, 0.6, 0.85, .easeInOut)
        let breath = reduced ? 0 : sin(max(0, t - AppOpening.introSeconds) * .pi / 1.6)
        let shape = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)

        return ZStack {
            // A restrained pool of light continues breathing if the library needs time.
            Circle()
                .fill(RadialGradient(colors: [PP.accent.opacity(0.23), PP.progress.opacity(0.08), .clear],
                                     center: .center, startRadius: 0, endRadius: side * 0.85))
                .frame(width: side * 1.9, height: side * 1.9)
                .scaleEffect(1 + breath * 0.035)
                .opacity(appear)

            Image(iconName)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [PP.accent.opacity(0.45), PP.accent.opacity(0.04)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
                .overlay {
                    if !reduced {
                        // One soft glint crosses the actual artwork during the reveal.
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.18), .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: side * 0.45, height: side * 1.8)
                            .rotationEffect(.degrees(22))
                            .offset(x: side * (sweep * 2.4 - 1.2))
                            .opacity(sin(sweep * .pi))
                            .frame(width: side, height: side)
                            .clipShape(shape)
                    }
                }
                .shadow(color: PP.accent.opacity(0.10 + breath * 0.025), radius: 24, y: 4)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 12)
                .scaleEffect(reduced ? 1 : scale * (1 + leaving * 0.12))
                .offset(y: reduced ? 0 : 14 * (1 - appear))
                .blur(radius: reduced ? 0 : 6 * (1 - appear))
                .opacity(appear)
        }
    }
}
