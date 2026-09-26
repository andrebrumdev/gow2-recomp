import Foundation

func runSaveSyncerChecks() {
    let G = "BCUS98229_GOW2"
    let app = IOSApp(bundleID: "com.example.gow2", name: "God of War II",
                     url: "file:///private/var/containers/Bundle/Application/A/GoW2.app/", builtByDeveloper: true)
    var macRunning = false
    var exactFacts = DeviceFacts()
    exactFacts.copyFromNestsDirectory = false
    exactFacts.removeExistingContentDeletesExtras = true
    final class Env {
        let root: URL, mac: URL, phone: FakeTransport, phoneSaves: URL, backups: URL, state: URL
        init(_ root: URL) {
            self.root = root
            mac = root.appendingPathComponent("mac/savedata")
            phone = FakeTransport(root: root.appendingPathComponent("container"))
            phoneSaves = phone.root.appendingPathComponent("Documents/savedata")
            backups = root.appendingPathComponent("backups")
            state = root.appendingPathComponent("state/save-sync.json")
        }
    }
    func env(_ tag: String) -> Env {
        let e = Env(tempDir("sync-\(tag)"))
        e.phone.installed = [app]
        writeFile(e.mac.appendingPathComponent("\(G)/MASTER.BIN"), "m1")
        writeFile(e.mac.appendingPathComponent("\(G)/DATA00.BIN"), "d1")
        writeFile(e.mac.appendingPathComponent("BLUS31017_00000000/00000000.SAV"), "ben10")
        writeFile(e.phoneSaves.appendingPathComponent("\(G)/MASTER.BIN"), "m1")
        writeFile(e.phoneSaves.appendingPathComponent("\(G)/DATA00.BIN"), "d1")
        return e
    }
    func syncer(_ e: Env, facts: DeviceFacts? = nil, running: (() -> Bool)? = nil) -> SaveSyncer {
        SaveSyncer(transport: e.phone, device: "00008110-TEST", bundle: "com.example.gow2", macRoot: e.mac,
                   backupRoot: e.backups, stateURL: e.state, staging: e.root.appendingPathComponent("staging"),
                   facts: facts ?? exactFacts, macGameRunning: running ?? { macRunning },
                   now: { Date(timeIntervalSince1970: 1790372701) })
    }
    func hash(_ dir: URL) -> String? { (try? SaveSnapshot.take(dir))?[G]?.hash }
    let fm = FileManager.default

    // 1. First sync, same save on both sides: nothing written, base recorded.
    let e = env("main")
    var r = try! syncer(e).run(.both)
    check(r.same == [G] && r.pushed.isEmpty && r.pulled.isEmpty && r.backups.isEmpty, "identical: nothing written \(r)")
    check(SyncState.load(e.state).base[G] == hash(e.mac), "base recorded")
    check(!e.phone.ops.contains { $0.hasPrefix("dir to") }, "nothing pushed")
    check(!fm.fileExists(atPath: e.phoneSaves.appendingPathComponent("BLUS31017_00000000").path),
          "another game's save never goes to the phone")

    // 2. Only the phone changed -> pulled, the Mac's old save backed up.
    writeFile(e.phoneSaves.appendingPathComponent("\(G)/DATA00.BIN"), "d2-phone")
    r = try! syncer(e).run(.both)
    check(r.pulled == [G] && r.backups.count == 1 && hash(e.mac) == hash(e.phoneSaves), "pulled \(r)")
    check(r.backups[0].lastPathComponent.hasSuffix("-mac")
          && fileText(r.backups[0].appendingPathComponent("\(G)/DATA00.BIN")) == "d1", "old Mac save kept in the backup")
    check(!fm.fileExists(atPath: e.mac.appendingPathComponent(".\(G).sync-new").path)
          && !fm.fileExists(atPath: e.mac.appendingPathComponent(".\(G).sync-old").path), "no staging left on the Mac")

    // 3. Only the Mac changed -> pushed with -r (F6 true), the phone's old save backed up first.
    writeFile(e.mac.appendingPathComponent("\(G)/DATA00.BIN"), "d3-mac")
    r = try! syncer(e).run(.both)
    check(r.pushed == [G] && hash(e.phoneSaves) == hash(e.mac), "pushed \(r)")
    check(r.backups.first?.lastPathComponent.hasSuffix("-iphone") == true
          && fileText(r.backups[0].appendingPathComponent("\(G)/DATA00.BIN")) == "d2-phone", "old phone save kept")
    check(e.phone.ops.contains("dir to Documents/savedata/\(G) -r"), "the phone copy replaces the directory")

    // 4. Mac → iPhone removes stale files on the phone (F6 true; the backup keeps them).
    writeFile(e.phoneSaves.appendingPathComponent("\(G)/STALE.BIN"), "old")
    r = try! syncer(e).run(.macToPhone)
    check(r.pushed == [G] && !fm.fileExists(atPath: e.phoneSaves.appendingPathComponent("\(G)/STALE.BIN").path)
          && fileText(r.backups[0].appendingPathComponent("\(G)/STALE.BIN")) == "old", "exact replica + backup")

    // 5. Both changed -> conflict, nothing touched; resolve keeps the phone's with a Mac backup.
    writeFile(e.mac.appendingPathComponent("\(G)/MASTER.BIN"), "m4-mac")
    writeFile(e.phoneSaves.appendingPathComponent("\(G)/MASTER.BIN"), "m4-phone")
    r = try! syncer(e).run(.both)
    check(r.conflicts.map(\.name) == [G] && r.conflicts[0].mac.hash == hash(e.mac) && r.backups.isEmpty, "conflict \(r)")
    check(fileText(e.mac.appendingPathComponent("\(G)/MASTER.BIN")) == "m4-mac"
          && fileText(e.phoneSaves.appendingPathComponent("\(G)/MASTER.BIN")) == "m4-phone", "a conflict touches neither side")
    r = try! syncer(e).resolve(G, keep: .iphone)
    check(r.pulled == [G] && fileText(e.mac.appendingPathComponent("\(G)/MASTER.BIN")) == "m4-phone"
          && fileText(r.backups[0].appendingPathComponent("\(G)/MASTER.BIN")) == "m4-mac", "resolved to the phone's")
    check(SyncState.load(e.state).base[G] == hash(e.mac), "base after resolve")

    // 6. Never synced and different -> conflict (Review Focus 3).
    let n = env("never")
    writeFile(n.mac.appendingPathComponent("\(G)/DATA00.BIN"), "x")
    check((try! syncer(n).run(.both)).conflicts.count == 1, "never synced + different")

    // 7. Forced direction with the source missing (Codex review 8): reported, nothing copied.
    let ms = env("missing")
    try! fm.removeItem(at: ms.mac.appendingPathComponent(G))
    r = try! syncer(ms).run(.macToPhone)
    check(r.missingSource == [G] && r.pushed.isEmpty && r.backups.isEmpty && hash(ms.phoneSaves) != nil
          && !ms.phone.ops.contains { $0.hasPrefix("dir to") }, "Mac → iPhone without a Mac save \(r)")

    // 8. Guards (Review Focus 2): nothing is copied while the game runs anywhere.
    let gd = env("guards")
    macRunning = true
    do { _ = try syncer(gd).run(.both); check(false, "Mac game running must refuse") }
    catch let x as SaveSyncError { check(x == .gameRunningMac && gd.phone.ops.isEmpty, "\(x)") }
    catch { check(false, "\(error)") }
    macRunning = false
    gd.phone.running = ["file:///private/var/containers/Bundle/Application/A/GoW2.app/GoW2"]
    do { _ = try syncer(gd).resolve(G, keep: .mac); check(false, "phone app running must refuse") }
    catch let x as SaveSyncError { check(x == .gameRunningPhone && gd.phone.ops.isEmpty, "\(x)") }
    catch { check(false, "\(error)") }
    gd.phone.running = []
    gd.phone.installed = []
    do { _ = try syncer(gd).run(.both); check(false, "app not installed must refuse") }
    catch let x as SaveSyncError { check(x == .appNotInstalled, "\(x)") }
    catch { check(false, "\(error)") }
    gd.phone.installed = [app]
    // g2play started by hand in the middle of the sync (Codex review 6): the re-check right
    // before the destructive step refuses; the phone is untouched.
    writeFile(gd.mac.appendingPathComponent("\(G)/DATA00.BIN"), "gd-mac")
    var calls = 0
    do { _ = try syncer(gd, running: { calls += 1; return calls > 1 }).run(.macToPhone); check(false, "mid-sync g2play must refuse") }
    catch let x as SaveSyncError { check(x == .gameRunningMac && !gd.phone.ops.contains { $0.hasPrefix("dir to") }, "\(x) \(gd.phone.ops)") }
    catch { check(false, "\(error)") }
    check(fileText(gd.phoneSaves.appendingPathComponent("\(G)/DATA00.BIN")) == "d1", "phone untouched")
    writeFile(gd.phoneSaves.appendingPathComponent("\(G)/DATA00.BIN"), "gd-phone")
    calls = 0
    do { _ = try syncer(gd, running: { calls += 1; return calls > 1 }).run(.phoneToMac); check(false, "mid-sync g2play must refuse the pull") }
    catch let x as SaveSyncError { check(x == .gameRunningMac, "\(x)") }
    catch { check(false, "\(error)") }
    check(fileText(gd.mac.appendingPathComponent("\(G)/DATA00.BIN")) == "gd-mac", "Mac untouched")
    check(!fm.fileExists(atPath: gd.mac.appendingPathComponent(".\(G).sync-new").path),
          "a refused pull leaves no staging copy on the Mac")

    // 9. A push that did not land is caught; the base is not advanced.
    let v = env("verify")
    _ = try! syncer(v).run(.both)
    let base = SyncState.load(v.state).base[G]
    writeFile(v.mac.appendingPathComponent("\(G)/DATA00.BIN"), "v-mac")
    v.phone.dropWritesUnder = "Documents/savedata/"
    do { _ = try syncer(v).run(.both); check(false, "verify must fail") }
    catch let x as SaveSyncError { check(x == .verifyFailed(G), "\(x)") }
    catch { check(false, "\(error)") }
    check(SyncState.load(v.state).base[G] == base, "base unchanged after a failed push")

    // 10. A corrupted push is rolled back to the (verified) backup (Codex review 4).
    v.phone.dropWritesUnder = nil
    v.phone.corruptPrefix = "Documents/savedata/"
    v.phone.corruptNext = 1
    do { _ = try syncer(v).run(.both); check(false, "corrupted push must fail") }
    catch let x as SaveSyncError { check(x == .verifyFailed(G), "\(x)") }
    catch { check(false, "\(error)") }
    check(fileText(v.phoneSaves.appendingPathComponent("\(G)/DATA00.BIN")) == "d1"
          && fileText(v.phoneSaves.appendingPathComponent("\(G)/MASTER.BIN")) == "m1", "phone restored from the backup")
    v.phone.corruptNext = 3                          // both pushed files, then the first restored one
    do { _ = try syncer(v).run(.both); check(false, "failed restore must fail") }
    catch let x as SaveSyncError {
        if case .restoreFailed(let name, let path) = x {
            check(name == G && fileText(URL(fileURLWithPath: path).appendingPathComponent("DATA00.BIN")) == "d1", "backup path named \(path)")
        } else { check(false, "expected restoreFailed, got \(x)") }
    }
    catch { check(false, "\(error)") }
    v.phone.corruptNext = 0

    // 11. F6 not measured (or false): no -r; a phone save with extra files is refused before any write.
    let f6 = env("f6")
    var noF6 = exactFacts
    noF6.removeExistingContentDeletesExtras = nil
    writeFile(f6.mac.appendingPathComponent("\(G)/DATA00.BIN"), "f6-mac")
    _ = try! syncer(f6, facts: noF6).run(.macToPhone)
    check(f6.phone.ops.contains("dir to Documents/savedata/\(G)") && !f6.phone.ops.contains { $0.hasSuffix(" -r") },
          "without F6 the copy never asks devicectl to remove anything")
    writeFile(f6.phoneSaves.appendingPathComponent("\(G)/EXTRA.BIN"), "x")
    let opsF6 = f6.phone.ops.count
    do { _ = try syncer(f6, facts: noF6).run(.macToPhone); check(false, "extras without F6 must refuse") }
    catch let x as SaveSyncError { check(x == .cannotReplaceExactly(G) && f6.phone.ops.count == opsF6 + 1, "\(x) \(f6.phone.ops.suffix(2))") }
    catch { check(false, "\(error)") }

    // 12. Mac swap failure points (Codex review 2).
    let sw = env("swap")
    _ = try! syncer(sw).run(.both)
    writeFile(sw.phoneSaves.appendingPathComponent("\(G)/DATA00.BIN"), "sw-phone")
    //  a) moving the verified staging into place fails -> the old Mac save is put back.
    let s1 = syncer(sw)
    s1.moveItem = { src, dst in
        if src.lastPathComponent == ".\(G).sync-new" { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.moveItem(at: src, to: dst)
    }
    do { _ = try s1.run(.both); check(false, "swap failure must throw") } catch {}
    check(fileText(sw.mac.appendingPathComponent("\(G)/DATA00.BIN")) == "d1"
          && !fm.fileExists(atPath: sw.mac.appendingPathComponent(".\(G).sync-old").path), "old Mac save restored in place")
    //  b) moving the old save aside fails -> nothing moved.
    let s2 = syncer(sw)
    s2.moveItem = { src, dst in
        if dst.lastPathComponent == ".\(G).sync-old" { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.moveItem(at: src, to: dst)
    }
    do { _ = try s2.run(.both); check(false, "aside failure must throw") } catch {}
    check(fileText(sw.mac.appendingPathComponent("\(G)/DATA00.BIN")) == "d1", "Mac save intact")
    check(!fm.fileExists(atPath: sw.mac.appendingPathComponent(".\(G).sync-new").path), "failed swap leaves no staging copy")
    //  c) a crash between the two moves (target gone, .sync-old present): the next run puts it back first.
    try! fm.moveItem(at: sw.mac.appendingPathComponent(G), to: sw.mac.appendingPathComponent(".\(G).sync-old"))
    try! fm.createDirectory(at: sw.mac.appendingPathComponent(".\(G).sync-new"), withIntermediateDirectories: true)
    r = try! syncer(sw).run(.both)
    check(r.recovered == [G] && r.pulled == [G] && fileText(sw.mac.appendingPathComponent("\(G)/DATA00.BIN")) == "sw-phone"
          && fileText(r.backups.last!.appendingPathComponent("\(G)/DATA00.BIN")) == "d1", "recovered, then pulled with a backup \(r)")
    //  d) an orphan .sync-old next to a present target is kept among the backups, never deleted.
    try! fm.copyItem(at: sw.mac.appendingPathComponent(G), to: sw.mac.appendingPathComponent(".\(G).sync-old"))
    r = try! syncer(sw).run(.both)
    check(r.recovered.isEmpty && r.backups.first?.lastPathComponent.hasSuffix("-mac-recovered") == true
          && !fm.fileExists(atPath: sw.mac.appendingPathComponent(".\(G).sync-old").path), "orphan kept in backups \(r)")

    // 13. A phone that never saved (no Documents/savedata): pushed, no backup.
    let f = env("fresh")
    try! fm.removeItem(at: f.phoneSaves)
    r = try! syncer(f).run(.both)
    check(r.pushed == [G] && r.backups.isEmpty && hash(f.phoneSaves) == hash(f.mac), "fresh phone \(r)")
    check(!fm.fileExists(atPath: f.root.appendingPathComponent("staging").path)
          || (try! fm.contentsOfDirectory(atPath: f.root.appendingPathComponent("staging").path)).isEmpty,
          "staging cleaned")

    // 14. The phone copy itself fails (Task 9 hardening). Before writing anything: the
    //     transport's error comes back, the phone keeps its save, no restore is attempted.
    let tf = env("copyfail")
    _ = try! syncer(tf).run(.both)
    let tfBase = SyncState.load(tf.state).base[G]
    writeFile(tf.mac.appendingPathComponent("\(G)/DATA00.BIN"), "tf-mac")
    tf.phone.failWhen = { $0.hasPrefix("dir to") ? DeviceError(code: DeviceError.locked, domain: "fake", message: "locked") : nil }
    do { _ = try syncer(tf).run(.both); check(false, "failed copy must throw") }
    catch let x as DeviceError { check(x.code == DeviceError.locked, "\(x)") }
    catch { check(false, "expected the transport error, got \(error)") }
    tf.phone.failWhen = nil
    check(tf.phone.ops.filter { $0.hasPrefix("dir to") }.count == 1
          && fileText(tf.phoneSaves.appendingPathComponent("\(G)/DATA00.BIN")) == "d1"
          && SyncState.load(tf.state).base[G] == tfBase, "untouched phone, no restore, base kept \(tf.phone.ops)")
    //     After writing part of it: the verified backup is put back, then the error comes back.
    let partial = PartialCopyTransport(tf.phone)
    let ps = SaveSyncer(transport: partial, device: "00008110-TEST", bundle: "com.example.gow2", macRoot: tf.mac,
                        backupRoot: tf.backups, stateURL: tf.state, staging: tf.root.appendingPathComponent("staging"),
                        facts: exactFacts, macGameRunning: { false }, now: { Date(timeIntervalSince1970: 1790372701) })
    do { _ = try ps.run(.both); check(false, "partial copy must throw") }
    catch let x as DeviceError { check(x.code == DeviceError.noDevice, "\(x)") }
    catch { check(false, "expected the transport error, got \(error)") }
    check(fileText(tf.phoneSaves.appendingPathComponent("\(G)/DATA00.BIN")) == "d1"
          && fileText(tf.phoneSaves.appendingPathComponent("\(G)/MASTER.BIN")) == "m1"
          && tf.phone.ops.filter { $0.hasPrefix("dir to") }.count == 3, "phone restored after a partial copy \(tf.phone.ops)")

    // 15. Something that is not a save sits where the pulled save goes: it is moved to the
    //     backups (never deleted) before the phone's save takes its place.
    let pf = env("plainfile")
    try! fm.removeItem(at: pf.mac.appendingPathComponent(G))
    writeFile(pf.mac.appendingPathComponent(G), "not a save")
    r = try! syncer(pf).run(.both)
    check(r.pulled == [G] && hash(pf.mac) == hash(pf.phoneSaves)
          && r.backups.contains { fileText($0.appendingPathComponent(G)) == "not a save" }
          && !fm.fileExists(atPath: pf.mac.appendingPathComponent(".\(G).sync-old").path), "plain file kept in backups \(r)")
}

/// Writes the first file of a directory copy, then fails once (a cable pulled mid-copy).
final class PartialCopyTransport: DeviceTransport {
    let inner: FakeTransport
    var failed = false
    init(_ inner: FakeTransport) { self.inner = inner }
    func devices() throws -> [IOSDevice] { try inner.devices() }
    func lockState(_ device: String) throws -> IOSLockState { try inner.lockState(device) }
    func apps(_ device: String) throws -> [IOSApp] { try inner.apps(device) }
    func processes(_ device: String) throws -> [String] { try inner.processes(device) }
    func files(_ device: String, bundle: String, under dir: String) throws -> [RemoteFile] {
        try inner.files(device, bundle: bundle, under: dir)
    }
    func copyFileTo(_ device: String, bundle: String, local: URL, remote: String) throws {
        try inner.copyFileTo(device, bundle: bundle, local: local, remote: remote)
    }
    func copyDirectoryTo(_ device: String, bundle: String, local: URL, remote: String, removeExisting: Bool) throws {
        if failed { return try inner.copyDirectoryTo(device, bundle: bundle, local: local, remote: remote, removeExisting: removeExisting) }
        failed = true
        let one = FileManager.default.temporaryDirectory.appendingPathComponent("partial-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: one) }
        let first = try FileManager.default.contentsOfDirectory(atPath: local.path).sorted()[0]
        try FileManager.default.createDirectory(at: one, withIntermediateDirectories: true)
        try FakeTransport.place(local.appendingPathComponent(first), at: one.appendingPathComponent(first))
        try inner.copyDirectoryTo(device, bundle: bundle, local: one, remote: remote, removeExisting: removeExisting)
        throw DeviceError(code: DeviceError.noDevice, domain: "fake", message: "device went away")
    }
    func copyFileFrom(_ device: String, bundle: String, remote: String, local: URL) throws {
        try inner.copyFileFrom(device, bundle: bundle, remote: remote, local: local)
    }
    func copyDirectoryFrom(_ device: String, bundle: String, remote: String, local: URL) throws {
        try inner.copyDirectoryFrom(device, bundle: bundle, remote: remote, local: local)
    }
    func cancel() { inner.cancel() }
}
