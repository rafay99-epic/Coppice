import SwiftUI

/// Status colours, and nothing else.
///
/// There is deliberately no palette here. An app that paints its own greys,
/// blacks and accent stops looking like a Mac app the moment the user changes
/// appearance, accent colour, or turns on Increase Contrast. Everything that is
/// not a status signal uses the system's own semantics: `.secondary`,
/// `.quaternary`, `Divider`, materials, and the user's accent for primary
/// actions.
///
/// The five colours below map to macOS's standard meanings, so a verdict reads
/// the same way it does anywhere else in the OS.
extension Verdict {
    var tint: Color {
        switch self {
        case .safe: return .green
        case .caution: return .orange
        case .prunable, .orphan: return .secondary
        case .blocked(let blocker):
            if case .liveProcess = blocker { return .blue }
            return .red
        }
    }

    /// Shape and wording carry the meaning too, never colour alone.
    var symbol: String {
        switch self {
        case .safe: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .prunable: return "clock.arrow.circlepath"
        case .orphan: return "questionmark.circle.fill"
        case .blocked(let blocker):
            if case .liveProcess = blocker { return "bolt.horizontal.circle.fill" }
            return "lock.fill"
        }
    }

    /// Short noun for the badge. The row has limited width, and the full reason
    /// lives in the inspector and the tooltip.
    var shortLabel: String {
        switch self {
        case .safe: return "Safe"
        case .caution: return "Review"
        case .prunable: return "Stale"
        case .orphan: return "Orphan"
        case .blocked(let blocker):
            switch blocker {
            case .mainWorktree: return "Main"
            case .liveProcess: return "In use"
            case .uncommittedChanges, .untrackedFiles: return "Uncommitted"
            case .unpushedCommits, .aheadOfDefault: return "Unpushed"
            case .ignoredConfig: return "Local config"
            case .locked: return "Locked"
            case .gitOperationInProgress: return "In progress"
            case .dirtySubmodule: return "Submodule"
            case .outsideScanRoots: return "Out of scope"
            }
        }
    }
}

/// A verdict shown as an icon and a word, sized for a table cell.
struct VerdictBadge: View {
    let verdict: Verdict

    var body: some View {
        Label {
            Text(verdict.shortLabel)
        } icon: {
            Image(systemName: verdict.symbol)
        }
        .font(.caption)
        .foregroundStyle(verdict.tint)
        .labelStyle(.titleAndIcon)
        .help(helpText)
    }

    private var helpText: String {
        switch verdict {
        case .blocked(let blocker): return "\(blocker.summary). \(blocker.remedy)"
        case .caution(let list): return list.map(\.summary).joined(separator: ". ")
        case .safe: return "Clean, pushed, nothing running, no local-only config."
        case .prunable: return "The directory is gone. Only stale git metadata remains."
        case .orphan: return "The parent repository no longer exists."
        }
    }
}

/// Formatting shared by the menu bar, the table and the log.
enum Format {
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "Zero KB" }
        return value.formatted(.byteCount(style: .file))
    }

    /// Sizes in a column read better abbreviated, and never wrap.
    static func compactBytes(_ value: Int64) -> String {
        guard value > 0 else { return "—" }
        return value.formatted(.byteCount(style: .file, allowedUnits: [.mb, .gb, .tb]))
    }
}
