import Foundation
import CryptoKit

func sha(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }

/// A small game tree: EBOOT.ELF (ELF magic), USRDIR/{gow2.psarc,sub/a.bin,.DS_Store}, movie_cache/intro.m2v.
func makeGameTree(_ root: URL) -> (elf: URL, usrdir: URL, movies: URL) {
    let elf = root.appendingPathComponent("EBOOT.ELF")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try! (Data([0x7F, 0x45, 0x4C, 0x46]) + Data("rest".utf8)).write(to: elf)
    let t = Date(timeIntervalSince1970: 1784521789)
    try! FileManager.default.setAttributes([.modificationDate: t], ofItemAtPath: elf.path)
    writeFile(root.appendingPathComponent("USRDIR/gow2.psarc"), "PSARC-DATA", mtime: t)
    writeFile(root.appendingPathComponent("USRDIR/sub/a.bin"), "A", mtime: t)
    writeFile(root.appendingPathComponent("USRDIR/.DS_Store"), "junk", mtime: t)
    writeFile(root.appendingPathComponent("movies/intro.m2v"), "MOVIE", mtime: t)
    return (elf, root.appendingPathComponent("USRDIR"), root.appendingPathComponent("movies"))
}

func runManifestChecks() {
    let root = tempDir("manifest")
    let g = makeGameTree(root.appendingPathComponent("game"))
    let src = try! InstallSources.collect(elf: g.elf, usrdir: g.usrdir, movieCache: g.movies)
    check(src.map(\.rel) == ["EBOOT.ELF", "USRDIR/gow2.psarc", "USRDIR/sub/a.bin", "movie_cache/intro.m2v"],
          "sources, hidden files skipped, sorted: \(src.map(\.rel))")
    check((try? InstallSources.collect(elf: g.elf, usrdir: g.usrdir, movieCache: nil))?.count == 3, "movie_cache optional")
    check((try? InstallSources.collect(elf: g.elf, usrdir: g.usrdir, movieCache: root.appendingPathComponent("none")))?.count == 3,
          "missing movie_cache skipped")
    do { _ = try InstallSources.collect(elf: g.usrdir.appendingPathComponent("gow2.psarc"), usrdir: g.usrdir, movieCache: nil)
         check(false, "not an ELF must throw") }
    catch let e as InstallSources.Failure { check(e.userMessage.contains("EBOOT.ELF"), "notELF message") }
    catch { check(false, "\(error)") }
    try! FileManager.default.createSymbolicLink(at: g.usrdir.appendingPathComponent("link.bin"),
                                                withDestinationURL: g.usrdir.appendingPathComponent("sub/a.bin"))
    do { _ = try InstallSources.collect(elf: g.elf, usrdir: g.usrdir, movieCache: nil); check(false, "symlink must throw") }
    catch let e as InstallSources.Failure { check(e == .symlink("USRDIR/link.bin"), "symlink \(e)") }
    catch { check(false, "\(error)") }
    try! FileManager.default.removeItem(at: g.usrdir.appendingPathComponent("link.bin"))

    // Hash cache: the second build hashes nothing; a changed mtime rehashes (Review Focus 5).
    let cacheURL = root.appendingPathComponent("hash-cache.json")
    let c1 = HashCache(url: cacheURL)
    let m1 = try! InstallManifestBuilder.build(src, cache: c1)
    check(c1.hashedBytes == 8 + 10 + 1 + 5, "first build hashes every byte: \(c1.hashedBytes)")
    check(m1.entries.first { $0.path == "USRDIR/gow2.psarc" }?.sha256 == sha("PSARC-DATA"), "sha256 of the psarc")
    check(m1.entries.first { $0.path == "USRDIR/gow2.psarc" }?.mtime == 1784521789, "mtime in seconds")
    let c2 = HashCache(url: cacheURL)
    let m2 = try! InstallManifestBuilder.build(src, cache: c2)
    check(c2.hashedBytes == 0 && m2 == m1, "second build served from the saved cache")
    writeFile(g.usrdir.appendingPathComponent("gow2.psarc"), "PSARC-DATB", mtime: Date(timeIntervalSince1970: 1784521790))
    let c3 = HashCache(url: cacheURL)
    let m3 = try! InstallManifestBuilder.build(src, cache: c3)
    check(c3.hashedBytes == 10 && m3.entries.first { $0.path == "USRDIR/gow2.psarc" }?.sha256 == sha("PSARC-DATB"),
          "same size, new mtime -> rehashed: \(c3.hashedBytes)")
    check(m3.setID != m1.setID && m3.totalBytes == 24, "set id follows the content")
    // Replaced with the same size AND the old mtime (Codex review 1): the ctime still moves -> rehashed.
    writeFile(g.usrdir.appendingPathComponent("gow2.psarc"), "PSARC-DATC", mtime: Date(timeIntervalSince1970: 1784521790))
    let c4 = HashCache(url: cacheURL)
    let m4 = try! InstallManifestBuilder.build(src, cache: c4)
    check(c4.hashedBytes == 10 && m4.entries.first { $0.path == "USRDIR/gow2.psarc" }?.sha256 == sha("PSARC-DATC")
          && m4.entries.first { $0.path == "USRDIR/gow2.psarc" }?.mtime == 1784521790, "same size + same mtime -> rehashed")
    writeFile(g.usrdir.appendingPathComponent("gow2.psarc"), "PSARC-DATB", mtime: Date(timeIntervalSince1970: 1784521790))
    _ = try! InstallManifestBuilder.build(src, cache: HashCache(url: cacheURL))
    check(byteOrder("USRDIR/b", "movie_cache/a") && byteOrder("Z", "a") && !byteOrder("a", "a"), "byte order (strcmp)")

    // Format: exactly what the iOS parser accepts (C probe on a fake Documents).
    let text = m3.serialized()
    check(text.hasPrefix("gow2-install 1\nset \(m3.setID)\nfile 8 ") && text.hasSuffix("end 4\n"), "format:\n\(text)")
    let docs = root.appendingPathComponent("Documents")
    for e in m3.entries {
        let dst = docs.appendingPathComponent(e.path)
        try! FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! FileManager.default.copyItem(at: e.source, to: dst)
    }
    check(probeState(docs) == 2, "files without the manifest: incomplete")
    try! InstallManifest.incompleteMarker.write(to: docs.appendingPathComponent(InstallManifest.fileName), atomically: true, encoding: .utf8)
    check(probeState(docs) == 2, "marker: incomplete")
    try! text.write(to: docs.appendingPathComponent(InstallManifest.fileName), atomically: true, encoding: .utf8)
    check(probeState(docs) == 1, "the iOS parser accepts the Swift manifest")

    // Plan: skip needs phone size+mtime AND the pushed-hash record; else small -> verify, large -> copy.
    let m5 = try! InstallManifestBuilder.build(src, cache: HashCache(url: cacheURL))
    let eboot = m5.entries.first { $0.path == "EBOOT.ELF" }!, psarc = m5.entries.first { $0.path == "USRDIR/gow2.psarc" }!
    let remote = [RemoteFile(path: "EBOOT.ELF", size: 8, mtime: 1784521789, isDirectory: false),
                  RemoteFile(path: "USRDIR/gow2.psarc", size: 10, mtime: 1784521790, isDirectory: false),
                  RemoteFile(path: "USRDIR/sub", size: 64, mtime: 1, isDirectory: true),
                  RemoteFile(path: "movie_cache/intro.m2v", size: 4, mtime: 1784521789, isDirectory: false)] // torn
    let pushed = ["EBOOT.ELF": PushedFile(size: 8, mtime: 1784521789, sha256: eboot.sha256),
                  "USRDIR/gow2.psarc": PushedFile(size: 10, mtime: 1784521790, sha256: sha("PSARC-DATC"))] // old content
    let plan = InstallPlan.split(m5, remote: remote, pushed: pushed, verifyLimit: 64)
    check(plan.skip.map(\.path) == ["EBOOT.ELF"], "skip only with a matching record: \(plan.skip.map(\.path))")
    check(plan.verify.map(\.path) == ["USRDIR/gow2.psarc"], "same size+mtime, other hash -> verify: \(plan.verify.map(\.path))")
    check(plan.copy.map(\.path) == ["USRDIR/sub/a.bin", "movie_cache/intro.m2v"], "copy \(plan.copy.map(\.path))")
    check(InstallPlan.step(psarc, remote: remote[1], pushed: pushed["USRDIR/gow2.psarc"], verifyLimit: 4) == .copy,
          "a large file without a matching record is copied again")
    check(InstallPlan.step(eboot, remote: remote[0], pushed: nil, verifyLimit: 64) == .verify, "no record (P1 data) -> verify")

    checkByteOrderVsSwiftDefault()
    try? FileManager.default.removeItem(at: root)
}

/// Binding cross-task check (coordinator instruction / Review Focus 5): the Swift writer must
/// sort by raw UTF-8 byte order -- what byteOrder() implements and what the C parser's strcmp
/// enforces (gow2_ios_install_manifest.c) -- never by Swift's default String order, which is
/// Unicode-canonical: a precomposed "é" (U+00E9, bytes 0xC3 0xA9) and a decomposed "e" +
/// combining acute (U+0065 U+0301, bytes 0x65 0xCC 0x81) compare EQUAL under Swift's `<` (so
/// `sorted()` would leave them in whatever order they started in), while their UTF-8 bytes are
/// strictly ordered (decomposed first: 0x65 < 0xC3). If InstallManifest ever used the default
/// order instead of byteOrder, a manifest built with these two paths in the "wrong" (NFC-first)
/// order would come out unsorted and the real C parser would reject it. This proves it does not,
/// round-tripping through the actual parser (manifest_probe), not just an in-memory assertion.
private func checkByteOrderVsSwiftDefault() {
    let precomposed = "USRDIR/zcaf\u{e9}.bin"    // NFC: z c a f é
    let decomposed = "USRDIR/zcafe\u{301}.bin"   // NFD: z c a f e + combining acute (U+0301)
    check(precomposed == decomposed, "sanity: Swift treats NFC/NFD as the same String value (== is canonical, not byte-wise)")
    check(Array(precomposed.utf8) != Array(decomposed.utf8), "sanity: their UTF-8 bytes are nonetheless different")
    check(byteOrder(decomposed, precomposed) && !byteOrder(precomposed, decomposed),
          "byte order strictly ranks NFD before NFC")
    check(!(precomposed < decomposed) && !(decomposed < precomposed),
          "control: Swift's default String order treats NFC/NFD as equal -- without byteOrder this test would be moot")

    // A second, filesystem-safe (pure ASCII) pair where a naive component-wise comparator could
    // still get the boundary wrong: '.' (0x2E) sorts before '/' (0x2F), so "USRDIR/sub.bin" comes
    // before "USRDIR/sub/x.bin" in byte order, same as Swift's default order here -- pinned so a
    // future change to byteOrder cannot special-case path separators.
    check(byteOrder("USRDIR/sub.bin", "USRDIR/sub/x.bin"), "dot sorts before slash")
    // Uppercase vs lowercase (both orders agree for plain ASCII -- included per the review focus,
    // pinned so byteOrder never grows a case-insensitive comparison).
    check(byteOrder("USRDIR/A.bin", "USRDIR/a.bin"), "uppercase sorts before lowercase (ASCII)")

    let root = tempDir("manifest-order")
    let docs = root.appendingPathComponent("Documents")
    writeFile(docs.appendingPathComponent("EBOOT.ELF"), "EBOOT-BYTES")
    writeFile(docs.appendingPathComponent("USRDIR/gow2.psarc"), "PSARC")
    // One real file (written under the precomposed spelling) backs BOTH manifest entries: the
    // Mac's default volume is case- and normalization-insensitive for lookups (measured this
    // session), so `stat()` on either byte spelling resolves to it with the same size -- only the
    // manifest's own path bytes (not the filesystem) decide whether the sort check passes.
    let cafeContent = "CAFE-BYTES"
    writeFile(docs.appendingPathComponent(precomposed), cafeContent)
    let cafeSize = Int64(cafeContent.utf8.count)
    let entries = [
        ManifestEntry(path: "EBOOT.ELF", size: 11, mtime: 0, ctimeNs: 0, sha256: sha("EBOOT-BYTES"),
                      source: docs.appendingPathComponent("EBOOT.ELF")),
        ManifestEntry(path: "USRDIR/gow2.psarc", size: 5, mtime: 0, ctimeNs: 0, sha256: sha("PSARC"),
                      source: docs.appendingPathComponent("USRDIR/gow2.psarc")),
        ManifestEntry(path: precomposed, size: cafeSize, mtime: 0, ctimeNs: 0, sha256: sha(cafeContent),
                      source: docs.appendingPathComponent(precomposed)),
        ManifestEntry(path: decomposed, size: cafeSize, mtime: 0, ctimeNs: 0, sha256: sha(cafeContent),
                      source: docs.appendingPathComponent(decomposed)),
    ]
    let orderManifest = InstallManifest(entries: entries)
    // Swift's String `==`/`<` are canonical (NFC == NFD), so comparing [String] here would pass
    // no matter which physical order the two café entries ended up in; compare raw UTF-8 bytes
    // per entry instead, which is what actually reaches the wire (and what strcmp sees).
    let gotBytes = orderManifest.entries.map { Array($0.path.utf8) }
    let wantBytes = ["EBOOT.ELF", "USRDIR/gow2.psarc", decomposed, precomposed].map { Array($0.utf8) }
    check(gotBytes == wantBytes, "InstallManifest sorts NFC/NFD entries by raw bytes, not Swift's default order")

    let serializedText = orderManifest.serialized()
    try! serializedText.write(to: docs.appendingPathComponent(InstallManifest.fileName), atomically: true, encoding: .utf8)
    // Same point, checked directly on the bytes actually written to disk (belt and suspenders).
    let serializedBytes = Data(serializedText.utf8)
    if let rd = serializedBytes.range(of: Data(decomposed.utf8)), let rp = serializedBytes.range(of: Data(precomposed.utf8)) {
        check(rd.lowerBound < rp.lowerBound, "the decomposed entry's line precedes the precomposed one in the written bytes")
    } else {
        check(false, "could not locate both NFC/NFD entries in the written manifest bytes")
    }
    let state = probeState(docs)
    check(state == 1, "the real C parser accepts the NFC/NFD manifest sorted by byte order (state=\(state))")
    try? FileManager.default.removeItem(at: root)
}
