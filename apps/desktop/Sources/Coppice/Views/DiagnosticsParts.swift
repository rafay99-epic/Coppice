import SwiftUI

struct Sparkline: View {
    let values: [Double]
    var zeroBased = false

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard values.count > 1, let high = values.max(), let low = values.min() else { return }
                let floor = zeroBased ? 0 : low
                let range = max(high - floor, zeroBased ? 1 : high * 0.05, 0.000_1)
                let step = geometry.size.width / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
                    let point = CGPoint(
                        x: CGFloat(index) * step,
                        y: geometry.size.height - 2 - CGFloat((value - floor) / range) * (geometry.size.height - 4)
                    )
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(.white, lineWidth: 1.2)
        }
        .frame(height: 44)
        .background(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

struct VitalsCharts: View {
    let samples: [Telemetry.Sample]
    let usage: Telemetry.Usage
    let cpu: Double
    let uptime: TimeInterval

    private var span: String {
        guard let first = samples.first, Date().timeIntervalSince(first.date) > 55 * 60 else { return "since launch" }
        return "last hour"
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            chart(
                "Memory",
                value: Format.bytes(usage.memory),
                values: samples.map { Double($0.memory) },
                zeroBased: false,
                note: "\(span) · peak \(Format.bytes(max(samples.map(\.memory).max() ?? 0, usage.memory)))"
            )
            chart(
                "CPU",
                value: String(format: "%.1f%%", cpu),
                values: samples.map(\.cpu),
                zeroBased: true,
                note: "\(usage.threads) threads · up \(Format.duration(uptime))"
            )
        }
    }

    private func chart(_ title: String, value: String, values: [Double], zeroBased: Bool, note: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: Space.s)
                Text(value)
                    .font(.display(22))
                    .monospacedDigit()
            }
            Sparkline(values: values, zeroBased: zeroBased)
            Text(note)
                .font(.uiCaption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value), \(note)")
    }
}

struct PhaseRow: View {
    let phase: Telemetry.Phase
    let total: Double

    var body: some View {
        HStack(spacing: Space.m) {
            Text(phase.name)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            GeometryReader { geometry in
                Rectangle()
                    .fill(phase.background ? Color.white.opacity(0.35) : Color.white)
                    .frame(width: max(geometry.size.width * phase.seconds / total, 2), height: 4)
                    .offset(x: geometry.size.width * phase.start / total)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 10)
            Text(Telemetry.format(phase.seconds))
                .font(.uiCaption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phase.name), \(Telemetry.format(phase.seconds))\(phase.background ? ", in the background" : "")")
    }
}

struct Job: Identifiable {
    enum State {
        case running, idle, waiting, off

        var word: String {
            switch self {
            case .running: return "running"
            case .idle: return "idle"
            case .waiting: return "waiting"
            case .off: return "off"
            }
        }
    }

    let name: String
    let state: State
    let detail: String

    var id: String { name }
}

struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                Circle()
                    .strokeBorder(.white, lineWidth: 1)
                    .background(Circle().fill(job.state == .running ? Color.white : .clear))
                    .frame(width: 7, height: 7)
                Text(job.state.word)
            }
            .frame(width: 72, alignment: .leading)
            Text(job.name)
            Text(job.detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .opacity(job.state == .off ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

struct CommandRow: View {
    let command: Telemetry.Command

    var body: some View {
        HStack(spacing: Space.m) {
            Text(command.label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Space.s)
            if command.status != 0 {
                Text("exit \(command.status)")
                    .font(.uiCaption)
                    .foregroundStyle(.tertiary)
            }
            Text(Telemetry.format(command.seconds))
                .font(.uiCaption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

extension Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 1 { return "\(Int(seconds))s" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}
