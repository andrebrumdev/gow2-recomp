import Foundation

func snap(_ n: String, _ h: String) -> SaveDirSnapshot { SaveDirSnapshot(name: n, hash: h, newest: 0, files: 1) }

func runSaveSyncPlanChecks() {
    let G = "BCUS98229_GOW2"
    func d(_ m: [String: SaveDirSnapshot], _ p: [String: SaveDirSnapshot], _ b: [String: String], _ mode: SyncMode) -> [SaveAction] {
        SaveSyncPlan.decide(mac: m, phone: p, base: b, mode: mode)
    }
    check(d([G: snap(G, "a")], [G: snap(G, "a")], [:], .both) == [.same(G)], "identical -> skip")
    check(d([G: snap(G, "a")], [:], [:], .both) == [.push(G)], "only on the Mac -> push")
    check(d([:], [G: snap(G, "a")], [G: "a"], .both) == [.pull(G)], "missing on the Mac: deletions never propagate")
    check(d([G: snap(G, "a")], [G: snap(G, "b")], [:], .both) == [.conflict(G)], "never synced + different = conflict (Review Focus 3)")
    check(d([G: snap(G, "a")], [G: snap(G, "b")], [G: "a"], .both) == [.pull(G)], "only the phone changed -> pull")
    check(d([G: snap(G, "a")], [G: snap(G, "b")], [G: "b"], .both) == [.push(G)], "only the Mac changed -> push")
    check(d([G: snap(G, "a")], [G: snap(G, "b")], [G: "c"], .both) == [.conflict(G)], "both changed -> conflict")
    check(d([G: snap(G, "a")], [G: snap(G, "b")], [G: "c"], .macToPhone) == [.push(G)], "Mac → iPhone")
    check(d([G: snap(G, "a")], [G: snap(G, "b")], [G: "c"], .phoneToMac) == [.pull(G)], "iPhone → Mac")
    check(d([:], [G: snap(G, "b")], [:], .macToPhone) == [.missingSource(G)],
          "Mac → iPhone without a Mac save: nothing copied, reported (never deletes the phone's)")
    check(d([G: snap(G, "a")], [:], [:], .phoneToMac) == [.missingSource(G)],
          "iPhone → Mac without a phone save: nothing copied, reported (never deletes the Mac's)")
    check(d(["BCUS98229_A": snap("BCUS98229_A", "x"), G: snap(G, "a")], [G: snap(G, "a")], [:], .both)
          == [.push("BCUS98229_A"), .same(G)], "per directory, sorted")

    let root = tempDir("savesnap")
    let mac = root.appendingPathComponent("mac"), other = root.appendingPathComponent("other")
    writeFile(mac.appendingPathComponent("\(G)/MASTER.BIN"), "m1", mtime: Date(timeIntervalSince1970: 1790000000))
    writeFile(mac.appendingPathComponent("\(G)/DATA00.BIN"), "d1", mtime: Date(timeIntervalSince1970: 1790000100))
    writeFile(mac.appendingPathComponent("\(G)/.DS_Store"), "x")
    writeFile(mac.appendingPathComponent("BLUS31017_00000000/00000000.SAV"), "ben10")
    writeFile(other.appendingPathComponent("\(G)/MASTER.BIN"), "m1", mtime: Date(timeIntervalSince1970: 1))
    writeFile(other.appendingPathComponent("\(G)/DATA00.BIN"), "d1", mtime: Date(timeIntervalSince1970: 2))
    let a = try! SaveSnapshot.take(mac), b = try! SaveSnapshot.take(other)
    check(Array(a.keys) == [G], "only GoW2's save directories: \(a.keys)")
    check(a[G]?.hash == b[G]?.hash && a[G]?.files == 2, "same content, other mtimes -> same hash")
    check(a[G]?.newest == 1790000100, "newest mtime shown to the user")
    writeFile(other.appendingPathComponent("\(G)/DATA00.BIN"), "d2")
    check((try! SaveSnapshot.take(other))[G]?.hash != a[G]?.hash, "content change -> new hash")
    check((try! SaveSnapshot.take(root.appendingPathComponent("none"))).isEmpty, "missing root = no saves")

    let st = root.appendingPathComponent("state/save-sync.json")
    check(SyncState.load(st) == SyncState(), "no state file = never synced")
    var s = SyncState()
    s.base[G] = "abc"
    try! s.save(st)
    check(SyncState.load(st).base[G] == "abc", "state round trip")

    let home = tempDir("savehome")
    check(SaveBackup.defaultRoot(home: home).path.hasSuffix("Documents/GoW2 Saves"), "default backup root")
    try! FileManager.default.createDirectory(at: home.appendingPathComponent("Documents/PESSOAL/gow2-saves"),
                                             withIntermediateDirectories: true)
    check(SaveBackup.defaultRoot(home: home).path.hasSuffix("Documents/PESSOAL/gow2-saves"), "the user's backup folder when present")
    check(SaveBackup.folderName(Date(timeIntervalSince1970: 1790372701), side: .mac, timeZone: TimeZone(identifier: "UTC")!)
          == "2026-09-25_214501-mac", "folder name")
    let bk = root.appendingPathComponent("backups")
    let f1 = try! SaveBackup.write(dir: mac.appendingPathComponent(G), name: G, into: bk, folder: "2026-09-25_214501-mac")
    let f2 = try! SaveBackup.write(dir: mac.appendingPathComponent(G), name: G, into: bk, folder: "2026-09-25_214501-mac")
    check(f1.lastPathComponent == "2026-09-25_214501-mac" && f2.lastPathComponent == "2026-09-25_214501-mac-2",
          "a backup is never overwritten")
    let sums = try! String(contentsOf: f1.appendingPathComponent("sha256.txt"), encoding: .utf8)
    check(sums == "\(sha("d1"))  \(G)/DATA00.BIN\n\(sha("m1"))  \(G)/MASTER.BIN\n", "sha256.txt in shasum -c format:\n\(sums)")
    check((try! SaveSnapshot.take(f1))[G]?.hash == a[G]?.hash, "the backup equals the source")
    check(SaveSyncError.gameRunningPhone.userMessage.contains("alternador")
          && SaveSyncError.gameRunningMac.userMessage.contains("Mac"), "refusal messages")
    try? FileManager.default.removeItem(at: root)
    runSaveSnapshotFailClosedChecks()
}

/// The snapshot fails closed (spec: never lose a save): anything it cannot read
/// or that is not plain files and folders is an error, never a smaller snapshot.
func runSaveSnapshotFailClosedChecks() {
    let G = "BCUS98229_GOW2"
    let fm = FileManager.default
    func throwsError(_ f: () throws -> Any) -> Error? {
        do { _ = try f(); return nil } catch { return error }
    }
    func fresh(_ tag: String) -> (root: URL, save: URL) {
        let r = tempDir(tag)
        let s = r.appendingPathComponent("saves/\(G)")
        writeFile(s.appendingPathComponent("MASTER.BIN"), "m1")
        writeFile(s.appendingPathComponent("SUB/DATA00.BIN"), "d1")
        return (r, s)
    }
    func chmod(_ u: URL, _ mode: Int) { try! fm.setAttributes([.posixPermissions: mode], ofItemAtPath: u.path) }

    // (a) unreadable subfolder: two different saves must not hash equal.
    do {
        let (r, s) = fresh("sfc-sub")
        let sub = s.appendingPathComponent("SUB")
        chmod(sub, 0o000)
        let e = throwsError { try SaveSnapshot.take(r.appendingPathComponent("saves")) }
        check(e as? SaveSyncError == .unreadableSave(G), "unreadable subfolder -> throws: \(String(describing: e))")
        check(throwsError { try SaveSnapshot.digest(s) } != nil, "digest of a save with an unreadable subfolder throws")
        chmod(sub, 0o755)
        try? fm.removeItem(at: r)
    }
    // (b) unreadable save folder: never a well-formed empty snapshot.
    do {
        let (r, s) = fresh("sfc-top")
        chmod(s, 0o000)
        let e = throwsError { try SaveSnapshot.take(r.appendingPathComponent("saves")) }
        check(e as? SaveSyncError == .unreadableSave(G), "unreadable save folder -> throws: \(String(describing: e))")
        chmod(s, 0o755)
        try? fm.removeItem(at: r)
    }
    // (c) empty save folder (only hidden files) is not a save.
    do {
        let r = tempDir("sfc-empty")
        writeFile(r.appendingPathComponent("saves/\(G)/.DS_Store"), "x")
        let e = throwsError { try SaveSnapshot.take(r.appendingPathComponent("saves")) }
        check(e as? SaveSyncError == .unreadableSave(G), "empty save folder -> throws: \(String(describing: e))")
        try? fm.removeItem(at: r)
    }
    // (d) symlinked save folder.
    do {
        let (r, s) = fresh("sfc-linkdir")
        let other = r.appendingPathComponent("other")
        try! fm.createDirectory(at: other, withIntermediateDirectories: true)
        try! fm.createSymbolicLink(at: other.appendingPathComponent(G), withDestinationURL: s)
        let e = throwsError { try SaveSnapshot.take(other) }
        check(e as? SaveSyncError == .symlinkInSave(G), "symlinked save folder -> throws: \(String(describing: e))")
        check(throwsError { try SaveSnapshot.digest(other.appendingPathComponent(G)) } != nil, "digest of a symlinked save folder throws")
        // (f) a backup of a symlinked folder is impossible, and leaves nothing behind.
        let bk = r.appendingPathComponent("backups")
        let be = throwsError { try SaveBackup.write(dir: other.appendingPathComponent(G), name: G, into: bk, folder: "f") }
        check(be as? SaveSyncError == .symlinkInSave(G), "backup of a symlinked save folder -> throws: \(String(describing: be))")
        check(!fm.fileExists(atPath: bk.appendingPathComponent("f").path), "a refused backup creates no folder")
        try? fm.removeItem(at: r)
    }
    // (e) symlink inside a save (to a file and to a folder).
    for (tag, dest) in [("file", "MASTER.BIN"), ("dir", "SUB")] {
        let (r, s) = fresh("sfc-link\(tag)")
        try! fm.createSymbolicLink(at: s.appendingPathComponent("LINK_\(tag)"),
                                   withDestinationURL: s.appendingPathComponent(dest))
        let e = throwsError { try SaveSnapshot.take(r.appendingPathComponent("saves")) }
        check(e as? SaveSyncError == .symlinkInSave(G), "symlink (\(tag)) inside a save -> throws: \(String(describing: e))")
        let be = throwsError { try SaveBackup.write(dir: s, name: G, into: r.appendingPathComponent("backups"), folder: "f") }
        check(be != nil, "backup of a save holding a symlink (\(tag)) -> throws")
        try? fm.removeItem(at: r)
    }
    // Messages the user sees.
    check(SaveSyncError.unreadableSave(G).userMessage.contains(G)
          && SaveSyncError.symlinkInSave(G).userMessage.contains(G), "fail-closed messages name the save")
}
