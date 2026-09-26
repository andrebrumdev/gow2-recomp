import Foundation

/// The launcher's one-activity lock shared by Jogar and the iPhone save sync
/// (Codex review 6). MainActor: taking it is check-and-set in one turn.
@MainActor
protocol GameRunState: AnyObject {
    var running: Bool { get }
    /// false when the game runs or another activity holds the launcher.
    func tryBeginExclusive(_ reason: String) -> Bool
    func endExclusive()
}

extension Backend: GameRunState {}

struct IOSDeps {
    var transport: DeviceTransport
    var scripts: ScriptRunning
    var readProfile: (URL) throws -> Data
    var xcodePrefs: () -> Data?
    /// `ps -axo comm=`; throws when the list cannot be read (the flows then refuse:
    /// an unreadable process list is never "the game is closed").
    var macProcesses: () throws -> String
    /// Recorded device behaviours (Task 1): F5 gates the save sync, F6 the phone
    /// replace, F7 the lock reading, F8 the profile rotation on re-sign.
    var facts: DeviceFacts
    var home: URL
    var now: () -> Date

    static func live(repo: URL) -> IOSDeps {
        let facts = DeviceFacts.bundled(repo: repo)
        return IOSDeps(transport: DevicectlTransport(facts: facts), scripts: ProcessScriptRunner(),
                       readProfile: { try Signing.decodeProfile($0) }, xcodePrefs: { Signing.readXcodePrefs() },
                       macProcesses: {
                           let out: String
                           do { out = try LauncherCore.run("/bin/ps", ["-axo", "comm="]) } catch { throw IOSFlowError.processListFailed }
                           return try checkedPS(out)
                       },
                       facts: facts, home: FileManager.default.homeDirectoryForCurrentUser, now: { Date() })
    }

    /// A `ps` that ran but listed nothing is a failure too (it always lists itself).
    static func checkedPS(_ output: String) throws -> String {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw IOSFlowError.processListFailed }
        return output
    }
}

enum IOSOperation: String {
    case refresh = "Procurando o iPhone…"
    case install = "Instalando no iPhone…"
    case resign = "Reassinando…"
    case saves = "Sincronizando os saves…"
}

struct IOSInstallRecord: Codable, Equatable {
    var expiry: Date?
    var installedAt: Date?
    var setID: String?
}

enum IOSFlowError: Error {
    case build(ScriptResult), install(ScriptResult), noProfile(String), notReady(String)
    case phoneAppRunning, notInstalled, missingSigning, configMismatch(String), processListFailed

    static func lastError(_ out: String) -> String {
        out.split(separator: "\n").last { $0.contains("error") || $0.contains("ERROR") }.map(String.init) ?? ""
    }

    var userMessage: String {
        switch self {
        case .build(let r):
            if let c = r.deviceErrorCode { return DeviceError(code: c, domain: "com.apple.dt.CoreDeviceError", message: "").userMessage }
            return "A compilação para iPhone falhou (log em ~/Library/Logs/GoW2Recomp/ios-build.log). " + IOSFlowError.lastError(r.output)
        case .install(let r):
            if let c = r.deviceErrorCode {
                return DeviceError(code: c, domain: "com.apple.dt.CoreDeviceError", message: IOSFlowError.lastError(r.output)).userMessage
            }
            return "A instalação no iPhone falhou (log em ~/Library/Logs/GoW2Recomp/ios-install.log). " + IOSFlowError.lastError(r.output)
        case .noProfile(let p):
            return "O app compilado não tem perfil de assinatura (\(p)). Confira a equipe escolhida e se o Xcode está com o seu Apple ID (Xcode → Ajustes → Contas)."
        case .notReady(let line):
            return line
        case .phoneAppRunning:
            return SaveSyncError.gameRunningPhone.userMessage
        case .notInstalled:
            return "O GoW2 com esse identificador não está neste iPhone: use Instalar no iPhone."
        case .missingSigning:
            return "Escolha a equipe (Apple ID) e o identificador do app antes de continuar."
        case .processListFailed:
            return "Não deu para ler a lista de processos do Mac para conferir se o GoW2 está aberto. Feche o jogo no Mac e tente de novo."
        case .configMismatch(let out):
            return "Os scripts do iOS leram outra configuração (ios/local.env ou variáveis GOW2_IOS_* no ambiente). Confira:\n\(out)"
        }
    }
}

/// pt-BR lines the iPhone screen shows.
enum IOSText {
    static func gb(_ b: Int64) -> String {
        String(format: "%.1f GB", Double(b) / 1e9).replacingOccurrences(of: ".", with: ",")
    }

    static func date(_ d: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.timeZone = timeZone
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: d)
    }

    static func deviceLine(_ d: IOSDevice, lock: IOSLockState, facts: DeviceFacts) -> String {
        if !d.paired { return "\(d.name): toque em Confiar no iPhone e procure de novo." }
        if !d.developerMode { return "\(d.name): ative o Modo de Desenvolvedor (Ajustes → Privacidade e Segurança → Modo de Desenvolvedor)." }
        if !d.booted { return "\(d.name) está desligado ou reiniciando." }
        if IOSPolicy.isLocked(lock, facts: facts) { return "\(d.name) está bloqueado — desbloqueie o iPhone e procure de novo." }
        return "\(d.model) “\(d.name)” · iOS \(d.osVersion) · "
            + (d.overWiFi ? "pelo Wi-Fi (lento para 7 GB: prefira o cabo USB)" : "pelo cabo")
    }

    static func hashing(_ done: Int64, _ total: Int64) -> String {
        "Conferindo os arquivos do jogo no Mac: \(gb(done)) de \(gb(total))"
    }

    static func copying(_ p: PushProgress) -> String {
        "Copiando \(p.file) (\(p.index) de \(p.count)) — \(gb(p.doneBytes)) de \(gb(p.totalBytes))"
    }

    static func installed(_ o: PushOutcome, badge: ExpiryBadge) -> String {
        switch o {
        case .alreadyInstalled:
            return "Instalado. O jogo já estava completo no iPhone. \(badge.text)."
        case .installed(let copied, let skipped):
            return "Instalado. \(copied) arquivo(s) copiado(s), \(skipped) já estavam no iPhone. \(badge.text)."
        }
    }

    static func syncResult(_ r: SaveSyncReport, mode: SyncMode) -> String {
        var parts: [String] = []
        if !r.recovered.isEmpty { parts.append("save do Mac recuperado de uma sincronia interrompida: " + r.recovered.joined(separator: ", ")) }
        if !r.missingSource.isEmpty {
            let source = mode == .phoneToMac ? "no iPhone" : "no Mac"
            parts.append("Nada copiado para " + r.missingSource.joined(separator: ", ") + ": não existe \(source); os dois lados continuam diferentes")
        }
        if !r.pushed.isEmpty { parts.append("Mac → iPhone: " + r.pushed.joined(separator: ", ")) }
        if !r.pulled.isEmpty { parts.append("iPhone → Mac: " + r.pulled.joined(separator: ", ")) }
        if !r.conflicts.isEmpty { parts.append("\(r.conflicts.count) conflito(s): escolha abaixo qual lado manter") }
        if parts.isEmpty { return "Os saves já estavam iguais no Mac e no iPhone." }
        if !r.backups.isEmpty { parts.append("cópia do lado substituído em " + r.backups.map(\.lastPathComponent).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    static func message(for error: Error) -> String {
        switch error {
        case let e as DeviceError: return e.userMessage
        case let e as PushError: return e.userMessage
        case let e as SaveSyncError: return e.userMessage
        case let e as InstallSources.Failure: return e.userMessage
        case let e as IOSFlowError: return e.userMessage
        case LocalEnvError.invalid(let key): return "Valor inválido para \(key): use só letras, números, ponto, hífen e sublinhado."
        default: return error.localizedDescription
        }
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
}

@MainActor
final class IOSBackend: ObservableObject {
    @Published private(set) var device: IOSDevice?
    @Published private(set) var deviceReady = false
    @Published private(set) var deviceLine = "Procurando o iPhone…"
    @Published private(set) var teams: [XcodeTeam] = []
    @Published var team = ""
    @Published var bundle = ""
    @Published private(set) var installedBundle: String?
    @Published private(set) var record = IOSInstallRecord()
    @Published private(set) var busy: IOSOperation?
    @Published private(set) var canCancel = false
    @Published private(set) var progress = ""
    @Published private(set) var error: String?
    @Published private(set) var lastResult: String?
    @Published private(set) var conflicts: [SaveConflict] = []

    let repo: URL
    let deps: IOSDeps
    weak var game: GameRunState?
    private let cancelFlag = CancelFlag()

    init(repo: URL, game: GameRunState?, deps: IOSDeps) {
        self.repo = repo
        self.game = game
        self.deps = deps
    }

    var badge: ExpiryBadge { Signing.badge(record.expiry, now: deps.now()) }

    var bundleWarning: String? {
        guard let installed = installedBundle, !bundle.isEmpty, installed != bundle else { return nil }
        return "O iPhone já tem o GoW2 com o identificador \(installed). Outro identificador instala um segundo app (a conta gratuita permite 3) e copia o jogo (7 GB) de novo."
    }

    var supportDir: URL { deps.home.appendingPathComponent("Library/Application Support/GoW2Recomp/ios") }
    var logsDir: URL { deps.home.appendingPathComponent("Library/Logs/GoW2Recomp") }
    var backupRootPath: String { backupRoot(LauncherCore.load(repo: repo)).path }

    private func deviceDir(_ d: IOSDevice) -> URL { supportDir.appendingPathComponent("\(d.udid)_\(bundle)") }
    private func staging() -> URL { supportDir.appendingPathComponent("staging") }

    private func backupRoot(_ c: LauncherConfig) -> URL {
        if let p = c.save_backup_dir, !p.isEmpty { return URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
        return SaveBackup.defaultRoot(home: deps.home)
    }

    private func off<T: Sendable>(_ work: @escaping () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }

    // MARK: device

    func refresh() async {
        guard busy == nil else { return }
        busy = .refresh
        defer { busy = nil }
        await refreshDevice()
    }

    private func refreshDevice() async {
        let env = LocalEnvFile.at(repo: repo).read()
        if team.isEmpty { team = env["GOW2_IOS_TEAM"] ?? "" }
        if bundle.isEmpty { bundle = env["GOW2_IOS_BUNDLE_ID"] ?? "" }
        teams = deps.xcodePrefs().map { Signing.teams(xcodePrefs: $0) } ?? []
        if team.isEmpty, teams.count == 1 { team = teams[0].id }
        let t = deps.transport
        let preferred = env["GOW2_IOS_DEVICE"] ?? ""
        deviceReady = false
        do {
            let list = try await off { try t.devices() }
            guard let d = IOSPolicy.pickDevice(list, preferred: preferred) else {
                device = nil
                installedBundle = nil
                deviceLine = list.isEmpty ? "Nenhum iPhone conectado. Conecte o cabo USB e desbloqueie o iPhone."
                                          : "Mais de um iPhone conectado: deixe conectado só o que vai receber o jogo."
                return
            }
            device = d
            let udid = d.udid
            let lock = try await off { try t.lockState(udid) }
            let apps = try await off { try t.apps(udid) }
            installedBundle = Signing.suggestedBundle(apps)
            if bundle.isEmpty, let b = installedBundle { bundle = b }
            if bundle.isEmpty, !team.isEmpty { bundle = IOSScripts.defaultBundle(team: team) }
            deviceReady = d.paired && d.booted && d.developerMode && !IOSPolicy.isLocked(lock, facts: deps.facts)
            deviceLine = IOSText.deviceLine(d, lock: lock, facts: deps.facts)
            record = loadRecord(d)
        } catch {
            deviceLine = IOSText.message(for: error)
        }
    }

    private func readyDevice() async throws -> IOSDevice {
        await refreshDevice()
        guard let d = device, deviceReady else { throw IOSFlowError.notReady(deviceLine) }
        return d
    }

    /// Ruling 4: Instalar and Reassinar refuse, like the save sync, while the game runs
    /// on either side — the launcher's own game or a g2play/boot_gow2* started by hand.
    private func refuseIfGameRunning(_ d: IOSDevice) async throws {
        let ps = deps.macProcesses
        if game?.running == true { throw SaveSyncError.gameRunningMac }
        if try await off({ IOSPolicy.macGameRunning(psComm: try ps()) }) { throw SaveSyncError.gameRunningMac }
        try await refuseIfPhoneAppRunning(d)
    }

    private func refuseIfPhoneAppRunning(_ d: IOSDevice) async throws {
        let t = deps.transport, b = bundle, udid = d.udid
        let running = try await off { () -> Bool in
            guard let app = try t.apps(udid).first(where: { $0.bundleID == b }) else { return false }
            return IOSPolicy.appRunning(executables: try t.processes(udid), appURL: app.url)
        }
        if running { throw IOSFlowError.phoneAppRunning }
    }

    // MARK: scripts

    private func runScript(_ name: String, _ args: [String], log: String) async throws -> ScriptResult {
        let script = IOSScripts.dir(repo: repo).appendingPathComponent(name)
        let env = IOSScripts.environment(ProcessInfo.processInfo.environment)
        let logURL = logsDir.appendingPathComponent(log)
        let s = deps.scripts
        return try await off { try s.run(script, args, env: env, log: logURL) }
    }

    private func writeLocalEnv(_ d: IOSDevice) throws {
        guard LocalEnvFile.valid(team), LocalEnvFile.valid(bundle) else { throw IOSFlowError.missingSigning }
        try LocalEnvFile.at(repo: repo).update(["GOW2_IOS_TEAM": team, "GOW2_IOS_DEVICE": d.udid, "GOW2_IOS_BUNDLE_ID": bundle])
    }

    /// The scripts must sign and install exactly what the screen shows.
    private func verifyScriptConfig(_ d: IOSDevice) async throws {
        let r = try await runScript("print_config.sh", [], log: "ios-config.log")
        guard let c = IOSScripts.config(r), c.team == team, c.device == d.udid, c.bundle == bundle else {
            throw IOSFlowError.configMismatch(r.output)
        }
    }

    private func buildApp(signOnly: Bool) async throws -> URL {
        progress = signOnly ? "Assinando o app de novo…" : "Compilando o app para iPhone (a primeira vez leva vários minutos)…"
        let r = try await runScript("build_ios.sh", signOnly ? ["--sign-only"] : [], log: "ios-build.log")
        guard r.status == 0, let app = r.value("GOW2_IOS_APP") else { throw IOSFlowError.build(r) }
        return URL(fileURLWithPath: app)
    }

    private func installApp() async throws {
        progress = "Instalando o app no iPhone…"
        let r = try await runScript("install_ios.sh", [], log: "ios-install.log")
        guard r.status == 0, r.output.contains("GOW2_IOS_INSTALL_OK") else { throw IOSFlowError.install(r) }
    }

    private func readExpiry(_ app: URL) throws -> Date {
        let prof = app.appendingPathComponent("embedded.mobileprovision")
        guard let info = (try? deps.readProfile(prof)).flatMap({ Signing.profile(plist: $0) }) else {
            throw IOSFlowError.noProfile(prof.path)
        }
        return info.expires
    }

    private func loadRecord(_ d: IOSDevice) -> IOSInstallRecord {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let u = deviceDir(d).appendingPathComponent("install.json")
        return (try? Data(contentsOf: u)).flatMap { try? dec.decode(IOSInstallRecord.self, from: $0) } ?? IOSInstallRecord()
    }

    private func saveRecord(_ d: IOSDevice) throws {
        let u = deviceDir(d).appendingPathComponent("install.json")
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(record).write(to: u, options: .atomic)
    }

    // MARK: flows

    /// Build, sign, install (the container is kept), then copy what the phone lacks.
    func install() async {
        guard busy == nil else { return }
        busy = .install
        error = nil
        lastResult = nil
        defer { busy = nil; progress = ""; canCancel = false }
        do {
            let d = try await readyDevice()
            try await refuseIfGameRunning(d)
            try writeLocalEnv(d)
            try await verifyScriptConfig(d)
            let c = LauncherCore.load(repo: repo)
            let sources = try InstallSources.collect(elf: URL(fileURLWithPath: c.elf), usrdir: URL(fileURLWithPath: c.vfs_root),
                                                     movieCache: c.movie_cache.isEmpty ? nil : URL(fileURLWithPath: c.movie_cache))
            let app = try await buildApp(signOnly: false)
            let expiry = try readExpiry(app)
            try await refuseIfGameRunning(d)             // the build takes minutes: re-check right before installing
            try await installApp()
            record = loadRecord(d)                       // the app is on the phone now, whatever happens next
            record.expiry = expiry
            record.installedAt = deps.now()
            try saveRecord(d)
            progress = "Conferindo os arquivos do jogo no Mac…"
            let cache = HashCache(url: supportDir.appendingPathComponent("hash-cache.json"))
            let manifest = try await off {
                try InstallManifestBuilder.build(sources, cache: cache) { done, total in
                    Task { @MainActor in self.progress = IOSText.hashing(done, total) }
                }
            }
            let pusher = DataPusher(transport: deps.transport, device: d.udid, bundle: bundle, staging: staging(),
                                    recordURL: deviceDir(d).appendingPathComponent("pushed.json"))
            try await refuseIfGameRunning(d)             // hashing takes minutes too: re-check before copying
            let flag = cancelFlag
            flag.set(false)
            canCancel = true
            let outcome = try await off {
                try pusher.push(manifest, progress: { p in Task { @MainActor in self.progress = IOSText.copying(p) } },
                                cancelled: { flag.isSet })
            }
            canCancel = false
            record.setID = manifest.setID                // only once the phone holds this set
            try saveRecord(d)
            lastResult = IOSText.installed(outcome, badge: badge)
        } catch {
            self.error = IOSText.message(for: error)
        }
    }

    /// Re-sign: rebuild only the signature and reinstall the app; data and saves stay.
    func resign() async {
        guard busy == nil else { return }
        busy = .resign
        error = nil
        lastResult = nil
        defer { busy = nil; progress = "" }
        do {
            let d = try await readyDevice()
            guard installedBundle != nil, installedBundle == bundle else { throw IOSFlowError.notInstalled }
            try await refuseIfGameRunning(d)
            try writeLocalEnv(d)
            try await verifyScriptConfig(d)
            var retired: [RetiredProfile] = []
            if deps.facts.retireProfileRenews == true {                      // F8; not measured -> keep the profile
                retired = try Signing.retireProfiles(
                    appID: "\(team).\(bundle)", from: Signing.profilesDir(home: deps.home),
                    to: supportDir.appendingPathComponent("retired-profiles/\(Int(deps.now().timeIntervalSince1970))"),
                    reader: deps.readProfile)
            }
            let app: URL
            do { app = try await buildApp(signOnly: true) } catch {
                Signing.restore(retired)
                throw error
            }
            let expiry = try readExpiry(app)
            try await refuseIfGameRunning(d)             // re-check right before replacing the app
            try await installApp()
            record = loadRecord(d)
            record.expiry = expiry
            record.installedAt = deps.now()
            try saveRecord(d)
            lastResult = "Reassinado. \(badge.text). O jogo e os saves no iPhone não foram tocados."
        } catch {
            self.error = IOSText.message(for: error)
        }
    }

    /// The launcher's own game cannot start while the sync holds the exclusive lock;
    /// a g2play started by hand is caught by `ps` at the start and again right
    /// before every destructive step (SaveSyncer).
    private func makeSyncer(_ d: IOSDevice) -> SaveSyncer {
        let c = LauncherCore.load(repo: repo)
        let ps = deps.macProcesses
        return SaveSyncer(transport: deps.transport, device: d.udid, bundle: bundle, macRoot: LauncherCore.savedataRoot(c),
                          backupRoot: backupRoot(c), stateURL: deviceDir(d).appendingPathComponent("save-sync.json"),
                          staging: staging(), facts: deps.facts, macGameRunning: { IOSPolicy.macGameRunning(psComm: try ps()) },
                          now: deps.now)
    }

    func syncSaves(_ mode: SyncMode) async {
        await runSaves(mode) { s in try s.run(mode) }
    }

    func resolve(_ name: String, keep: SaveSide) async {
        await runSaves(keep == .mac ? .macToPhone : .phoneToMac) { s in try s.resolve(name, keep: keep) }
        if error == nil { conflicts.removeAll { $0.name == name } }
    }

    private func runSaves(_ mode: SyncMode, _ work: @escaping (SaveSyncer) throws -> SaveSyncReport) async {
        guard busy == nil else { return }
        error = nil
        lastResult = nil
        if let g = game, !g.tryBeginExclusive("Sincronizando os saves com o iPhone — espere terminar.") {
            error = SaveSyncError.gameRunningMac.userMessage
            return
        }
        busy = .saves
        defer { busy = nil; progress = ""; game?.endExclusive() }
        do {
            let d = try await readyDevice()
            let s = makeSyncer(d)
            progress = "Comparando os saves do Mac e do iPhone…"
            let r = try await off { try work(s) }
            conflicts = r.conflicts.isEmpty ? conflicts.filter { c in !(r.pushed + r.pulled + r.same).contains(c.name) } : r.conflicts
            lastResult = IOSText.syncResult(r, mode: mode)
        } catch {
            self.error = IOSText.message(for: error)
        }
    }

    func cancel() {
        guard canCancel else { return }
        cancelFlag.set(true)
        deps.transport.cancel()
    }
}
