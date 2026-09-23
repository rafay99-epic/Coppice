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

struct MonoButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
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
        .font(.caption)
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
        guard value > 0 else { return "Zero KB" }
        return value.formatted(.byteCount(style: .file))
    }

    static func compactBytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 MB" }
        return value.formatted(.byteCount(style: .file, allowedUnits: [.mb, .gb, .tb]))
    }
}
