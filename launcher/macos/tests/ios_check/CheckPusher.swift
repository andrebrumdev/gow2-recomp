import Foundation

func fileText(_ u: URL) -> String? { try? String(contentsOf: u, encoding: .utf8) }

func runPusherChecks() {
    let root = tempDir("pusher")
    let g = makeGameTree(root.appendingPathComponent("game"))
    let src = try! InstallSources.collect(elf: g.elf, usrdir: g.usrdir, movieCache: g.movies)
    let cache = HashCache(url: root.appendingPathComponent("hc.json"))
    let m = try! InstallManifestBuilder.build(src, cache: cache)
    let phone = FakeTransport(root: root.appendingPathComponent("container"))
    let docs = phone.root.appendingPathComponent("Documents")
    try! FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    let record = root.appendingPathComponent("pushed.json")
    let pusher = DataPusher(transport: phone, device: "00008110-TEST", bundle: "com.example.gow2",
                            staging: root.appendingPathComponent("staging"), recordURL: record)
    let locked = DeviceError(code: DeviceError.locked, domain: "com.apple.dt.CoreDeviceError", message: "locked")

    // 1. Locked mid-copy (Review Focus 1): EBOOT copied and verified, psarc fails, the app reads "incomplete".
    phone.failWhen = { $0 == "to Documents/USRDIR/gow2.psarc" ? locked : nil }
    do { _ = try pusher.push(m); check(false, "locked copy must throw") }
    catch let e as DeviceError { check(e.isLocked, "locked \(e)") }
    catch { check(false, "\(error)") }
    check(Array(phone.ops.prefix(5)) == ["to Documents/gow2-install.manifest", "dir to Documents/USRDIR",
                                         "dir to Documents/movie_cache", "to Documents/EBOOT.ELF", "from Documents/EBOOT.ELF"],
          "marker first, then parents, then copy + download-verify: \(phone.ops)")
    check(probeState(docs) == 2, "between the two runs the app says not installed")
    check(PushedRecord.load(record).files.keys.sorted() == ["EBOOT.ELF"], "only the verified file is recorded")

    // 2. Resume: only what is missing is copied; manifest last and read back.
    phone.failWhen = nil
    var seen: [PushProgress] = []
    let out = try! pusher.push(m, progress: { seen.append($0) })
    check(out == .installed(copied: 3, skipped: 1), "resume copies 3, skips EBOOT: \(out)")
    check(seen.last?.doneBytes == 10 + 1 + 5 && seen.last?.totalBytes == 16 && seen.last?.count == 3, "progress \(String(describing: seen.last))")
    check(Array(phone.ops.suffix(2)) == ["to Documents/gow2-install.manifest", "from Documents/gow2-install.manifest"],
          "manifest written last and read back: \(phone.ops.suffix(2))")
    check(probeState(docs) == 1, "the app now says installed")

    // 3. Nothing to do: one read of the manifest, no copy.
    let before = phone.ops.count
    check((try? pusher.push(m)) == .alreadyInstalled, "second push is a no-op")
    check(Array(phone.ops.dropFirst(before)) == ["from Documents/gow2-install.manifest"], "no-op ops \(phone.ops.dropFirst(before))")

    // 4. Changed file on the Mac (Review Focus 5) -> only it is re-copied.
    writeFile(g.movies.appendingPathComponent("intro.m2v"), "MOVIE2", mtime: Date(timeIntervalSince1970: 1784600000))
    let m2 = try! InstallManifestBuilder.build(src, cache: cache)
    check((try? pusher.push(m2)) == .installed(copied: 1, skipped: 3), "changed file re-copied")

    // 5. Replaced on the Mac with the SAME size and the SAME mtime (Codex review 1): the phone
    //    matches on size+mtime, but the record names the old hash -> re-copied, for a small
    //    file (download-verify) and for a large one (verifyLimit below its size).
    writeFile(g.usrdir.appendingPathComponent("gow2.psarc"), "PSARC-DATX", mtime: Date(timeIntervalSince1970: 1784521789))
    let m3 = try! InstallManifestBuilder.build(src, cache: cache)
    check((try? pusher.push(m3)) == .installed(copied: 1, skipped: 3)
          && fileText(docs.appendingPathComponent("USRDIR/gow2.psarc")) == "PSARC-DATX", "same size+mtime, new bytes: small file")
    let bigPusher = DataPusher(transport: phone, device: "d", bundle: "b", staging: root.appendingPathComponent("staging"),
                               recordURL: record, verifyLimit: 4)
    writeFile(g.usrdir.appendingPathComponent("gow2.psarc"), "PSARC-DATY", mtime: Date(timeIntervalSince1970: 1784521789))
    let m4 = try! InstallManifestBuilder.build(src, cache: cache)
    let opsBig = phone.ops.count
    check((try? bigPusher.push(m4)) == .installed(copied: 1, skipped: 3)
          && fileText(docs.appendingPathComponent("USRDIR/gow2.psarc")) == "PSARC-DATY", "same size+mtime, new bytes: large file")
    check(!phone.ops.dropFirst(opsBig).contains("from Documents/USRDIR/gow2.psarc"), "a large file is not downloaded back")
    check(probeState(docs) == 1, "installed after the same-size replacements")

    // 5b. Fact F4 (a copy onto a same-size, same-mtime file is skipped by devicectl): a LARGE
    //     file replaced on the Mac with the same size and mtime must still reach the phone before
    //     the complete manifest names it — never a complete manifest over the old bytes.
    try! (Data([0x7F, 0x45, 0x4C, 0x46]) + Data("REST".utf8)).write(to: g.elf)
    try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1784521789)], ofItemAtPath: g.elf.path)
    let m4b = try! InstallManifestBuilder.build(src, cache: cache)
    check((try? bigPusher.push(m4b)) == .installed(copied: 1, skipped: 3), "same size+mtime EBOOT (large) re-copied")
    check((try? Data(contentsOf: docs.appendingPathComponent("EBOOT.ELF"))) == (try? Data(contentsOf: g.elf))
          && fileText(docs.appendingPathComponent(InstallManifest.fileName)) == m4b.serialized()
          && probeState(docs) == 1, "complete manifest only over the new bytes of the large file")

    // 6. Same-length corruption on the way (a small file, the level we can check): caught by the
    //    download hash before the manifest; the record forgets the file; a retry fixes it.
    writeFile(g.movies.appendingPathComponent("intro.m2v"), "MOVIE3", mtime: Date(timeIntervalSince1970: 1784600001))
    let m5 = try! InstallManifestBuilder.build(src, cache: cache)
    phone.corruptPrefix = "Documents/movie_cache/"
    phone.corruptNext = 1
    do { _ = try pusher.push(m5); check(false, "corruption must be caught") }
    catch let e as PushError { check(e == .verifyFailed("movie_cache/intro.m2v"), "corruption \(e)") }
    catch { check(false, "\(error)") }
    check(probeState(docs) == 2 && PushedRecord.load(record).files["movie_cache/intro.m2v"] == nil, "no manifest, no record")
    check((try? pusher.push(m5)) == .installed(copied: 1, skipped: 3)
          && fileText(docs.appendingPathComponent("movie_cache/intro.m2v")) == "MOVIE3", "retry after corruption")

    // 7. Cancel before the first file: the phone keeps the marker.
    writeFile(g.movies.appendingPathComponent("intro.m2v"), "MOVIE4", mtime: Date(timeIntervalSince1970: 1784600002))
    let m6 = try! InstallManifestBuilder.build(src, cache: cache)
    do { _ = try pusher.push(m6, cancelled: { true }); check(false, "cancel must throw") }
    catch let e as PushError { check(e == .cancelled && e.userMessage.contains("continuar"), "cancel \(e)") }
    catch { check(false, "\(error)") }
    check(probeState(docs) == 2, "cancelled push leaves the marker")

    // 8. A copy that silently did not land is caught right after it.
    phone.dropWritesUnder = "Documents/movie_cache/"
    do { _ = try pusher.push(m6); check(false, "verify must fail") }
    catch let e as PushError { check(e == .verifyFailed("movie_cache/intro.m2v"), "verify \(e)") }
    catch { check(false, "\(error)") }
    check(probeState(docs) == 2, "no manifest after a failed verify")
    phone.dropWritesUnder = nil
    check((try? pusher.push(m6)) == .installed(copied: 1, skipped: 3), "retry after the failed verify")

    // 9. P1-style data (copied without the launcher, no record): small files are verified by
    //    download and kept, large ones are copied again; a wrong small file is replaced.
    let p1 = FakeTransport(root: root.appendingPathComponent("container-p1"))
    for e in m6.entries {
        let dst = p1.root.appendingPathComponent("Documents/" + e.path)
        try! FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! FakeTransport.place(e.source, at: dst)
    }
    let a = p1.root.appendingPathComponent("Documents/USRDIR/sub/a.bin")
    let am = try! FileManager.default.attributesOfItem(atPath: a.path)[.modificationDate] as! Date
    writeFile(a, "Z", mtime: am)                                      // same size and mtime, other bytes
    let adopt = DataPusher(transport: p1, device: "d", bundle: "b", staging: root.appendingPathComponent("staging-p1"),
                           recordURL: root.appendingPathComponent("pushed-p1.json"), verifyLimit: 6)
    check((try? adopt.push(m6)) == .installed(copied: 3, skipped: 1), "EBOOT (8) and psarc (10) re-copied, a.bin fixed, intro (6) kept")
    check(fileText(a) == "A" && probeState(p1.root.appendingPathComponent("Documents")) == 1, "P1 data adopted")

    // 10. A freshly installed app: Documents exists and is empty.
    let fresh = FakeTransport(root: root.appendingPathComponent("container2"))
    try! FileManager.default.createDirectory(at: fresh.root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    let p2 = DataPusher(transport: fresh, device: "d", bundle: "b", staging: root.appendingPathComponent("staging2"),
                        recordURL: root.appendingPathComponent("pushed2.json"))
    check((try? p2.push(m6)) == .installed(copied: 4, skipped: 0), "fresh container")

    // 11. Cancel pressed while a file already on the phone is being invalidated (final review 5):
    //     transport.cancel() may be lost in that window, so the pusher checks the flag again
    //     right before the real copy -- the real copy never starts.
    writeFile(g.movies.appendingPathComponent("intro.m2v"), "MOVIE5", mtime: Date(timeIntervalSince1970: 1784600003))
    let m7 = try! InstallManifestBuilder.build(src, cache: cache)
    var cancelNow = false
    let introOp = "to Documents/movie_cache/intro.m2v"
    fresh.failWhen = { op in
        if op == introOp { cancelNow = true }                    // the placeholder upload of invalidate()
        return nil
    }
    let opsCancel = fresh.ops.count
    do { _ = try p2.push(m7, cancelled: { cancelNow }); check(false, "cancel during invalidate must throw") }
    catch let e as PushError { check(e == .cancelled, "cancel during invalidate \(e)") }
    catch { check(false, "\(error)") }
    check(fresh.ops.dropFirst(opsCancel).filter { $0 == introOp }.count == 1,
          "only the placeholder was uploaded, no real copy after the cancel: \(fresh.ops.dropFirst(opsCancel))")
    fresh.failWhen = nil
    check((try? p2.push(m7)) == .installed(copied: 1, skipped: 3), "resume after the cancel during invalidate")

    // 12. Cancel pressed during a verify download (P1-style data, no record): nothing more is
    //     copied after that download.
    let p1b = FakeTransport(root: root.appendingPathComponent("container-p1b"))
    for e in m7.entries {
        let dst = p1b.root.appendingPathComponent("Documents/" + e.path)
        try! FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! FakeTransport.place(e.source, at: dst)
    }
    var cancelVerify = false
    p1b.failWhen = { op in
        if op.hasPrefix("from Documents/") && op != "from Documents/gow2-install.manifest" { cancelVerify = true }
        return nil
    }
    let adoptB = DataPusher(transport: p1b, device: "d", bundle: "b", staging: root.appendingPathComponent("staging-p1b"),
                            recordURL: root.appendingPathComponent("pushed-p1b.json"), verifyLimit: 6)
    do { _ = try adoptB.push(m7, cancelled: { cancelVerify }); check(false, "cancel during a verify download must throw") }
    catch let e as PushError { check(e == .cancelled, "cancel during verify \(e)") }
    catch { check(false, "\(error)") }
    if let i = p1b.ops.firstIndex(where: { $0.hasPrefix("from Documents/") && $0 != "from Documents/gow2-install.manifest" }) {
        let after = Array(p1b.ops[(i + 1)...])
        check(after.isEmpty, "nothing after the cancelled verify download: \(after)")
        check(PushedRecord.load(root.appendingPathComponent("pushed-p1b.json")).files.isEmpty,
              "the cancelled verify records nothing")
    } else {
        check(false, "no verify download happened: \(p1b.ops)")
    }

    // 13. Incident 2026-09-26: after a wipe, Documents/USRDIR has no file node at all, and
    //     the real device answered ensureDirectories's own pre-creation `copy to` with
    //     CoreDeviceError 7000 "Failed to retrieve the file node for Documents/USRDIR" instead
    //     of creating it -- uncaught, that aborted the whole install ("Instalar no iPhone"
    //     failed outright). The push must still finish: fact F1 says the per-file `copy to`
    //     that follows creates any parent directory still missing on its own.
    //     (Before the ensureDirectories fix in IOSDataPusher.swift, this check fails: the
    //     injected error propagates out of push() uncaught and `try?` below returns nil.)
    let missingUSRDIR = DeviceError(code: DeviceError.notFound, domain: "com.apple.dt.CoreDeviceError",
                                    message: "Failed to retrieve the file node for Documents/USRDIR")
    let wiped = FakeTransport(root: root.appendingPathComponent("container-wiped"))
    try! FileManager.default.createDirectory(at: wiped.root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    wiped.failWhen = { $0 == "dir to Documents/USRDIR" ? missingUSRDIR : nil }
    let wipedPusher = DataPusher(transport: wiped, device: "d", bundle: "b", staging: root.appendingPathComponent("staging-wiped"),
                                 recordURL: root.appendingPathComponent("pushed-wiped.json"))
    check((try? wipedPusher.push(m7)) == .installed(copied: 4, skipped: 0),
          "USRDIR pre-creation failing like the wiped phone still installs")
    check(fileText(wiped.root.appendingPathComponent("Documents/USRDIR/gow2.psarc")) != nil
          && fileText(wiped.root.appendingPathComponent("Documents/USRDIR/sub/a.bin")) != nil,
          "the files themselves still landed under USRDIR despite the failed pre-creation")

    // Production argv and the F5 gate (the thin layer).
    check(Devicectl.args(.copyTo("D", bundle: "B", local: "/l", remote: "Documents/x", removeExisting: true), json: "/j")
          == ["devicectl", "device", "copy", "to", "--device", "D", "--domain-type", "appDataContainer",
              "--domain-identifier", "B", "--source", "/l", "--destination", "Documents/x",
              "--remove-existing-content", "true", "-j", "/j", "-q"], "copy to argv")
    check(Devicectl.args(.files("D", bundle: "B", dir: "Documents"), json: "/j")
          == ["devicectl", "device", "info", "files", "--device", "D", "--domain-type", "appDataContainer",
              "--domain-identifier", "B", "--subdirectory", "Documents", "-t", "120", "-j", "/j", "-q"], "files argv")
    check(Devicectl.args(.devices, json: "/j") == ["devicectl", "list", "devices", "-t", "30", "-j", "/j", "-q"], "devices argv")
    let tmp = URL(fileURLWithPath: "/t")
    var f5 = DeviceFacts()
    do { _ = try Devicectl.contentsRoot(tmp: tmp, remote: "Documents/savedata", facts: f5); check(false, "F5 unmeasured must refuse") }
    catch let e as DeviceError { check(e.code == DeviceError.factMissing, "F5 gate \(e)") }
    catch { check(false, "\(error)") }
    f5.copyFromNestsDirectory = false
    check((try? Devicectl.contentsRoot(tmp: tmp, remote: "Documents/savedata", facts: f5))?.path == "/t", "F5 false: contents at the destination")
    f5.copyFromNestsDirectory = true
    check((try? Devicectl.contentsRoot(tmp: tmp, remote: "Documents/savedata", facts: f5))?.path == "/t/savedata", "F5 true: nested")
    do { _ = try DevicectlTransport(facts: DeviceFacts()).copyDirectoryFrom("D", bundle: "B", remote: "Documents/savedata",
                                                                         local: root.appendingPathComponent("never"))
         check(false, "the production transport must refuse without F5") }
    catch let e as DeviceError { check(e.code == DeviceError.factMissing, "production F5 gate \(e)") }
    catch { check(false, "\(error)") }
    try? FileManager.default.removeItem(at: root)
}
