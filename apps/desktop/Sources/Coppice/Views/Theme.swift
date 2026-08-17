import SwiftUI

/// Visual tokens. Centralised so the whole app re-skins from one place.
///
/// True black rather than a dark grey: on the OLED-adjacent panels these Macs
/// ship with, `#000` is genuinely off rather than dimly lit, and the contrast
/// against white text is what makes a dense list readable at a glance.
enum Theme {
    static let background = Color.black
    static let panel = Color(white: 0.04)
    static let elevated = Color(white: 0.07)
    static let line = Color(white: 0.12)
    static let lineStrong = Color(white: 0.18)

    static let primary = Color.white
    static let secondary = Color(white: 0.58)
    static let tertiary = Color(white: 0.36)

    static let safe = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let caution = Color(red: 1.0, green: 0.75, blue: 0.26)
    static let blocked = Color(red: 1.0, green: 0.36, blue: 0.36)
    static let live = Color(red: 0.30, green: 0.65, blue: 1.0)
    static let info = Color(red: 0.69, green: 0.49, blue: 1.0)

    static let mono = Font.system(.body, design: .monospaced)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// One spring for every state change in the app, so motion feels like a
    /// single system rather than a pile of independent choices.
    static let motion = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// For content that appears or disappears rather than moving.
    static let fade = Animation.easeOut(duration: 0.18)
}

extension Verdict {
    var tint: Color {
        switch self {
        case .safe: return Theme.safe
        case .caution: return Theme.caution
        case .prunable, .orphan: return Theme.info
        case .blocked(let blocker):
            if case .liveProcess = blocker { return Theme.live }
            return Theme.blocked
        }
    }

    /// Shape and text carry the meaning too, never colour on its own.
    var symbol: String {
        switch self {
        case .safe: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .prunable: return "trash.slash.fill"
        case .orphan: return "questionmark.circle.fill"
        case .blocked(let blocker):
            if case .liveProcess = blocker { return "bolt.horizontal.circle.fill" }
            return "lock.fill"
        }
    }
}

/// Verdict pill. Word plus icon, so it survives a colourblind reader and a
/// greyscale print.
struct VerdictBadge: View {
    let verdict: Verdict
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: verdict.symbol)
                .font(.system(size: compact ? 8 : 9, weight: .bold))
            Text(verdict.label)
                .font(Theme.mono(compact ? 9 : 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(verdict.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(verdict.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(verdict.tint.opacity(0.28), lineWidth: 1)
        )
        .fixedSize()
    }
}

/// A single headline number with its label underneath.
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = Theme.primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.mono(19, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Theme.background)
    }
}

/// Determinate only. A looping spinner or shimmer repaints every frame, which on
/// a 120 Hz display keeps the GPU awake for as long as it is on screen.
struct ProgressStrip: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.line)
                Rectangle()
                    .fill(Theme.primary)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: 2)
        .animation(Theme.motion, value: fraction)
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(9, weight: .medium))
            .tracking(1.1)
            .foregroundStyle(Theme.tertiary)
    }
}

extension View {
    /// Standard hairline divider used between rows and sections.
    func hairline(_ edge: Edge.Set = .bottom) -> some View {
        padding(.zero).overlay(alignment: edge == .top ? .top : .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}
