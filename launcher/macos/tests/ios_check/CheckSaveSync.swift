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
}
