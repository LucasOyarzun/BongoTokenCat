import Foundation

/// Turns hook events into "keep drumming until T".
///
/// The rhythm is driven by how much the model *writes*, not by how often it calls
/// tools. Measured on real sessions, tool calls land a median 7.7s apart — a cat
/// tapping once every eight seconds reads as broken. Output volume is the signal
/// with enough density to animate: median 428 tokens per assistant message.
///
/// `tokensPerSecond` is the tuning knob. On the same sample it produces roughly:
/// 40 tok/s → drumming 100% of the time (saturated, no visible rest),
/// 100 tok/s → 62%, 150 tok/s → 42%. The default sits in the band where the cat
/// looks busy but its pauses still mean something.
enum DrumEngine {
    static let tokensPerSecond: Double = 120

    /// Fallback burst for events that carry no text. Long enough to register as a
    /// deliberate hit, short enough that a burst of tool calls reads as separate hits.
    static let toolBurst: TimeInterval = 0.45

    /// A single turn should not lock the paws down for minutes on end — a 20k-token
    /// message would otherwise drum for nearly three minutes past the actual work.
    static let maxBurst: TimeInterval = 8

    /// Rough token count for a piece of assistant text. Four characters per token is
    /// the usual English approximation; exactness does not matter here because the
    /// result only sets an animation length.
    static func estimatedTokens(in text: String) -> Int { text.count / 4 }

    /// How long this event should keep the paws moving. Zero = do not drum.
    static func burstDuration(for event: HookEvent) -> TimeInterval {
        guard let state = EventMapping.state(for: event), state.isBusy else { return 0 }
        guard let text = event.producedText, !text.isEmpty else { return toolBurst }
        let seconds = Double(estimatedTokens(in: text)) / tokensPerSecond
        return min(max(seconds, toolBurst), maxBurst)
    }

    /// Beats per second while drumming, scaled by how much is queued up.
    ///
    /// A cat that always drums at one speed carries no information beyond on/off.
    /// Tying tempo to the remaining burst makes a heavy turn visibly more frantic
    /// than a single tool call.
    static func beatsPerSecond(remaining: TimeInterval) -> Double {
        let intensity = min(remaining / maxBurst, 1)
        return 5 + (intensity * 7)   // 5 Hz idle-busy → 12 Hz flat out
    }
}
