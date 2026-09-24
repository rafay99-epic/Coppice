import SwiftUI

extension Verdict {
    var tint: HierarchicalShapeStyle {
        switch status {
        case .ready, .hasWork: return .primary
        case .inUse: return .secondary
        case .protected, .stale: return .tertiary
        }
    }

    var symbol: String {
        switch status {
        case .ready: return "circle.fill"
        case .hasWork: return "circle.lefthalf.filled"
        case .inUse: return "circle.dashed"
        case .protected: return "lock.fill"
        case .stale: return "clock"
        }
    }

    var shortLabel: String {
        switch status {
        case .ready: return "Ready"
        case .hasWork: return "Has work"
        case .inUse: return "In use"
        case .protected: return "Protected"
        case .stale: return "Stale"
        }
    }
}

extension Font {
    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "Fraunces-LightItalic" : "Fraunces-Light", size: size)
    }

    static func heading(_ size: CGFloat = 17, italic: Bool = false) -> Font {
        .custom(italic ? "Fraunces-Italic" : "Fraunces-Regular", size: size)
    }

    static let ui = Font.custom("Instrument Sans", size: 13, relativeTo: .body)
    static let uiLarge = Font.custom("Instrument Sans", size: 15, relativeTo: .title3)
    static let uiCallout = Font.custom("Instrument Sans", size: 12.5, relativeTo: .callout)
    static let uiCaption = Font.custom("Instrument Sans", size: 11.5, relativeTo: .caption)
}

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.heading(14, italic: true))
            .foregroundStyle(.secondary)
    }
}

struct MonoButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize()
            .font(.ui.weight(.medium))
            .foregroundStyle(.black)
            .padding(.horizontal, Space.l)
            .padding(.vertical, 6)
            .background(.white, in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .animation(.smooth, value: isEnabled)
    }
}

extension ButtonStyle where Self == MonoButtonStyle {
    static var mono: MonoButtonStyle { MonoButtonStyle() }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize()
            .font(.ui.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, Space.l)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(.white.opacity(0.35)))
            .contentShape(.capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

struct MonoToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: Space.m) {
                configuration.label
                Spacer(minLength: Space.m)
                Capsule()
                    .fill(configuration.isOn ? Color.white : Color.white.opacity(0.16))
                    .frame(width: 30, height: 18)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? Color.black : Color.white)
                            .padding(2)
                    }
                    .animation(.snappy(duration: 0.18), value: configuration.isOn)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == MonoToggleStyle {
    static var mono: MonoToggleStyle { MonoToggleStyle() }
}

struct ProgressLine: View {
    let value: Double
    var height: CGFloat = 1

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.12))
            Rectangle().fill(.white).scaleEffect(x: min(max(value, 0), 1), anchor: .leading)
        }
        .frame(height: height)
        .animation(.smooth, value: value)
        .accessibilityElement()
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func withoutGlass() -> some ToolbarContent {
        if #available(macOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

extension View {
    func numeric<Value: Equatable>(_ value: Value) -> some View {
        contentTransition(.numericText()).animation(.smooth, value: value)
    }
}

struct VerdictBadge: View {
    let verdict: Verdict

    var body: some View {
        Label {
            Text(verdict.shortLabel)
                .fontWeight(verdict.status == .ready ? .semibold : .regular)
        } icon: {
            Image(systemName: verdict.symbol)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.uiCaption)
        .foregroundStyle(verdict.tint)
        .labelStyle(.titleAndIcon)
        .help(helpText)
    }

    private var helpText: String {
        switch verdict {
        case .blocked(let blocker):
            return blocker.severity == .absolute ? "\(blocker.summary). \(blocker.remedy)" : blocker.summary
        case .caution(let list): return list.map(\.summary).joined(separator: ". ")
        case .safe: return "Clean, pushed, nothing running."
        case .prunable: return "The directory is gone. Only stale git metadata remains."
        case .orphan: return "The parent repository no longer exists."
        }
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 MB" }
        return value.formatted(.byteCount(style: .file))
    }

    static func compactBytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 MB" }
        return value.formatted(.byteCount(style: .file, allowedUnits: [.mb, .gb, .tb]))
    }
}
