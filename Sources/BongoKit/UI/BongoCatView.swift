import SwiftUI

/// One bongo cat: the layered artwork plus whatever state badge it needs.
struct BongoCatView: View {
    let state: AgentState
    /// When the current burst ends. Compared against `now` rather than baked into a
    /// boolean so the paws settle the moment the burst expires, without waiting for
    /// something else to rebuild the view.
    let drumsUntil: Date
    let now: Date
    let skin: Skin
    let width: Double
    let label: String?

    private var isDrumming: Bool { drumsUntil > now }

    /// 0…1 — how much of a full-length burst is still queued up.
    private var intensity: Double {
        let remaining = drumsUntil.timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return min(remaining / DrumEngine.maxBurst, 1)
    }

    var body: some View {
        VStack(spacing: 1) {
            ZStack(alignment: .top) {
                artwork
                badge
            }
            if let label, !label.isEmpty {
                Text(label)
                    .font(.system(size: max(9, width * 0.06), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    // The label sits straight on the desktop, so it carries its own
                    // contrast rather than relying on what is behind it.
                    .shadow(color: .black.opacity(0.9), radius: 2)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: width)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Artwork

    private var artwork: some View {
        ZStack {
            sprite("cat")
            sprite(PawPose.left(currentPaws))
            sprite(PawPose.right(currentPaws))
        }
        .frame(width: width, height: width * CatSprites.aspectRatio)
        // The body is filled white, so multiplying recolours the cat itself. This is
        // what the previous line-art sprites could not do: black strokes stay black
        // under any multiplier.
        .colorMultiply(skin.bodyColor)
        .saturation(state == .failed ? 0 : 1)
        // Dimmed, not ghosted. At 0.55 a white cat all but vanished into a light
        // wallpaper; the `zzz` badge now carries the meaning, so the fade only has
        // to hint at it.
        .opacity(state == .sleeping ? 0.8 : 1)
        // Lifts a white cat off a light wallpaper without putting a panel behind it.
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    private var currentPaws: PawPosition {
        guard isDrumming else { return .resting(for: state) }
        let beats = DrumEngine.beatsPerSecond(remaining: intensity * DrumEngine.maxBurst)
        return .drumming(at: now.timeIntervalSinceReferenceDate, beatsPerSecond: beats)
    }

    /// Layers share one canvas, so each simply fills the frame.
    @ViewBuilder
    private func sprite(_ name: String) -> some View {
        if let image = CatSprites.image(named: name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }

    // MARK: - Badge

    /// Symbol, colour, and how far to shrink the glyph so it fits the circle.
    /// `ellipsis` and `zzz` are much wider than they are tall, which is what
    /// `glyphScale` is for.
    private struct BadgeStyle {
        let symbol: String
        let color: Color
        var glyphScale: Double = 1
    }

    @ViewBuilder
    private var badge: some View {
        if let style = badgeStyle {
            Image(systemName: style.symbol)
                .font(.system(size: badgeDiameter * 0.66 * style.glyphScale, weight: .bold))
                .foregroundStyle(.white)
                // A square frame keeps the background a circle whatever the glyph's
                // aspect ratio; padding alone let a wide symbol squash it into a
                // sliver with the dots hanging outside.
                .frame(width: badgeDiameter, height: badgeDiameter)
                .background(Circle().fill(style.color))
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: max(1, width * 0.006)))
                .shadow(color: .black.opacity(0.4), radius: 2)
                .offset(x: width * 0.30, y: -width * 0.02)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var badgeDiameter: Double { max(16, width * 0.111) }

    /// A badge only for what the paws cannot say. Working and delegating are the
    /// exception — their rhythm already carries it, and a badge on every cat would
    /// turn the row back into the wall of noise the rhythm is meant to replace.
    ///
    /// The three alert colours stay reserved for states that owe you something.
    /// Thinking and sleeping report rather than ask, so they take cool, quiet
    /// colours: they earn a badge only because the paws alone leave them ambiguous
    /// — thinking against idle, sleeping against failed.
    private var badgeStyle: BadgeStyle? {
        switch state {
        case .needsInput: return BadgeStyle(symbol: "questionmark", color: .orange)
        case .failed:     return BadgeStyle(symbol: "exclamationmark", color: .red)
        case .done:       return BadgeStyle(symbol: "checkmark", color: .green)
        case .thinking:   return BadgeStyle(symbol: "ellipsis", color: .blue, glyphScale: 0.8)
        case .sleeping:   return BadgeStyle(symbol: "zzz", color: .gray, glyphScale: 0.75)
        default:          return nil
        }
    }

    private var accessibilityDescription: String {
        let who = label ?? "Agent"
        switch state {
        case .working, .delegating: return "\(who) is working"
        case .thinking:             return "\(who) is thinking"
        case .needsInput:           return "\(who) is waiting for you"
        case .failed:               return "\(who) hit an error"
        case .done:                 return "\(who) finished"
        case .idle:                 return "\(who) is idle"
        case .sleeping:             return "\(who) is asleep"
        }
    }
}

private extension PawPose {
    static func left(_ position: PawPosition) -> String { position.left.spriteName(side: "left") }
    static func right(_ position: PawPosition) -> String { position.right.spriteName(side: "right") }
}
