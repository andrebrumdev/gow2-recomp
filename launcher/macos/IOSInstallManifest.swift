import Foundation
import CryptoKit

/// Byte order of the UTF-8 paths: the order the iOS parser checks with strcmp.
func byteOrder(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }

/// One file the iPhone needs, at `path` under the container's Documents.
struct ManifestEntry: Equatable {
    let path: String
    let size: Int64
    let mtime: Int64          // seconds; devicectl keeps it on the copy (facts F3)
    let ctimeNs: Int64        // the Mac file's change time when it was hashed (detects a change during the copy)
    let sha256: String
    let source: URL           // the Mac file (symlinks resolved)
}

/// What the launcher copied to the phone and verified there, per path (P3 record,
/// ~/Library/Application Support/GoW2Recomp/ios/<udid>_<bundle>/pushed.json).
struct PushedFile: Codable, Equatable {
    let size: Int64
    let mtime: Int64
    let sha256: String
}

/// The launcher's install manifest; format parsed by the iOS app
/// (ios/Sources/gow2_ios_install_manifest.h). Pushed LAST; while a push runs
/// the phone holds `incompleteMarker`.
struct InstallManifest: Equatable {
    static let fileName = "gow2-install.manifest"
    static let remotePath = "Documents/gow2-install.manifest"
    static let incompleteMarker = "gow2-install 1\nincomplete\n"
    let entries: [ManifestEntry]

    init(entries: [ManifestEntry]) { self.entries = entries.sorted { byteOrder($0.path, $1.path) } }

    /// Identity of the data set: SHA-256 of the "size sha path" lines.
    var setID: String {
        let lines = entries.map { "\($0.size) \($0.sha256) \($0.path)\n" }.joined()
        return SHA256.hash(data: Data(lines.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.size } }

    func serialized() -> String {
        var s = "gow2-install 1\nset \(setID)\n"
        for e in entries { s += "file \(e.size) \(e.sha256) \(e.path)\n" }
        return s + "end \(entries.count)\n"
    }
}

enum InstallSources {
    struct Source: Equatable {
        let rel: String
        let url: URL
    }

    enum Failure: Error, Equatable {
        case notELF(String), noUSRDIR(String), symlink(String), badName(String)
        var userMessage: String {
            switch self {
            case .notELF(let p): return "Falta o EBOOT.ELF descriptografado (\(p)). Configure em Arquivos do jogo."
            case .noUSRDIR(let p): return "Falta a pasta USRDIR (\(p)). Configure em Arquivos do jogo."
            case .symlink(let p): return "\(p) é um atalho (link simbólico) dentro da pasta do jogo: ponha o arquivo de verdade no lugar."
            case .badName(let p): return "Nome de arquivo não suportado no iPhone: \(p)"
            }
        }
    }

    /// EBOOT.ELF, USRDIR/** and movie_cache/** (if present), sorted; hidden files skipped.
    static func collect(elf: URL, usrdir: URL, movieCache: URL?) throws -> [Source] {
        guard LauncherCore.isELF(elf.path) else { throw Failure.notELF(elf.path) }
        guard LauncherCore.isDir(usrdir.path) else { throw Failure.noUSRDIR(usrdir.path) }
        var out = [Source(rel: "EBOOT.ELF", url: elf.resolvingSymlinksInPath())]
        out += try tree(usrdir.resolvingSymlinksInPath(), as: "USRDIR")
        if let mc = movieCache, LauncherCore.isDir(mc.path) {
            out += try tree(mc.resolvingSymlinksInPath(), as: "movie_cache")
        }
        return out.sorted { byteOrder($0.rel, $1.rel) }
    }

    static func safeComponent(_ s: String) -> Bool {
        !s.isEmpty && !s.hasPrefix(".") && !s.contains { "\n\r\t\\\0".contains($0) }
    }

    /// Path-based enumeration: relative paths come from the enumerator itself (URL
    /// enumeration standardizes /private/var to /var, which breaks prefix arithmetic),
    /// and its attributes are lstat's, so a symlink is seen as a symlink.
    private static func tree(_ root: URL, as top: String) throws -> [Source] {
        var out: [Source] = []
        guard let e = FileManager.default.enumerator(atPath: root.path) else { return [] }
        while let rel = e.nextObject() as? String {
            let type = e.fileAttributes?[.type] as? FileAttributeType
            if (rel as NSString).lastPathComponent.hasPrefix(".") {
                if type == .typeDirectory { e.skipDescendants() }
                continue
            }
            let full = top + "/" + rel
            if type == .typeSymbolicLink { throw Failure.symlink(full) }
            guard type == .typeRegular else { continue }
            guard full.split(separator: "/").allSatisfy({ safeComponent(String($0)) }) else { throw Failure.badName(full) }
            out.append(Source(rel: full, url: root.appendingPathComponent(rel)))
        }
        return out
    }
}

/// SHA-256 per file, cached by (size, mtime ns, ctime ns, inode) so 7 GB is hashed
/// once. The ctime is part of the key because a file replaced with the same size
/// and a restored mtime still gets a new ctime (nobody can set it back).
final class HashCache {
    struct Entry: Codable, Equatable {
        let size: Int64
        let mtimeNs: Int64
        let ctimeNs: Int64
        let inode: UInt64
        let sha256: String
    }

    let url: URL
    private var map: [String: Entry] = [:]
    private(set) var hashedBytes: Int64 = 0

    init(url: URL) {
        self.url = url
        if let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([String: Entry].self, from: d) { map = m }
    }

    static func fileInfo(_ u: URL) throws -> (size: Int64, mtimeNs: Int64, mtime: Int64, ctimeNs: Int64, inode: UInt64) {
        var st = stat()
        guard stat(u.path, &st) == 0 else { throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: u.path]) }
        let m = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
        let c = Int64(st.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(st.st_ctimespec.tv_nsec)
        return (Int64(st.st_size), m, Int64(st.st_mtimespec.tv_sec), c, UInt64(st.st_ino))
    }

    func sha256(of u: URL, onBytes: (Int64) -> Void = { _ in }) throws -> String {
        let i = try HashCache.fileInfo(u)
        if let e = map[u.path], e.size == i.size, e.mtimeNs == i.mtimeNs, e.ctimeNs == i.ctimeNs, e.inode == i.inode {
            onBytes(i.size)
            return e.sha256
        }
        guard let h = FileHandle(forReadingAtPath: u.path) else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: u.path])
        }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            hashedBytes += Int64(chunk.count)
            onBytes(Int64(chunk.count))
        }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        map[u.path] = Entry(size: i.size, mtimeNs: i.mtimeNs, ctimeNs: i.ctimeNs, inode: i.inode, sha256: hex)
        return hex
    }

    func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(map).write(to: url, options: .atomic)
    }
}

enum InstallManifestBuilder {
    static func build(_ sources: [InstallSources.Source], cache: HashCache,
                      progress: (_ done: Int64, _ total: Int64) -> Void = { _, _ in }) throws -> InstallManifest {
        var total: Int64 = 0
        for s in sources { total += try HashCache.fileInfo(s.url).size }
        var done: Int64 = 0
        var entries: [ManifestEntry] = []
        for s in sources {
            let i = try HashCache.fileInfo(s.url)
            let digest = try cache.sha256(of: s.url) { n in
                done += n
                progress(done, total)
            }
            entries.append(ManifestEntry(path: s.rel, size: i.size, mtime: i.mtime, ctimeNs: i.ctimeNs, sha256: digest, source: s.url))
        }
        try cache.save()
        return InstallManifest(entries: entries)
    }
}

/// What to do with each manifest file (Codex review 1/5). Size + mtime on the
/// phone are never enough on their own: a skip also needs the pushed-hash record
/// to name the same content; without it a small file is download-verified and a
/// large one is copied again.
enum InstallPlan {
    enum Step: Equatable { case skip, verify, copy }

    static func step(_ e: ManifestEntry, remote: RemoteFile?, pushed: PushedFile?, verifyLimit: Int64) -> Step {
        guard let r = remote, !r.isDirectory, r.size == e.size, r.mtime == e.mtime else { return .copy }
        if pushed == PushedFile(size: e.size, mtime: e.mtime, sha256: e.sha256) { return .skip }
        return e.size <= verifyLimit ? .verify : .copy
    }

    /// `remote`: `devicectl device info files --subdirectory Documents`.
    static func split(_ m: InstallManifest, remote: [RemoteFile], pushed: [String: PushedFile],
                      verifyLimit: Int64) -> (copy: [ManifestEntry], verify: [ManifestEntry], skip: [ManifestEntry]) {
        var byPath: [String: RemoteFile] = [:]
        for r in remote where !r.isDirectory { byPath[r.path] = r }
        var copy: [ManifestEntry] = [], verify: [ManifestEntry] = [], skip: [ManifestEntry] = []
        for e in m.entries {
            switch step(e, remote: byPath[e.path], pushed: pushed[e.path], verifyLimit: verifyLimit) {
            case .skip: skip.append(e)
            case .verify: verify.append(e)
            case .copy: copy.append(e)
            }
        }
        return (copy, verify, skip)
    }
}
