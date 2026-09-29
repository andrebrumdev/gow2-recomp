import Foundation

/// Install and re-sign copy the phone's saves to the Mac before the app is replaced
/// (plan 2026-09-28 Phase 6, Task 2): a verified backup first, or no install at all.
@MainActor
func runInstallBackupChecks() async {
    let G = "BCUS98229_GOW2"
    let root = tempDir("instbackup")
    let repo = root.appendingPathComponent("repo"), home = root.appendingPathComponent("home")
    let game = makeGameTree(root.appendingPathComponent("game"))
    try! FileManager.default.createDirectory(at: repo.appendingPathComponent("ios"), withIntermediateDirectories: true)
    let cfg: [String: Any] = ["elf": game.elf.path, "vfs_root": game.usrdir.path, "movie_cache": game.movies.path,
                              "savedata_root": root.appendingPathComponent("macsaves").path]
    try! JSONSerialization.data(withJSONObject: cfg).write(to: repo.appendingPathComponent("user_config.json"))
    let dev = IOSDevice(udid: "00008110-TEST", name: "iPhone Teste", model: "iPhone 14", osVersion: "26.6",
                        transport: "wired", paired: true, booted: true, developerMode: true)
    let app = IOSApp(bundleID: "com.example.gow2", name: "God of War II",
                     url: "file:///private/var/containers/Bundle/Application/A/GoW2.app/", builtByDeveloper: true)
    let phone = FakeTransport(root: root.appendingPathComponent("container"))
    try! FileManager.default.createDirectory(at: phone.root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    phone.deviceList = [dev]
    phone.installed = [app]
    writeFile(phone.root.appendingPathComponent("Documents/savedata/\(G)/SYS.BIN"), "phone-save")
    let appPath = root.appendingPathComponent("GoW2.app").path
    let scripts = FakeScripts()
    scripts.results["print_config.sh"] = ScriptResult(status: 0, output:
        "GOW2_IOS_TEAM=ABCDE12345\nGOW2_IOS_DEVICE=00008110-TEST\nGOW2_IOS_BUNDLE=com.example.gow2\nGOW2_IOS_APP=\(appPath)\n")
    scripts.results["build_ios.sh"] = ScriptResult(status: 0, output: "GOW2_IOS_APP=\(appPath)\n")
    scripts.results["build_ios.sh --sign-only"] = ScriptResult(status: 0, output: "GOW2_IOS_APP=\(appPath)\n")
    scripts.results["install_ios.sh"] = ScriptResult(status: 0, output: "GOW2_IOS_INSTALL_OK\n")
    let now = Date(timeIntervalSince1970: 1790372701)
    let facts = DeviceFacts(measured: "test", copyFromNestsDirectory: false, removeExistingContentDeletesExtras: nil,
                            lockStateTracksLock: true, retireProfileRenews: nil)
    let deps = IOSDeps(transport: phone, scripts: scripts,
                       readProfile: { _ in profilePlist(expires: "2026-10-01T14:19:03Z") },
                       xcodePrefs: { Data(fxXcodePrefs.utf8) }, macProcesses: { "/bin/zsh\n" },
                       facts: facts, home: home, now: { now }, prereqs: { _, _ in [] })
    let ios = IOSBackend(repo: repo, game: FakeGame(), deps: deps)
    await ios.refresh()
    let backups = URL(fileURLWithPath: ios.backupRootPath)
    func backedUp() -> [String] {   // "<folder>/<save>/SYS.BIN" under the backup root
        ((FileManager.default.enumerator(atPath: backups.path)?.allObjects as? [String]) ?? []).filter { $0.hasSuffix("SYS.BIN") }.sorted()
    }

    // The backup exists when install_ios.sh runs, and install_ios.sh is told so.
    var seen: [String] = []
    scripts.onRun = { key in if key == "install_ios.sh" { seen = backedUp() } }
    await ios.install()
    check(ios.error == nil, "install with a phone save: \(ios.error ?? "")")
    check(seen.count == 1 && seen[0].hasSuffix("-iphone/\(G)/SYS.BIN"), "phone save backed up before install_ios.sh: \(seen)")
    check((try? String(contentsOf: backups.appendingPathComponent(seen.first ?? "x"), encoding: .utf8)) == "phone-save",
          "the backup holds the phone's bytes")
    check(scripts.envs["install_ios.sh"]?["GOW2_IOS_SAVES_BACKED_UP"] == "1", "install_ios.sh is told the saves are backed up")
    check(ios.lastResult?.contains("Saves do iPhone copiados") == true, "result names the backup: \(ios.lastResult ?? "")")

    // Re-sign backs up again before replacing the app.
    let n0 = backedUp().count
    seen = []
    await ios.resign()
    check(ios.error == nil && seen.count == n0 + 1, "resign backs up first: \(ios.error ?? "") \(seen)")

    // A backup that cannot be read: nothing is installed.
    phone.failWhen = { $0 == "dir from Documents/savedata"
        ? DeviceError(code: DeviceError.notFound, domain: "fake", message: "Failed to retrieve the file node") : nil }
    let c0 = scripts.calls.count
    await ios.install()
    check(ios.error?.contains("saves do iPhone") == true && !scripts.calls.dropFirst(c0).contains("install_ios.sh"),
          "no install without a backup: \(ios.error ?? "") \(scripts.calls.dropFirst(c0))")
    await ios.resign()
    check(ios.error?.contains("saves do iPhone") == true && !scripts.calls.dropFirst(c0).contains("install_ios.sh"),
          "no re-sign without a backup: \(ios.error ?? "")")
    phone.failWhen = nil

    // First install of this bundle (not on the phone): nothing to back up, the install goes on.
    phone.installed = []
    let from0 = phone.ops.filter { $0.hasPrefix("dir from") }.count
    await ios.install()
    check(ios.error == nil && phone.ops.filter { $0.hasPrefix("dir from") }.count == from0,
          "first install: no backup read, install ok: \(ios.error ?? "")")
    try? FileManager.default.removeItem(at: root)
}
