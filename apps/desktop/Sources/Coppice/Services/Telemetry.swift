import Darwin
import Foundation

final class Telemetry: @unchecked Sendable {
    static let shared = Telemetry()

    struct Command: Sendable, Hashable {
        let label: String
        let seconds: Double
        let status: Int32
    }

    struct Phase: Sendable, Hashable {
        let name: String
        let start: Double
        let seconds: Double
        var background = false
    }

    struct Scan: Sendable, Hashable {
        let date: Date
        var phases: [Phase]
        let commands: Int

        var seconds: Double {
            phases.filter { !$0.background }.map { $0.start + $0.seconds }.max() ?? 0
        }
    }

    struct Usage: Sendable, Equatable {
        let date: Date
        let memory: Int64
        let cpuSeconds: Double
        let threads: Int

        func cpuPercent(since earlier: Usage?) -> Double {
            guard let earlier, date > earlier.date else { return 0 }
            return max(0, (cpuSeconds - earlier.cpuSeconds) / date.timeIntervalSince(earlier.date) * 100)
        }
    }

    struct Sample: Sendable, Hashable {
        let date: Date
        let memory: Int64
        let cpu: Double
    }

    struct Watcher: Sendable, Equatable {
        var folders = 0
        var changes = 0
        var lastChange: Date?
    }

    struct Snapshot: Sendable {
        let slowest: [Command]
        let commandCount: Int
        let lastScan: Scan?
        let samples: [Sample]
        let watcher: Watcher
        let recordingUntil: Date?
    }

    let launchedAt = Date()
    private let onHang: @Sendable (Double, String) -> Void
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.syntaxlabtechnology.coppice.telemetry", qos: .utility)
    private var slowest: [Command] = []
    private var commandCount = 0
    private var lastScan: Scan?
    private var samples: [Sample] = []
    private var watcher = Watcher()
    private var activity = "idle"
    private var recordingUntil: Date?
    private var sampler: DispatchSourceTimer?
    private var watchdog: DispatchSourceTimer?
    private var pingPending = false
    private var lastSampled: Usage?

    init(onHang: @escaping @Sendable (Double, String) -> Void = { seconds, during in
        Log.shared.write("HANG  main thread blocked for \(Telemetry.format(seconds)) during \(during)")
    }) {
        self.onHang = onHang
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var commands: Int { locked { commandCount } }

    var isRecording: Bool { locked { recordingUntil.map { $0 > Date() } ?? false } }

    func snapshot() -> Snapshot {
        locked {
            Snapshot(
                slowest: slowest,
                commandCount: commandCount,
                lastScan: lastScan,
                samples: samples,
                watcher: watcher,
                recordingUntil: recordingUntil.flatMap { $0 > Date() ? $0 : nil }
            )
        }
    }

    func record(command label: String, seconds: Double, status: Int32) {
        let recording = locked { () -> Bool in
            commandCount += 1
            if slowest.count < 8 || seconds > (slowest.last?.seconds ?? 0) {
                slowest.append(Command(label: label, seconds: seconds, status: status))
                slowest.sort { $0.seconds > $1.seconds }
                if slowest.count > 8 { slowest.removeLast() }
            }
            return recordingUntil.map { $0 > Date() } ?? false
        }
        if recording {
            Log.shared.write("cmd  \(label)  \(Self.format(seconds))  exit \(status)")
        }
    }

    func record(scan: Scan) {
        locked { lastScan = scan }
    }

    func record(sizing seconds: Double, count: Int) {
        locked {
            guard var scan = lastScan else { return }
            scan.phases.removeAll(where: \.background)
            let name = "Sizing \(count) worktree\(count == 1 ? "" : "s")"
            scan.phases.append(Phase(name: name, start: scan.seconds, seconds: seconds, background: true))
            lastScan = scan
        }
    }

    func setActivity(_ label: String) {
        locked { activity = label.isEmpty ? "idle" : label.prefix(1).lowercased() + label.dropFirst() }
    }

    func watching(folders: Int) {
        locked { watcher.folders = folders }
    }

    func noticedChange() {
        locked {
            watcher.changes += 1
            watcher.lastChange = Date()
        }
    }

    func record(for duration: TimeInterval?) {
        locked { recordingUntil = duration.map { Date().addingTimeInterval($0) } }
        if let duration {
            Log.shared.write("recording every command for \(Int(duration / 60)) minutes")
        } else {
            Log.shared.write("recording stopped")
        }
    }

    func startSampling() {
        queue.async { [self] in
            guard sampler == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 30, leeway: .seconds(5))
            timer.setEventHandler { [weak self] in self?.sample() }
            timer.resume()
            sampler = timer
        }
    }

    func startWatchdog() {
        queue.async { [self] in
            guard watchdog == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.ping() }
            timer.resume()
            watchdog = timer
        }
    }

    func stopWatchdog() {
        queue.async { [self] in
            watchdog?.cancel()
            watchdog = nil
        }
    }

    private func sample() {
        let usage = Self.usage()
        let cpu = usage.cpuPercent(since: lastSampled)
        lastSampled = usage
        locked {
            samples.append(Sample(date: usage.date, memory: usage.memory, cpu: cpu))
            if samples.count > 120 { samples.removeFirst(samples.count - 120) }
        }
    }

    private func ping() {
        guard !pingPending else { return }
        pingPending = true
        let sent = DispatchTime.now()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - sent.uptimeNanoseconds) / 1_000_000_000
            self.queue.async { self.pingPending = false }
            guard seconds > 0.25 else { return }
            self.onHang(seconds, self.locked { self.activity })
        }
    }

    static func usage() -> Usage {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        var times = rusage()
        getrusage(RUSAGE_SELF, &times)
        let cpu = Double(times.ru_utime.tv_sec + times.ru_stime.tv_sec)
            + Double(times.ru_utime.tv_usec + times.ru_stime.tv_usec) / 1_000_000
        var task = proc_taskinfo()
        let size = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &task, Int32(MemoryLayout<proc_taskinfo>.size))
        return Usage(
            date: Date(),
            memory: status == 0 ? Int64(info.ri_phys_footprint) : 0,
            cpuSeconds: cpu,
            threads: size > 0 ? Int(task.pti_threadnum) : 0
        )
    }

    static func label(_ executable: String, _ arguments: [String], cwd: String?) -> String {
        var arguments = arguments
        var place = cwd.map { ($0 as NSString).lastPathComponent }
        if arguments.first == "-C", arguments.count > 1 {
            place = (arguments[1] as NSString).lastPathComponent
            arguments.removeFirst(2)
        }
        let command = ([(executable as NSString).lastPathComponent] + arguments.prefix(2)).joined(separator: " ")
        return place.map { "\(command) · \($0)" } ?? command
    }

    static func format(_ seconds: Double) -> String {
        seconds < 10 ? String(format: "%.2f s", seconds) : String(format: "%.1f s", seconds)
    }
}

struct PhaseClock {
    private let origin = Date()
    private(set) var phases: [Telemetry.Phase] = []

    mutating func measure<T>(_ name: String, _ body: () -> T) -> T {
        let start = Date()
        let value = body()
        phases.append(Telemetry.Phase(name: name, start: start.timeIntervalSince(origin), seconds: Date().timeIntervalSince(start)))
        return value
    }
}
