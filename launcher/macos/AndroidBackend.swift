import Foundation

/// The Android screen's model (spec 2026-09-29-gow2-android-design): find the phone/tablet over adb,
/// check the build prerequisites, and run the steps the scripts already implement --
/// android/build_android.sh (port) and tools/android/install_android.sh (engine). The APK is
/// built on this Mac from the user's own data and installed only on the user's own device.

struct AndroidDevice: Equatable {
    let serial: String
    let state: String      // device | unauthorized | offline | no permissions
    let model: String
}

struct AndroidPrereq: Equatable, Identifiable {
    let id: String
    let title: String
    let ok: Bool
    let hint: String
}

enum AndroidOperation: String {
    case buildingProbe = "Preparando o instalador…"
    case bootstrapping = "Preparando o aparelho…"
    case building = "Compilando o app (leva vários minutos)…"
    case installing = "Instalando no aparelho…"
    case installingData = "Instalando e copiando o jogo (≈ 7 GB)…"
}

/// One script invocation of the install sequence.
enum AndroidStep: Equatable {
    case buildProbe
    case bootstrap
    case buildGame
    case install(data: Bool)

    var operation: AndroidOperation {
        switch self {
        case .buildProbe: return .buildingProbe
        case .bootstrap: return .bootstrapping
        case .buildGame: return .building
        case .install(let data): return data ? .installingData : .installing
        }
    }
    var logName: String {
        switch self {
        case .buildProbe: return "android-probe-build.log"
        case .bootstrap: return "android-bootstrap.log"
        case .buildGame: return "android-build.log"
        case .install: return "android-install.log"
        }
    }
}

enum AndroidText {
    /// `adb devices -l`: "SERIAL  device usb:… product:… model:SM_X610 device:… transport_id:1".
    static func parseDevices(_ output: String) -> [AndroidDevice] {
        var out: [AndroidDevice] = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("List of devices") || line.hasPrefix("*") { continue }
            let t = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard t.count >= 2 else { continue }
            var state = t[1]
            if state == "no", t.count > 2, t[2].hasPrefix("permissions") { state = "no permissions" }
            let model = t.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") } ?? t[0]
            out.append(AndroidDevice(serial: t[0], state: state, model: model))
        }
        return out
    }

    /// The device the install would use: the first one that is ready.
    static func ready(_ devices: [AndroidDevice]) -> AndroidDevice? { devices.first { $0.state == "device" } }

    static func deviceLine(_ devices: [AndroidDevice]) -> String {
        if let d = ready(devices) {
            let more = devices.count > 1 ? " Há mais de um aparelho ligado: será usado este." : ""
            return "\(d.model) pronto para instalar (\(d.serial)).\(more)"
        }
        guard let d = devices.first else {
            return "Nenhum aparelho Android encontrado. Ligue-o ao Mac por USB e ative a Depuração USB (Opções do desenvolvedor). Em aparelhos Samsung, desligue também o Bloqueador automático (Configurações → Segurança e privacidade)."
        }
        switch d.state {
        case "unauthorized":
            return "\(d.model) conectado, mas ainda não autorizado: na tela do aparelho, toque em \"Permitir depuração USB\" (marque \"Sempre permitir deste computador\")."
        case "offline":
            return "\(d.model) aparece como offline: desconecte e conecte o cabo de novo e destrave a tela."
        case "no permissions":
            return "\(d.model) sem permissão de acesso: desconecte e conecte o cabo de novo."
        default:
            return "\(d.model) está em um estado não esperado (\(d.state)): desconecte e conecte o cabo de novo."
        }
    }

    /// Message for a failed step (exit codes of device_txn.sh; the log has the details).
    static func stepError(_ step: AndroidStep, status: Int32, logPath: String) -> String {
        switch step {
        case .buildProbe, .buildGame:
            return "A compilação para Android falhou (log em \(logPath))."
        case .bootstrap, .install:
            switch status {
            case 21: return "A confirmação de que o aparelho é seu não foi registrada. Nada foi instalado."
            case 30: return "A instalação foi interrompida antes de gravar no aparelho: nada foi alterado (log em \(logPath))."
            case 31: return "A instalação falhou e foi desfeita: o aparelho ficou como estava (log em \(logPath))."
            case 32: return "ATENÇÃO: a instalação falhou e o desfazer também falhou. Não use o app no aparelho até reinstalar; os backups dos saves ficam em ~/Documents/PESSOAL/gow2-saves (log em \(logPath))."
            default: return "A instalação no Android falhou (código \(status); log em \(logPath))."
            }
        }
    }
}

enum AndroidScripts {
    static let ndkVersion = "27.2.12479018"
    static let buildTools = "35.0.0"
    static let platform = "android-34"

    /// The engine checkout with tools/android: GOW2_ENGINE_ROOT / PS3_ENGINE_ROOT, else the ps3recomp
    /// next to the port (its "android" worktree until the Android work is merged into it).
    static func engineRoot(repo: URL, env: [String: String],
                           exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL {
        if let p = env["GOW2_ENGINE_ROOT"] ?? env["PS3_ENGINE_ROOT"], !p.isEmpty { return URL(fileURLWithPath: p) }
        let sib = repo.deletingLastPathComponent().appendingPathComponent("ps3recomp")
        for c in [sib, sib.appendingPathComponent(".worktrees/android")]
        where exists(c.appendingPathComponent("tools/android/install_android.sh").path) { return c }
        return sib
    }
    /// The port's own android/build_android.sh, else the engine's games/gow2 copy (the monorepo layout
    /// build_android.sh understands: the engine is the checkout that sits two levels above it).
    static func buildScript(repo: URL, engine: URL,
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL {
        let own = repo.appendingPathComponent("android/build_android.sh")
        if exists(own.path) { return own }
        let viaEngine = engine.appendingPathComponent("games/gow2/android/build_android.sh")
        return exists(viaEngine.path) ? viaEngine : own
    }
    static func installScript(engine: URL) -> URL { engine.appendingPathComponent("tools/android/install_android.sh") }
    /// Build output (SDL, FFmpeg, shaderc, runtime, objects, APKs): kept next to the engine, never in the game folder.
    static func buildDir(engine: URL, env: [String: String]) -> URL {
        if let p = env["GOW2_ANDROID_BUILD"], !p.isEmpty { return URL(fileURLWithPath: p) }
        return engine.appendingPathComponent("build-android")
    }
    static func transportFile(engine: URL, env: [String: String]) -> URL {
        if let p = env["GOW2_TRANSPORT_FILE"], !p.isEmpty { return URL(fileURLWithPath: p) }
        return engine.appendingPathComponent("tools/android/device_transport.env")
    }

    static func sdkRoot(env: [String: String], home: URL, exists: (String) -> Bool) -> String? {
        let c: [String?] = [env["ANDROID_SDK_ROOT"], env["ANDROID_HOME"], "/opt/homebrew/share/android-commandlinetools",
                            home.appendingPathComponent("Library/Android/sdk").path]
        return c.compactMap { $0 }.first { !$0.isEmpty && exists($0 + "/platform-tools") }
    }
    static func adb(env: [String: String], home: URL, exists: (String) -> Bool) -> URL? {
        sdkRoot(env: env, home: home, exists: exists).map { URL(fileURLWithPath: $0 + "/platform-tools/adb") }
    }

    /// A Finder-launched app has PATH=/usr/bin:/bin:…: cmake and ninja live in Homebrew, and the
    /// build needs a JDK 17 (javac/d8) and a Python >= 3.11 (system python3 is 3.9).
    static func environment(_ base: [String: String], repo: URL, engine: URL, home: URL,
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [String: String] {
        var e = base
        let jdk = "/opt/homebrew/opt/openjdk@17"
        var path = base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var front = ["/opt/homebrew/bin", "/usr/local/bin"]
        if exists(jdk + "/bin/javac") { front.insert(jdk + "/bin", at: 0); if e["JAVA_HOME"] == nil { e["JAVA_HOME"] = jdk } }
        for p in front.reversed() where !path.split(separator: ":").contains(Substring(p)) { path = p + ":" + path }
        e["PATH"] = path
        if e["PY"] == nil, exists("/opt/homebrew/bin/python3") { e["PY"] = "/opt/homebrew/bin/python3" }
        e["GOW2_WORK"] = repo.path
        e["PS3_ENGINE_ROOT"] = engine.path
        e["GOW2_ANDROID_BUILD"] = buildDir(engine: engine, env: base).path
        e["GOW2_TRANSPORT_FILE"] = transportFile(engine: engine, env: base).path
        return e
    }

    static func prerequisites(repo: URL, engine: URL, env: [String: String], home: URL,
                              exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [AndroidPrereq] {
        let sdk = sdkRoot(env: env, home: home, exists: exists)
        let s = sdk ?? ""
        return [
            AndroidPrereq(id: "scripts", title: "Scripts do Android nesta cópia do projeto",
                          ok: exists(buildScript(repo: repo, engine: engine, exists: exists).path) && exists(installScript(engine: engine).path),
                          hint: "Esta cópia do projeto ainda não tem o suporte a Android (android/build_android.sh e tools/android/install_android.sh)."),
            AndroidPrereq(id: "sdk", title: "Android SDK (platform-tools, build-tools e plataforma)",
                          ok: sdk != nil && exists("\(s)/build-tools/\(buildTools)/apksigner") && exists("\(s)/platforms/\(platform)/android.jar"),
                          hint: "Instale com: brew install --cask android-commandlinetools, e depois tools/android/install_ndk.sh."),
            AndroidPrereq(id: "ndk", title: "Android NDK \(ndkVersion)",
                          ok: sdk != nil && exists("\(s)/ndk/\(ndkVersion)/source.properties"),
                          hint: "Rode tools/android/install_ndk.sh (baixa e confere o NDK)."),
            AndroidPrereq(id: "jdk", title: "Java JDK 17",
                          ok: exists("/opt/homebrew/opt/openjdk@17/bin/javac") || (env["JAVA_HOME"].map { exists($0 + "/bin/javac") } ?? false),
                          hint: "Instale com: brew install openjdk@17."),
            AndroidPrereq(id: "tools", title: "cmake e ninja",
                          ok: exists("/opt/homebrew/bin/cmake") && exists("/opt/homebrew/bin/ninja"),
                          hint: "Instale com: brew install cmake ninja."),
            AndroidPrereq(id: "python", title: "Python 3.11 ou mais novo",
                          ok: exists("/opt/homebrew/bin/python3") || env["PY"] != nil,
                          hint: "Instale com: brew install python."),
        ]
    }

    /// The steps for one install: a phone without the transport record proven yet gets the
    /// lift-free probe APK first (B0); the game APK is always rebuilt (incremental) and installed.
    static func plan(transportProven: Bool, probeApkExists: Bool, data: Bool) -> [AndroidStep] {
        var s: [AndroidStep] = []
        if !transportProven {
            if !probeApkExists { s.append(.buildProbe) }
            s.append(.bootstrap)
        }
        s.append(.buildGame)
        s.append(.install(data: data))
        return s
    }

    static func arguments(_ step: AndroidStep, serial: String, ownConfirmed: Bool) -> (script: String, args: [String]) {
        let own = ownConfirmed ? ["--i-own-this-device"] : []
        switch step {
        case .buildProbe: return ("build", ["--probe-only"])
        case .bootstrap: return ("install", ["--bootstrap", "--serial", serial] + own)
        case .buildGame: return ("build", [])
        case .install(let data): return ("install", ["--serial", serial] + (data ? ["--data"] : []) + own)
        }
    }

    /// True when the ownership record already has this serial (the scripts keep the real verdict).
    static func ownershipRecorded(serial: String, home: URL,
                                  read: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }) -> Bool {
        let rec = home.appendingPathComponent("Library/Application Support/GoW2 Recomp/android_ownership.json")
        return read(rec)?.contains("\"device_serial\":\"\(serial)\"") ?? false
    }
}

@MainActor
final class AndroidBackend: ObservableObject {
    @Published private(set) var device: AndroidDevice?
    @Published private(set) var deviceLine = "Procurando o aparelho Android…"
    @Published private(set) var prereqs: [AndroidPrereq] = []
    @Published private(set) var busy: AndroidOperation?
    @Published private(set) var progress = ""
    @Published private(set) var lastResult: String?
    @Published private(set) var error: String?
    /// The ownership dialog (first install on a device): the view binds its alert to this.
    @Published var askOwnership = false

    let repo: URL
    private let env: [String: String]
    private let home: URL
    private let runner: ScriptRunning
    private let exists: (String) -> Bool
    private var pendingData = false
    private var progressTask: Task<Void, Never>?

    init(repo: URL, runner: ScriptRunning = ProcessScriptRunner(),
         env: [String: String] = ProcessInfo.processInfo.environment,
         home: URL = FileManager.default.homeDirectoryForCurrentUser,
         exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.repo = repo; self.runner = runner; self.env = env; self.home = home; self.exists = exists
    }

    var engine: URL { AndroidScripts.engineRoot(repo: repo, env: env, exists: exists) }
    var deviceReady: Bool { device?.state == "device" }
    var missingPrereqs: Bool { prereqs.contains { !$0.ok } }
    var logsDir: URL { home.appendingPathComponent("Library/Logs/GoW2Recomp") }
    var canInstall: Bool { busy == nil && deviceReady && !missingPrereqs }

    func refresh() async {
        prereqs = AndroidScripts.prerequisites(repo: repo, engine: engine, env: env, home: home, exists: exists)
        guard let adb = AndroidScripts.adb(env: env, home: home, exists: exists) else {
            device = nil
            deviceLine = "O adb (Android SDK) não foi encontrado: veja os requisitos abaixo."
            return
        }
        let out = await Task.detached { Self.capture(adb, ["devices", "-l"]) }.value
        let devices = AndroidText.parseDevices(out)
        device = AndroidText.ready(devices) ?? devices.first
        deviceLine = AndroidText.deviceLine(devices)
    }

    /// "Instalar": asks the ownership question first when this device has no record yet.
    func requestInstall(data: Bool) {
        guard canInstall, let d = device else { return }
        pendingData = data
        if AndroidScripts.ownershipRecorded(serial: d.serial, home: home) { Task { await runInstall(ownConfirmed: false) } }
        else { askOwnership = true }
    }

    func confirmOwnership() { Task { await runInstall(ownConfirmed: true) } }

    private func runInstall(ownConfirmed: Bool) async {
        guard busy == nil, let d = device, d.state == "device" else { return }
        error = nil; lastResult = nil
        let repo = self.repo, engine = self.engine
        let scriptEnv = AndroidScripts.environment(env, repo: repo, engine: engine, home: home, exists: exists)
        let buildDir = AndroidScripts.buildDir(engine: engine, env: env)
        let transport = AndroidScripts.transportFile(engine: engine, env: env)
        let steps = AndroidScripts.plan(transportProven: exists(transport.path),
                                        probeApkExists: exists(buildDir.appendingPathComponent("gow2-probe.apk").path),
                                        data: pendingData)
        defer { busy = nil; progress = ""; progressTask?.cancel() }
        for step in steps {
            busy = step.operation
            let (which, args) = AndroidScripts.arguments(step, serial: d.serial, ownConfirmed: ownConfirmed)
            let script = which == "build" ? AndroidScripts.buildScript(repo: repo, engine: engine, exists: exists) : AndroidScripts.installScript(engine: engine)
            let log = logsDir.appendingPathComponent(step.logName)
            startProgress(log)
            let runner = self.runner
            let result: Result<ScriptResult, Error> = await Task.detached {
                Result { try runner.run(script, args, env: scriptEnv, log: log) }
            }.value
            progressTask?.cancel()
            switch result {
            case .failure(let e):
                error = "Não consegui executar \(script.lastPathComponent): \(e.localizedDescription)"; return
            case .success(let r) where r.status != 0:
                error = AndroidText.stepError(step, status: r.status, logPath: log.path.replacingOccurrences(of: home.path, with: "~")); return
            case .success:
                continue
            }
        }
        lastResult = pendingData ? "Instalado com o jogo. Abra \"God of War II\" na lista de aplicativos do aparelho."
                                 : "App instalado. Se o jogo ainda não estiver no aparelho, use \"Instalar com o jogo\"."
        await refresh()
    }

    /// Shows the last line of the running step's log every couple of seconds.
    private func startProgress(_ log: URL) {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let text = try? String(contentsOf: log, encoding: .utf8),
                   let line = text.split(whereSeparator: \.isNewline).last {
                    self?.progress = String(line.prefix(160))
                }
            }
        }
    }

    nonisolated private static func capture(_ exe: URL, _ args: [String]) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = exe; p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
