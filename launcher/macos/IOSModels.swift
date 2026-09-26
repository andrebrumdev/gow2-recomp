import Foundation

// MARK: - devicectl data (P3). Parsed from `xcrun devicectl … -j <file>`
// (devicectl 642.16; the facts behind each choice: docs/superpowers/specs/
// 2026-09-25-ios-p3-devicectl-facts.md in the ps3recomp monorepo).

struct IOSDevice: Equatable {
    let udid: String          // hardwareProperties.udid: what --device and local.env take
    let name: String
    let model: String         // "iPhone 14"
    let osVersion: String
    let transport: String     // "wired" (USB), "localNetwork" (Wi-Fi), …
    let paired: Bool
    let booted: Bool
    let developerMode: Bool
    var overWiFi: Bool { transport == "localNetwork" }
}

struct IOSLockState: Equatable {
    let passcodeRequired: Bool
    let unlockedSinceBoot: Bool
}

struct IOSApp: Equatable {
    let bundleID: String
    let name: String
    let url: String           // file:///private/var/containers/Bundle/Application/<UUID>/GoW2.app/
    let builtByDeveloper: Bool
}

struct RemoteFile: Equatable {
    let path: String          // relative to the listed subdirectory
    let size: Int64
    let mtime: Int64          // whole seconds (devicectl keeps the source mtime on copy)
    let isDirectory: Bool
}

/// Device behaviours measured once in P3 Task 1 (F1-F10) and recorded in
/// launcher/macos/ios_device_facts.json. nil = not measured: the dependent
/// feature stays blocked (F5) or takes the conservative path (F6, F7, F8).
struct DeviceFacts: Codable, Equatable {
    static let fileName = "ios_device_facts.json"
    var measured: String? = nil
    /// F5: `copy from` of a directory lands in <destination>/<name> (true) or in <destination> (false).
    var copyFromNestsDirectory: Bool? = nil
    /// F6: `copy to --remove-existing-content true` deletes destination files the source lacks.
    var removeExistingContentDeletesExtras: Bool? = nil
    /// F7: `lockState.passcodeRequired` is true exactly while the screen is locked.
    var lockStateTracksLock: Bool? = nil
    /// F8: moving Xcode's cached team profile away makes the next signed build get a fresh 7-day one.
    var retireProfileRenews: Bool? = nil

    /// Missing or unreadable file = nothing measured.
    static func load(_ url: URL) -> DeviceFacts {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(DeviceFacts.self, from: $0) } ?? DeviceFacts()
    }

    /// The copy inside the app bundle (build_app.sh puts it in Resources), else the checkout's.
    static func bundled(repo: URL) -> DeviceFacts {
        if let u = Bundle.main.url(forResource: "ios_device_facts", withExtension: "json") { return load(u) }
        return load(repo.appendingPathComponent("launcher/macos").appendingPathComponent(fileName))
    }
}

struct DeviceError: Error, Equatable {
    static let noDevice = 1000, notFound = 7000, locked = 10002
    /// A device behaviour the operation depends on was not measured yet (DeviceFacts nil).
    static let factMissing = -2
    let code: Int
    let domain: String
    let message: String
    var isLocked: Bool { code == DeviceError.locked }
    var isNotFound: Bool { code == DeviceError.notFound }
    var userMessage: String {
        switch code {
        case DeviceError.locked:
            return "O iPhone está bloqueado. Desbloqueie-o e deixe a tela ligada (Ajustes → Tela e Brilho → Bloqueio Automático → Nunca, durante a instalação) e tente de novo — a cópia continua de onde parou."
        case DeviceError.noDevice:
            return "iPhone não encontrado. Conecte o cabo USB, desbloqueie o iPhone e toque em Confiar se ele pedir."
        case DeviceError.factMissing:
            return "O launcher ainda não sabe como o devicectl se comporta neste caso (\(message)). Registre o fato em launcher/macos/ios_device_facts.json (Task 1 do plano P3) antes de usar esta função."
        default:
            return "Erro do devicectl (\(domain) \(code)): \(message)"
        }
    }
}

/// What the launcher needs from the phone. Production: DevicectlTransport
/// (IOSDevicectl.swift); tests: FakeTransport. `remote` paths are relative to
/// the app's data container ("Documents/…").
protocol DeviceTransport: AnyObject {
    func devices() throws -> [IOSDevice]
    func lockState(_ device: String) throws -> IOSLockState
    func apps(_ device: String) throws -> [IOSApp]
    func processes(_ device: String) throws -> [String]
    /// Every entry under `dir`, paths relative to it; DeviceError 7000 when `dir` is absent.
    func files(_ device: String, bundle: String, under dir: String) throws -> [RemoteFile]
    func copyFileTo(_ device: String, bundle: String, local: URL, remote: String) throws
    /// `remote` ends up holding `local`'s contents (not local's name inside it).
    func copyDirectoryTo(_ device: String, bundle: String, local: URL, remote: String, removeExisting: Bool) throws
    func copyFileFrom(_ device: String, bundle: String, remote: String, local: URL) throws
    /// `local` (a directory) receives `remote`'s contents.
    func copyDirectoryFrom(_ device: String, bundle: String, remote: String, local: URL) throws
    /// Stops the operation in flight (it then throws); later calls work again.
    func cancel()
}

enum DevicectlJSON {
    /// The `result` object, or the DeviceError of a failed command.
    static func result(_ data: Data) throws -> [String: Any] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DeviceError(code: -1, domain: "devicectl", message: "saída JSON ilegível")
        }
        if let e = error(o) { throw e }
        return (o["result"] as? [String: Any]) ?? [:]
    }

    static func error(_ o: [String: Any]) -> DeviceError? {
        guard let info = o["info"] as? [String: Any], let outcome = info["outcome"] as? String,
              outcome != "success" else { return nil }
        let e = (o["error"] as? [String: Any]) ?? [:]
        let desc = ((e["userInfo"] as? [String: Any])?["NSLocalizedDescription"] as? [String: Any])?["string"] as? String
        let code = contains(e, code: DeviceError.locked) ? DeviceError.locked : ((e["code"] as? Int) ?? -1)
        return DeviceError(code: code, domain: (e["domain"] as? String) ?? "", message: desc ?? outcome)
    }

    /// 10002 can sit under NSUnderlyingError: search the whole error tree.
    private static func contains(_ v: Any, code: Int) -> Bool {
        if let d = v as? [String: Any] {
            if (d["code"] as? Int) == code { return true }
            return d.values.contains { contains($0, code: code) }
        }
        if let a = v as? [Any] { return a.contains { contains($0, code: code) } }
        return false
    }

    static func devices(_ data: Data) throws -> [IOSDevice] {
        let r = try result(data)
        return ((r["devices"] as? [[String: Any]]) ?? []).compactMap { d in
            let hw = (d["hardwareProperties"] as? [String: Any]) ?? [:]
            let dp = (d["deviceProperties"] as? [String: Any]) ?? [:]
            let cp = (d["connectionProperties"] as? [String: Any]) ?? [:]
            guard (hw["reality"] as? String) == "physical", (hw["platform"] as? String) == "iOS",
                  let udid = hw["udid"] as? String else { return nil }
            return IOSDevice(udid: udid, name: (dp["name"] as? String) ?? "iPhone",
                             model: (hw["marketingName"] as? String) ?? "iPhone",
                             osVersion: (dp["osVersionNumber"] as? String) ?? "?",
                             transport: (cp["transportType"] as? String) ?? "",
                             paired: (cp["pairingState"] as? String) == "paired",
                             booted: (dp["bootState"] as? String) == "booted",
                             developerMode: (dp["developerModeStatus"] as? String) == "enabled")
        }
    }

    static func lockState(_ data: Data) throws -> IOSLockState {
        let r = try result(data)
        return IOSLockState(passcodeRequired: (r["passcodeRequired"] as? Bool) ?? false,
                            unlockedSinceBoot: (r["unlockedSinceBoot"] as? Bool) ?? false)
    }

    static func apps(_ data: Data) throws -> [IOSApp] {
        let r = try result(data)
        return ((r["apps"] as? [[String: Any]]) ?? []).compactMap { a in
            guard let id = a["bundleIdentifier"] as? String else { return nil }
            return IOSApp(bundleID: id, name: (a["name"] as? String) ?? id, url: (a["url"] as? String) ?? "",
                          builtByDeveloper: (a["builtByDeveloper"] as? Bool) ?? false)
        }
    }

    static func processes(_ data: Data) throws -> [String] {
        let r = try result(data)
        return ((r["runningProcesses"] as? [[String: Any]]) ?? []).compactMap { $0["executable"] as? String }
    }

    static func files(_ data: Data) throws -> [RemoteFile] {
        let r = try result(data)
        return ((r["files"] as? [[String: Any]]) ?? []).compactMap { f in
            guard let path = f["relativePath"] as? String else { return nil }
            let m = (f["metadata"] as? [String: Any]) ?? [:]
            let res = (f["resources"] as? [String: Any]) ?? [:]
            return RemoteFile(path: path, size: (m["size"] as? NSNumber)?.int64Value ?? 0,
                              mtime: (m["lastModDate"] as? String).flatMap(seconds) ?? 0,
                              isDirectory: (res["isDirectory"] as? Bool) ?? false)
        }
    }

    /// "2026-09-02T20:19:45.000Z" -> Unix seconds (floor).
    static func seconds(_ iso: String) -> Int64? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return Int64(d.timeIntervalSince1970.rounded(.down)) }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso).map { Int64($0.timeIntervalSince1970.rounded(.down)) }
    }
}

enum IOSPolicy {
    /// local.env's device when connected, else the only one; nil = none or ambiguous.
    static func pickDevice(_ devices: [IOSDevice], preferred: String) -> IOSDevice? {
        if let d = devices.first(where: { $0.udid == preferred }) { return d }
        return devices.count == 1 ? devices[0] : nil
    }

    /// F7 measured true: `passcodeRequired` means locked. Otherwise (false or not
    /// measured) the lock is reported only through a 10002 failure (DeviceError).
    static func isLocked(_ s: IOSLockState, facts: DeviceFacts) -> Bool {
        facts.lockStateTracksLock == true && s.passcodeRequired
    }

    private static func norm(_ u: String) -> String {
        var s = u.hasPrefix("file://") ? String(u.dropFirst(7)) : u
        if s.hasPrefix("/private/") { s = String(s.dropFirst(8)) }
        return s
    }

    /// A process whose executable lives in the app's bundle (a suspended app counts).
    static func appRunning(executables: [String], appURL: String) -> Bool {
        guard !appURL.isEmpty else { return false }
        var base = norm(appURL)
        if !base.hasSuffix("/") { base += "/" }
        return executables.contains { norm($0).hasPrefix(base) }
    }

    /// `ps -axo comm=` output: the GoW2 binaries the launcher, jogar_g2.sh and the
    /// test scripts start (g2play, boot_gow2, boot_gow2_<tag>).
    static func macGameRunning(psComm: String) -> Bool {
        psComm.split(separator: "\n").contains { line in
            let name = String(line.split(separator: "/").last ?? "")
            return name.range(of: "^(g2play|boot_gow2(_[A-Za-z0-9]+)?)$", options: .regularExpression) != nil
        }
    }
}
