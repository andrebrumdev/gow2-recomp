import Foundation

final class FakeScripts: ScriptRunning {
    var results: [String: ScriptResult] = [:]
    private(set) var calls: [String] = []
    /// Runs after the script "ran" (the world changing while a long build runs).
    var onRun: ((String) -> Void)?
    func run(_ script: URL, _ args: [String], env: [String: String], log: URL) throws -> ScriptResult {
        let key = ([script.lastPathComponent] + args).joined(separator: " ")
        calls.append(key)
        onRun?(key)
        return results[key] ?? ScriptResult(status: 127, output: "no fake for \(key)")
    }
}

/// `ps` output that a test changes while a flow runs.
final class PSBox: @unchecked Sendable {
    var text = "/bin/zsh\n"
}

@MainActor
final class FakeGame: GameRunState {
    var running = false
    private(set) var holder: String?
    private(set) var taken = 0
    func tryBeginExclusive(_ reason: String) -> Bool {
        guard !running, holder == nil else { return false }
        holder = reason
        taken += 1
        return true
    }
    func endExclusive() { holder = nil }
}

@MainActor
func runBackendChecks() async {
    let G = "BCUS98229_GOW2"
    let root = tempDir("backend")
    let repo = root.appendingPathComponent("repo"), home = root.appendingPathComponent("home")
    let game = makeGameTree(root.appendingPathComponent("game"))
    let saves = root.appendingPathComponent("macsaves")
    writeFile(saves.appendingPathComponent("\(G)/MASTER.BIN"), "m1")
    try! FileManager.default.createDirectory(at: repo.appendingPathComponent("ios"), withIntermediateDirectories: true)
    let cfg: [String: Any] = ["elf": game.elf.path, "vfs_root": game.usrdir.path, "movie_cache": game.movies.path,
                              "savedata_root": saves.path]
    try! JSONSerialization.data(withJSONObject: cfg).write(to: repo.appendingPathComponent("user_config.json"))
    writeFile(repo.appendingPathComponent("ios/local.env"), "GOW2_WORK=/keep/me\n")

    let dev = IOSDevice(udid: "00008110-TEST", name: "iPhone Teste", model: "iPhone 14", osVersion: "26.6",
                        transport: "wired", paired: true, booted: true, developerMode: true)
    let app = IOSApp(bundleID: "com.example.gow2", name: "God of War II",
                     url: "file:///private/var/containers/Bundle/Application/A/GoW2.app/", builtByDeveloper: true)
    let phone = FakeTransport(root: root.appendingPathComponent("container"))
    try! FileManager.default.createDirectory(at: phone.root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    phone.deviceList = [dev]
    phone.installed = [app]
    let appPath = root.appendingPathComponent("GoW2.app").path
    let goodConfig = ScriptResult(status: 0, output:
        "GOW2_IOS_TEAM=ABCDE12345\nGOW2_IOS_DEVICE=00008110-TEST\nGOW2_IOS_BUNDLE=com.example.gow2\nGOW2_IOS_APP=\(appPath)\n")
    let scripts = FakeScripts()
    scripts.results["print_config.sh"] = goodConfig
    scripts.results["build_ios.sh"] = ScriptResult(status: 0, output: "** BUILD SUCCEEDED **\nGOW2_IOS_APP=\(appPath)\n")
    scripts.results["build_ios.sh --sign-only"] = ScriptResult(status: 0, output: "GOW2_IOS_APP=\(appPath)\n")
    scripts.results["install_ios.sh"] = ScriptResult(status: 0, output: "App installed\nGOW2_IOS_INSTALL_OK\n")
    let now = Date(timeIntervalSince1970: 1790372701)
    let facts = DeviceFacts(measured: "test", copyFromNestsDirectory: false, removeExistingContentDeletesExtras: true,
                            lockStateTracksLock: true, retireProfileRenews: true)
    let deps = IOSDeps(transport: phone, scripts: scripts,
                       readProfile: { _ in profilePlist(expires: "2026-10-01T14:19:03Z") },
                       xcodePrefs: { Data(fxXcodePrefs.utf8) }, macProcesses: { "/bin/zsh\n" },
                       facts: facts, home: home, now: { now })
    let g = FakeGame()
    let ios = IOSBackend(repo: repo, game: g, deps: deps)

    // Refresh: team from Xcode, bundle id from the GoW2 already on the phone (Review Focus 4).
    await ios.refresh()
    check(ios.device == dev && ios.deviceReady && ios.team == "ABCDE12345" && ios.bundle == "com.example.gow2",
          "refresh: \(ios.deviceLine) team=\(ios.team) bundle=\(ios.bundle)")
    check(ios.bundleWarning == nil, "no warning for the installed bundle")
    ios.bundle = "com.example.other"
    check(ios.bundleWarning?.contains("com.example.gow2") == true, "warning for another bundle id")
    ios.bundle = "com.example.gow2"

    // Install: config check, build, install, push; manifest complete on the phone; expiry recorded.
    await ios.install()
    check(ios.error == nil, "install error: \(ios.error ?? "")")
    check(scripts.calls == ["print_config.sh", "build_ios.sh", "install_ios.sh"], "scripts \(scripts.calls)")
    check(probeState(phone.root.appendingPathComponent("Documents")) == 1, "the phone has a complete install")
    check(ios.record.expiry == Date(timeIntervalSince1970: 1790864343) && ios.badge == .ok(days: 6), "expiry \(ios.record)")
    check(ios.record.setID != nil && ios.record.installedAt == now, "set id and install time recorded after the push: \(ios.record)")
    check(ios.lastResult?.contains("Instalado") == true && ios.busy == nil && !ios.canCancel, "result \(ios.lastResult ?? "")")
    check(LocalEnvFile.at(repo: repo).read() == ["GOW2_WORK": "/keep/me", "GOW2_IOS_TEAM": "ABCDE12345",
                                                 "GOW2_IOS_DEVICE": "00008110-TEST", "GOW2_IOS_BUNDLE_ID": "com.example.gow2"],
          "local.env: three keys written, the rest kept")
    let again = IOSBackend(repo: repo, game: g, deps: deps)
    await again.refresh()
    check(again.record.expiry == ios.record.expiry, "install record persisted per device + bundle")
    await ios.install()
    check(ios.lastResult?.contains("já estava completo") == true, "second install copies nothing: \(ios.lastResult ?? "")")

    // Re-sign: --sign-only, no data copied, this app's cached profile retired; a failed build restores it.
    let pdir = Signing.profilesDir(home: home)
    writeFile(pdir.appendingPathComponent("old.mobileprovision"), "old")
    let opsBefore = phone.ops.count
    await ios.resign()
    check(ios.error == nil && Array(scripts.calls.suffix(3)) == ["print_config.sh", "build_ios.sh --sign-only", "install_ios.sh"],
          "resign \(scripts.calls.suffix(3)) \(ios.error ?? "")")
    check(phone.ops.count == opsBefore, "resign copies no data")
    check(!FileManager.default.fileExists(atPath: pdir.appendingPathComponent("old.mobileprovision").path), "cached profile retired")
    writeFile(pdir.appendingPathComponent("old2.mobileprovision"), "old2")
    scripts.results["build_ios.sh --sign-only"] = ScriptResult(status: 1, output: "error: No signing certificate\n")
    await ios.resign()
    check(ios.error?.contains("ios-build.log") == true
          && FileManager.default.fileExists(atPath: pdir.appendingPathComponent("old2.mobileprovision").path),
          "failed build restores the profile: \(ios.error ?? "")")
    scripts.results["build_ios.sh --sign-only"] = ScriptResult(status: 0, output: "GOW2_IOS_APP=\(appPath)\n")

    // GoW2 open on the phone (Review Focus 2): re-sign refuses before any script.
    phone.running = [app.url + "GoW2"]
    let calls0 = scripts.calls.count
    await ios.resign()
    check(ios.error?.contains("alternador") == true && scripts.calls.count == calls0, "resign refuses: \(ios.error ?? "")")
    phone.running = []

    // The game open on the Mac (the launcher's or a hand-started g2play): install and
    // re-sign refuse before any script, like the save sync (ruling 4).
    g.running = true
    await ios.install()
    check(ios.error?.contains("Mac") == true && scripts.calls.count == calls0, "install refuses with the Mac game open: \(ios.error ?? "")")
    await ios.resign()
    check(ios.error?.contains("Mac") == true && scripts.calls.count == calls0, "resign refuses with the Mac game open: \(ios.error ?? "")")
    g.running = false
    var psGame = deps
    psGame.macProcesses = { "/usr/bin/login\n/Users/x/gow2-recomp/boot_gow2_e435\n" }
    let byPS = IOSBackend(repo: repo, game: g, deps: psGame)
    await byPS.install()
    check(byPS.error?.contains("Mac") == true && scripts.calls.count == calls0, "install refuses with boot_gow2 running: \(byPS.error ?? "")")
    await byPS.resign()
    check(byPS.error?.contains("Mac") == true && scripts.calls.count == calls0, "resign refuses with boot_gow2 running: \(byPS.error ?? "")")

    // Locked phone: nothing runs.
    phone.lock = IOSLockState(passcodeRequired: true, unlockedSinceBoot: true)
    await ios.install()
    check(ios.error?.contains("bloqueado") == true && scripts.calls.count == calls0, "locked: \(ios.error ?? "")")
    phone.lock = IOSLockState(passcodeRequired: false, unlockedSinceBoot: true)

    // install_ios.sh failing with 10002 -> the locked message.
    scripts.results["install_ios.sh"] = ScriptResult(status: 1,
        output: "ERROR: The device is locked. (com.apple.dt.CoreDeviceError error 10002 (0x2712))\n")
    await ios.install()
    check(ios.error?.contains("bloqueado") == true, "install 10002: \(ios.error ?? "")")
    scripts.results["install_ios.sh"] = ScriptResult(status: 0, output: "GOW2_IOS_INSTALL_OK\n")

    // The scripts resolve another bundle id: stop before building.
    scripts.results["print_config.sh"] = ScriptResult(status: 0, output:
        "GOW2_IOS_TEAM=ABCDE12345\nGOW2_IOS_DEVICE=00008110-TEST\nGOW2_IOS_BUNDLE=com.other\nGOW2_IOS_APP=/x\n")
    let calls1 = scripts.calls.count
    await ios.install()
    check(ios.error?.contains("local.env") == true && scripts.calls.count == calls1 + 1, "config mismatch: \(ios.error ?? "")")
    scripts.results["print_config.sh"] = goodConfig

    // Final review 1: the game opened on either side while the (minutes-long) build ran:
    // the flow re-checks right before installing the app and again before copying data.
    let gameOnPhone = [app.url + "GoW2"]
    scripts.onRun = { key in if key == "build_ios.sh" { phone.running = gameOnPhone } }
    var c0 = scripts.calls.count, o0 = phone.ops.count
    await ios.install()
    check(ios.error?.contains("alternador") == true && Array(scripts.calls.dropFirst(c0)) == ["print_config.sh", "build_ios.sh"]
          && phone.ops.count == o0, "install: phone game opened during the build -> no install, no copy: \(ios.error ?? "") \(scripts.calls.dropFirst(c0))")
    phone.running = []
    scripts.onRun = { key in if key == "build_ios.sh --sign-only" { phone.running = gameOnPhone } }
    c0 = scripts.calls.count
    await ios.resign()
    check(ios.error?.contains("alternador") == true
          && Array(scripts.calls.dropFirst(c0)) == ["print_config.sh", "build_ios.sh --sign-only"],
          "resign: phone game opened during the build -> no install: \(ios.error ?? "") \(scripts.calls.dropFirst(c0))")
    phone.running = []
    let psBox = PSBox()
    var boxDeps = deps
    boxDeps.macProcesses = { psBox.text }
    let boxed = IOSBackend(repo: repo, game: g, deps: boxDeps)
    scripts.onRun = { key in if key.hasPrefix("build_ios.sh") { psBox.text = "/Users/x/gow2-recomp/g2play\n" } }
    c0 = scripts.calls.count
    o0 = phone.ops.count
    await boxed.install()
    check(boxed.error?.contains("Mac") == true && !scripts.calls.dropFirst(c0).contains("install_ios.sh") && phone.ops.count == o0,
          "install: Mac game opened during the build -> no install: \(boxed.error ?? "") \(scripts.calls.dropFirst(c0))")
    psBox.text = "/bin/zsh\n"
    c0 = scripts.calls.count
    await boxed.resign()
    check(boxed.error?.contains("Mac") == true && !scripts.calls.dropFirst(c0).contains("install_ios.sh"),
          "resign: Mac game opened during the build -> no install: \(boxed.error ?? "") \(scripts.calls.dropFirst(c0))")
    psBox.text = "/bin/zsh\n"
    // ... and opened while the app was being installed: the app is in (its expiry and install
    // time recorded right away -- final review 4), but no data is copied and no set id is written.
    let installJSON = ios.supportDir.appendingPathComponent("00008110-TEST_com.example.gow2/install.json")
    try? FileManager.default.removeItem(at: installJSON)
    scripts.onRun = { key in if key == "install_ios.sh" { phone.running = gameOnPhone } }
    c0 = scripts.calls.count
    o0 = phone.ops.count
    await ios.install()
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    let rec = (try? Data(contentsOf: installJSON)).flatMap { try? dec.decode(IOSInstallRecord.self, from: $0) }
    check(ios.error?.contains("alternador") == true && scripts.calls.dropFirst(c0).contains("install_ios.sh") && phone.ops.count == o0,
          "install: phone game opened during the app install -> no data copied: \(ios.error ?? "") ops+\(phone.ops.count - o0)")
    check(rec?.expiry == Date(timeIntervalSince1970: 1790864343) && rec?.installedAt == now && rec?.setID == nil,
          "record saved right after the app install, set id only after a push: \(String(describing: rec))")
    phone.running = []
    scripts.onRun = { key in if key == "install_ios.sh" { psBox.text = "/Users/x/gow2-recomp/boot_gow2\n" } }
    o0 = phone.ops.count
    await boxed.install()
    check(boxed.error?.contains("Mac") == true && phone.ops.count == o0, "install: Mac game opened during the app install -> no copy: \(boxed.error ?? "")")
    psBox.text = "/bin/zsh\n"
    scripts.onRun = nil

    // Final review 8: `ps` failing is never "not running" -- the flows refuse.
    var psFail = deps
    psFail.macProcesses = { throw IOSFlowError.processListFailed }
    let noPS = IOSBackend(repo: repo, game: g, deps: psFail)
    c0 = scripts.calls.count
    await noPS.install()
    check(noPS.error?.contains("processos") == true && scripts.calls.count == c0, "install refuses when ps fails: \(noPS.error ?? "")")
    await noPS.resign()
    check(noPS.error?.contains("processos") == true && scripts.calls.count == c0, "resign refuses when ps fails: \(noPS.error ?? "")")
    check(!(try! IOSDeps.checkedPS("/sbin/launchd\n")).isEmpty, "ps output kept")
    do { _ = try IOSDeps.checkedPS("  \n"); check(false, "empty ps output must throw") }
    catch { check((error as? IOSFlowError).map { if case .processListFailed = $0 { return true } else { return false } } == true, "\(error)") }

    // Save sync: refused with the Mac game open; Jogar blocked only while it runs.
    g.running = true
    await ios.syncSaves(.both)
    check(ios.error?.contains("Mac") == true && g.holder == nil && g.taken == 0, "sync refuses with the launcher's game open")
    g.running = false
    await ios.syncSaves(.both)
    check(ios.error == nil && ios.lastResult?.contains("Mac → iPhone") == true && g.holder == nil && g.taken == 1,
          "first sync pushes the Mac save: \(ios.lastResult ?? "") \(ios.error ?? "")")
    writeFile(saves.appendingPathComponent("\(G)/MASTER.BIN"), "mac2")
    writeFile(phone.root.appendingPathComponent("Documents/savedata/\(G)/MASTER.BIN"), "phone2")
    await ios.syncSaves(.both)
    check(ios.conflicts.map(\.name) == [G], "conflict listed")
    await ios.resolve(G, keep: .mac)
    check(ios.conflicts.isEmpty && ios.error == nil
          && (try? String(contentsOf: phone.root.appendingPathComponent("Documents/savedata/\(G)/MASTER.BIN"), encoding: .utf8)) == "mac2",
          "conflict resolved to the Mac's: \(ios.error ?? "")")
    check(ios.backupRootPath.hasSuffix("Documents/GoW2 Saves")
          && FileManager.default.fileExists(atPath: home.appendingPathComponent("Documents/GoW2 Saves").path), "phone save backed up")

    // Texts.
    let wifi = IOSDevice(udid: "x", name: "iPhone Teste", model: "iPhone 14", osVersion: "26.6", transport: "localNetwork",
                         paired: true, booted: true, developerMode: true)
    check(IOSText.deviceLine(wifi, lock: IOSLockState(passcodeRequired: false, unlockedSinceBoot: true), facts: facts).contains("cabo"),
          "Wi-Fi hint")
    var missing = SaveSyncReport()
    missing.missingSource = [G]
    check(IOSText.syncResult(missing, mode: .macToPhone).contains("Nada copiado")
          && IOSText.syncResult(missing, mode: .macToPhone).contains("não existe no Mac"), "forced direction without a source is not a success")
    // Every error the flows can surface is rendered in pt-BR (never localizedDescription).
    let locked = IOSText.message(for: DeviceError(code: DeviceError.locked, domain: "com.apple.dt.CoreDeviceError", message: ""))
    check(locked.contains("bloqueado") && locked.contains("deixe a tela ligada"), "locked text: \(locked)")
    let restored = IOSText.message(for: SaveSyncError.phoneRestored(G))
    check(restored.contains(G) && restored.contains("foi restaurado"), "phone restored text: \(restored)")
    let notRestored = IOSText.message(for: SaveSyncError.verifyFailed(G))
    check(notRestored.contains(G) && !notRestored.contains("restaurado"), "verify text claims no restore: \(notRestored)")
    check(IOSText.message(for: SaveSyncError.restoreFailed(G, "/b/x")).contains("/b/x"), "restoreFailed names the backup")
    check(IOSText.message(for: SaveSyncError.unreadableSave(G)).contains("Não deu para ler"), "unreadable save text")
    check(IOSText.message(for: SaveSyncError.symlinkInSave(G)).contains("link simbólico"), "symlink text")
    // A resign with F8 not measured keeps Xcode's cached profile.
    var noF8 = deps
    noF8.facts.retireProfileRenews = nil
    writeFile(pdir.appendingPathComponent("keep.mobileprovision"), "keep")
    let keep = IOSBackend(repo: repo, game: g, deps: noF8)
    await keep.resign()
    check(keep.error == nil && FileManager.default.fileExists(atPath: pdir.appendingPathComponent("keep.mobileprovision").path),
          "F8 unmeasured: profile kept: \(keep.error ?? "")")
    // An external g2play (not the launcher's) refuses the sync (ps check).
    var extPS = deps
    extPS.macProcesses = { "/Users/x/gow2-recomp/g2play\n" }
    let ext = IOSBackend(repo: repo, game: g, deps: extPS)
    await ext.syncSaves(.both)
    check(ext.error?.contains("Mac") == true && g.holder == nil, "external g2play refuses: \(ext.error ?? "")")
    let noPSSync = IOSBackend(repo: repo, game: g, deps: psFail)
    await noPSSync.syncSaves(.both)
    check(noPSSync.error?.contains("processos") == true && g.holder == nil, "sync refuses when ps fails: \(noPSSync.error ?? "")")
    check(IOSText.date(Date(timeIntervalSince1970: 1790372701), timeZone: TimeZone(identifier: "UTC")!) == "25/09 21:45", "date")
    check(IOSText.copying(PushProgress(file: "USRDIR/gow2.psarc", index: 2, count: 3, doneBytes: 1_200_000_000, totalBytes: 6_990_000_000))
          == "Copiando USRDIR/gow2.psarc (2 de 3) — 1,2 GB de 7,0 GB", "copy progress text")
    try? FileManager.default.removeItem(at: root)
}
