import Foundation

/// devicectl stand-in: `root` is the app's data container (root/Documents/…).
/// Copies keep mtimes and a directory copy lands as the destination's contents
/// (facts F2/F3/F5); stricter than devicectl where that helps: a single-file
/// copy needs its parent directory to exist. A single-file copy onto a file with
/// the same size and mtime is a no-op, as on the phone (fact F4).
final class FakeTransport: DeviceTransport {
    let root: URL
    var deviceList: [IOSDevice] = []
    var lock = IOSLockState(passcodeRequired: false, unlockedSinceBoot: true)
    var installed: [IOSApp] = []
    var running: [String] = []
    /// Called with each op string before it runs; a non-nil error is thrown instead.
    var failWhen: ((String) -> DeviceError?)?
    /// Copies to a remote path with this prefix "succeed" without writing anything.
    var dropWritesUnder: String?
    /// The next N non-empty files written under `corruptPrefix` get their first byte flipped
    /// (same size, same mtime): a transfer that "succeeds" with wrong bytes.
    var corruptNext = 0
    var corruptPrefix = ""
    private(set) var ops: [String] = []

    init(root: URL) { self.root = root }

    func devices() throws -> [IOSDevice] { deviceList }
    func lockState(_ device: String) throws -> IOSLockState { lock }
    func apps(_ device: String) throws -> [IOSApp] { installed }
    func processes(_ device: String) throws -> [String] { running }
    func cancel() {}

    private func url(_ remote: String) -> URL { root.appendingPathComponent(remote) }
    private func notFound(_ p: String) -> DeviceError {
        DeviceError(code: DeviceError.notFound, domain: "fake", message: "Failed to retrieve the file node for \(p)")
    }
    private func op(_ s: String) throws {
        ops.append(s)
        if let e = failWhen?(s) { throw e }
    }
    private func dropped(_ remote: String) -> Bool { dropWritesUnder.map { remote.hasPrefix($0) } ?? false }

    func files(_ device: String, bundle: String, under dir: String) throws -> [RemoteFile] {
        let base = url(dir)
        guard LauncherCore.isDir(base.path) else { throw notFound(dir) }
        var out: [RemoteFile] = []
        let e = FileManager.default.enumerator(atPath: base.path)!
        while let rel = e.nextObject() as? String {
            let u = base.appendingPathComponent(rel)
            let i = try HashCache.fileInfo(u)
            out.append(RemoteFile(path: rel, size: i.size, mtime: i.mtime, isDirectory: LauncherCore.isDir(u.path)))
        }
        return out.sorted { $0.path < $1.path }
    }

    func copyFileTo(_ device: String, bundle: String, local: URL, remote: String) throws {
        try op("to \(remote)")
        if dropped(remote) { return }
        let dst = url(remote)
        guard LauncherCore.isDir(dst.deletingLastPathComponent().path) else { throw notFound(remote) }
        // Fact F4: devicectl skips a file the destination already holds with the
        // same size and mtime ("unchanged"), whatever the bytes are.
        if LauncherCore.isFile(dst.path), let d = try? HashCache.fileInfo(dst), let l = try? HashCache.fileInfo(local),
           d.size == l.size, d.mtime == l.mtime { return }
        try FakeTransport.place(local, at: dst)
        try corrupt(dst, remote: remote)
    }

    private func corrupt(_ dst: URL, remote: String) throws {
        guard corruptNext > 0, remote.hasPrefix(corruptPrefix) else { return }
        if LauncherCore.isDir(dst.path) {
            for name in try FileManager.default.contentsOfDirectory(atPath: dst.path).sorted() {
                try corrupt(dst.appendingPathComponent(name), remote: remote + "/" + name)
            }
            return
        }
        var d = try Data(contentsOf: dst)
        guard !d.isEmpty else { return }          // no byte to flip: an empty file is not counted
        corruptNext -= 1
        let m = try FileManager.default.attributesOfItem(atPath: dst.path)[.modificationDate] as! Date
        d[0] ^= 0xFF
        try d.write(to: dst)
        try FileManager.default.setAttributes([.modificationDate: m], ofItemAtPath: dst.path)
    }

    func copyDirectoryTo(_ device: String, bundle: String, local: URL, remote: String, removeExisting: Bool) throws {
        try op("dir to \(remote)" + (removeExisting ? " -r" : ""))
        if dropped(remote) { return }
        let dst = url(remote)
        if removeExisting { try? FileManager.default.removeItem(at: dst) }
        try FakeTransport.mirror(local, into: dst)
        try corrupt(dst, remote: remote)
    }

    func copyFileFrom(_ device: String, bundle: String, remote: String, local: URL) throws {
        try op("from \(remote)")
        let src = url(remote)
        guard LauncherCore.isFile(src.path) else { throw notFound(remote) }
        try FakeTransport.place(src, at: local)
    }

    func copyDirectoryFrom(_ device: String, bundle: String, remote: String, local: URL) throws {
        try op("dir from \(remote)")
        let src = url(remote)
        guard LauncherCore.isDir(src.path) else { throw notFound(remote) }
        try FakeTransport.mirror(src, into: local)
    }

    static func place(_ src: URL, at dst: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        try fm.copyItem(at: src, to: dst)
        let m = try fm.attributesOfItem(atPath: src.path)[.modificationDate] as! Date
        try fm.setAttributes([.modificationDate: m], ofItemAtPath: dst.path)
    }

    /// Merges `src`'s contents into `dst` (created), keeping mtimes.
    static func mirror(_ src: URL, into dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        for name in try fm.contentsOfDirectory(atPath: src.path) {
            let s = src.appendingPathComponent(name), d = dst.appendingPathComponent(name)
            if LauncherCore.isDir(s.path) { try mirror(s, into: d) } else { try place(s, at: d) }
        }
    }
}
