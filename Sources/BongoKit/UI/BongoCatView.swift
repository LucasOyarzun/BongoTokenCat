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
        .opacity(state == .sleeping ? 0.55 : 1)
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

    @ViewBuilder
    private var badge: some View {
        if let symbol = badgeSymbol {
            Image(systemName: symbol)
                .font(.system(size: max(10, width * 0.075), weight: .bold))
                .foregroundStyle(.white)
                .padding(max(3, width * 0.018))
                .background(Circle().fill(badgeColor))
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: max(1, width * 0.006)))
                .shadow(color: .black.opacity(0.4), radius: 2)
                .offset(x: width * 0.30, y: -width * 0.02)
                .transition(.scale.combined(with: .opacity))
        }
    }

    /// Only states that need something from you get a badge. Working and thinking
    /// are already legible from the paws, and a badge on every cat would turn the
    /// row back into the wall of noise the rhythm is meant to replace.
    private var badgeSymbol: String? {
        switch state {
        case .needsInput: return "questionmark"
        case .failed:     return "exclamationmark"
        case .done:       return "checkmark"
        default:          return nil
        }
    }

    private var badgeColor: Color {
        switch state {
        case .needsInput: return .orange
        case .failed:     return .red
        case .done:       return .green
        default:          return .clear
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
