import Foundation

enum Devicectl {
    enum Op: Equatable {
        case devices
        case lockState(String)
        case apps(String)
        case processes(String)
        case files(String, bundle: String, dir: String)
        case copyTo(String, bundle: String, local: String, remote: String, removeExisting: Bool)
        case copyFrom(String, bundle: String, remote: String, local: String)
    }

    /// Where a `copy from` of directory `remote` put its contents inside the fresh
    /// directory `tmp`, per the recorded fact F5; not measured -> refuse (the
    /// save sync is blocked until Task 1 records it).
    static func contentsRoot(tmp: URL, remote: String, facts: DeviceFacts) throws -> URL {
        guard let nests = facts.copyFromNestsDirectory else {
            throw DeviceError(code: DeviceError.factMissing, domain: "facts", message: "F5: copy from de uma pasta")
        }
        return nests ? tmp.appendingPathComponent((remote as NSString).lastPathComponent) : tmp
    }

    static func args(_ op: Op, json: String) -> [String] {
        let tail = ["-j", json, "-q"]
        func container(_ d: String, _ b: String) -> [String] {
            ["--device", d, "--domain-type", "appDataContainer", "--domain-identifier", b]
        }
        switch op {
        case .devices:
            return ["devicectl", "list", "devices", "-t", "30"] + tail
        case .lockState(let d):
            return ["devicectl", "device", "info", "lockState", "--device", d, "-t", "30"] + tail
        case .apps(let d):
            return ["devicectl", "device", "info", "apps", "--device", d, "-t", "60"] + tail
        case .processes(let d):
            return ["devicectl", "device", "info", "processes", "--device", d, "-t", "60"] + tail
        case .files(let d, let b, let dir):
            return ["devicectl", "device", "info", "files"] + container(d, b) + ["--subdirectory", dir, "-t", "120"] + tail
        case .copyTo(let d, let b, let local, let remote, let r):
            return ["devicectl", "device", "copy", "to"] + container(d, b) + ["--source", local, "--destination", remote]
                + (r ? ["--remove-existing-content", "true"] : []) + tail
        case .copyFrom(let d, let b, let remote, let local):
            return ["devicectl", "device", "copy", "from"] + container(d, b) + ["--source", remote, "--destination", local] + tail
        }
    }
}

/// `xcrun devicectl … -j <tmp> -q`: results and errors come from the JSON file.
final class DevicectlTransport: DeviceTransport {
    let developerDir: String
    let facts: DeviceFacts
    private let lock = NSLock()
    private var current: Process?
    private var cancelRequested = false

    init(facts: DeviceFacts, developerDir: String = "/Applications/Xcode.app/Contents/Developer") {
        self.facts = facts
        self.developerDir = developerDir
    }

    func cancel() {
        lock.lock()
        cancelRequested = true
        if let p = current, p.isRunning { p.terminate() }
        lock.unlock()
    }

    @discardableResult
    private func run(_ op: Devicectl.Op) throws -> Data {
        let json = FileManager.default.temporaryDirectory.appendingPathComponent("devicectl-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: json) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = Devicectl.args(op, json: json.path)
        var env = ProcessInfo.processInfo.environment
        env["DEVELOPER_DIR"] = env["DEVELOPER_DIR"] ?? developerDir
        p.environment = env
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        lock.lock()
        cancelRequested = false            // a cancel only stops the command in flight
        lock.unlock()
        try p.run()
        // `current` is published only once the process runs: terminate() on a Process
        // that never launched raises NSInvalidArgumentException. A cancel that arrived
        // between the reset above and here is honoured at once. (If run() throws,
        // `current` was never set.)
        lock.lock()
        current = p
        if cancelRequested { p.terminate() }
        lock.unlock()
        let stderrText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        lock.lock()
        current = nil
        let wasCancelled = cancelRequested
        cancelRequested = false
        lock.unlock()
        if wasCancelled { throw PushError.cancelled }
        guard let data = try? Data(contentsOf: json) else {
            throw DeviceError(code: Int(p.terminationStatus), domain: "devicectl",
                              message: stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        _ = try DevicectlJSON.result(data)       // throws the command's DeviceError
        return data
    }

    func devices() throws -> [IOSDevice] { try DevicectlJSON.devices(run(.devices)) }
    func lockState(_ device: String) throws -> IOSLockState { try DevicectlJSON.lockState(run(.lockState(device))) }
    func apps(_ device: String) throws -> [IOSApp] { try DevicectlJSON.apps(run(.apps(device))) }
    func processes(_ device: String) throws -> [String] { try DevicectlJSON.processes(run(.processes(device))) }

    func files(_ device: String, bundle: String, under dir: String) throws -> [RemoteFile] {
        try DevicectlJSON.files(run(.files(device, bundle: bundle, dir: dir)))
    }

    func copyFileTo(_ device: String, bundle: String, local: URL, remote: String) throws {
        try run(.copyTo(device, bundle: bundle, local: local.path, remote: remote, removeExisting: false))
    }

    func copyDirectoryTo(_ device: String, bundle: String, local: URL, remote: String, removeExisting: Bool) throws {
        try run(.copyTo(device, bundle: bundle, local: local.path, remote: remote, removeExisting: removeExisting))
    }

    func copyFileFrom(_ device: String, bundle: String, remote: String, local: URL) throws {
        try run(.copyFrom(device, bundle: bundle, remote: remote, local: local.path))
    }

    /// Always into a fresh temp dir, then the contents are moved into `local`,
    /// so the result does not depend on whether `local` existed (facts F5).
    func copyDirectoryFrom(_ device: String, bundle: String, remote: String, local: URL) throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("devicectl-from-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        _ = try Devicectl.contentsRoot(tmp: tmp, remote: remote, facts: facts)   // refuse before touching the phone
        try run(.copyFrom(device, bundle: bundle, remote: remote, local: tmp.path))
        let src = try Devicectl.contentsRoot(tmp: tmp, remote: remote, facts: facts)
        try fm.createDirectory(at: local, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(atPath: src.path) {
            let dst = local.appendingPathComponent(item)
            try? fm.removeItem(at: dst)
            try fm.moveItem(at: src.appendingPathComponent(item), to: dst)
        }
    }
}
