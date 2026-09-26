import Foundation
import CryptoKit

struct PushProgress: Equatable {
    var file = ""
    var index = 0
    var count = 0
    var doneBytes: Int64 = 0
    var totalBytes: Int64 = 0
}

enum PushOutcome: Equatable {
    case alreadyInstalled
    case installed(copied: Int, skipped: Int)
}

enum PushError: Error, Equatable {
    case cancelled
    case verifyFailed(String)
    case sourceChanged(String)
    var userMessage: String {
        switch self {
        case .cancelled:
            return "Cópia cancelada. Use Instalar no iPhone de novo para continuar de onde parou."
        case .verifyFailed(let p):
            return "\(p) não conferiu no iPhone depois da cópia (tamanho, data ou conteúdo diferente). Use Instalar de novo; até lá o iPhone mostra \"Jogo não instalado\"."
        case .sourceChanged(let p):
            return "\(p) mudou no Mac durante a cópia. Use Instalar de novo quando nada estiver mexendo nos arquivos do jogo."
        }
    }
}

/// The pushed-hash record: per path, what was copied and verified on this phone.
struct PushedRecord: Codable, Equatable {
    var files: [String: PushedFile] = [:]

    static func load(_ url: URL) -> PushedRecord {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(PushedRecord.self, from: $0) } ?? PushedRecord()
    }

    func save(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}

/// Copies the game into the app container so that the phone never sees a
/// complete manifest over data the Mac has not verified: marker first; per file
/// copy, then size+mtime on the phone, then (files <= verifyLimit) a download
/// hashed against the manifest, then the pushed-hash record; manifest last.
/// Files above verifyLimit are trusted to devicectl's transfer once their size
/// and mtime match and the Mac source is unchanged (ruling D3; hashing 6.5 GB
/// back over the cable would cost as much as copying it again).
final class DataPusher {
    static let defaultVerifyLimit: Int64 = 64 << 20

    let transport: DeviceTransport
    let device: String
    let bundle: String
    let staging: URL
    let recordURL: URL
    let verifyLimit: Int64

    init(transport: DeviceTransport, device: String, bundle: String, staging: URL, recordURL: URL,
         verifyLimit: Int64 = DataPusher.defaultVerifyLimit) {
        self.transport = transport
        self.device = device
        self.bundle = bundle
        self.staging = staging
        self.recordURL = recordURL
        self.verifyLimit = verifyLimit
    }

    func push(_ m: InstallManifest, progress: (PushProgress) -> Void = { _ in },
              cancelled: () -> Bool = { false }) throws -> PushOutcome {
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var record = PushedRecord.load(recordURL)
        let text = m.serialized()
        let plan = InstallPlan.split(m, remote: try remoteFiles("Documents"), pushed: record.files, verifyLimit: verifyLimit)
        if plan.copy.isEmpty, plan.verify.isEmpty, (try? remoteManifestText()) == text { return .alreadyInstalled }
        try upload(InstallManifest.incompleteMarker)            // the app reads "not installed" from here on
        var toCopy = plan.copy
        for e in plan.verify {                                  // on the phone already, no record: check the bytes
            if cancelled() { throw PushError.cancelled }
            if try downloadHash(e) == e.sha256 {
                record.files[e.path] = PushedFile(size: e.size, mtime: e.mtime, sha256: e.sha256)
                try record.save(recordURL)
            } else {
                toCopy.append(e)
            }
        }
        toCopy.sort { byteOrder($0.path, $1.path) }
        try ensureDirectories(for: toCopy)
        var p = PushProgress(count: toCopy.count, totalBytes: toCopy.reduce(Int64(0)) { $0 + $1.size })
        for (i, e) in toCopy.enumerated() {
            if cancelled() { throw PushError.cancelled }
            record.files[e.path] = nil                          // the phone's copy is about to change
            try record.save(recordURL)
            p.file = e.path
            p.index = i + 1
            progress(p)
            try transport.copyFileTo(device, bundle: bundle, local: e.source, remote: "Documents/" + e.path)
            try verifyCopied(e)
            record.files[e.path] = PushedFile(size: e.size, mtime: e.mtime, sha256: e.sha256)
            try record.save(recordURL)
            p.doneBytes += e.size
            progress(p)
        }
        // Final gate: every file matches on the phone AND in the record.
        let final = InstallPlan.split(m, remote: try remoteFiles("Documents"), pushed: record.files, verifyLimit: 0)
        if let bad = (final.copy + final.verify).first { throw PushError.verifyFailed(bad.path) }
        try upload(text)
        guard (try? remoteManifestText()) == text else { throw PushError.verifyFailed(InstallManifest.fileName) }
        return .installed(copied: toCopy.count, skipped: m.entries.count - toCopy.count)
    }

    private func remoteFiles(_ dir: String) throws -> [RemoteFile] {
        do { return try transport.files(device, bundle: bundle, under: dir) }
        catch let e as DeviceError where e.isNotFound { return [] }
    }

    /// Right after one copy: size + mtime on the phone, the Mac source unchanged,
    /// and for small files the downloaded bytes' hash.
    private func verifyCopied(_ e: ManifestEntry) throws {
        let parts = e.path.split(separator: "/")
        let dir = (["Documents"] + parts.dropLast().map(String.init)).joined(separator: "/")
        let name = String(parts.last!)
        guard let r = try remoteFiles(dir).first(where: { $0.path == name }), !r.isDirectory,
              r.size == e.size, r.mtime == e.mtime else { throw PushError.verifyFailed(e.path) }
        let now = try HashCache.fileInfo(e.source)
        guard now.size == e.size, now.mtime == e.mtime, now.ctimeNs == e.ctimeNs else { throw PushError.sourceChanged(e.path) }
        if e.size <= verifyLimit, try downloadHash(e) != e.sha256 { throw PushError.verifyFailed(e.path) }
    }

    private func downloadHash(_ e: ManifestEntry) throws -> String {
        let local = staging.appendingPathComponent("verify-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: local) }
        try transport.copyFileFrom(device, bundle: bundle, remote: "Documents/" + e.path, local: local)
        return SHA256.hash(data: try Data(contentsOf: local)).map { String(format: "%02x", $0) }.joined()
    }

    private func remoteManifestText() throws -> String {
        let local = staging.appendingPathComponent("remote-" + InstallManifest.fileName)
        try? FileManager.default.removeItem(at: local)
        try transport.copyFileFrom(device, bundle: bundle, remote: InstallManifest.remotePath, local: local)
        return try String(contentsOf: local, encoding: .utf8)
    }

    private func upload(_ text: String) throws {
        let local = staging.appendingPathComponent(InstallManifest.fileName)
        try text.write(to: local, atomically: true, encoding: .utf8)
        try transport.copyFileTo(device, bundle: bundle, local: local, remote: InstallManifest.remotePath)
    }

    /// An empty skeleton of every parent directory, copied without removing
    /// anything, so a single-file copy never depends on devicectl creating parents.
    private func ensureDirectories(for entries: [ManifestEntry]) throws {
        let fm = FileManager.default
        let skel = staging.appendingPathComponent("skeleton")
        try? fm.removeItem(at: skel)
        var tops = Set<String>()
        for e in entries {
            let parts = e.path.split(separator: "/")
            guard parts.count > 1 else { continue }
            tops.insert(String(parts[0]))
            try fm.createDirectory(at: skel.appendingPathComponent(parts.dropLast().joined(separator: "/")),
                                   withIntermediateDirectories: true)
        }
        for t in tops.sorted(by: byteOrder) {
            try transport.copyDirectoryTo(device, bundle: bundle, local: skel.appendingPathComponent(t),
                                          remote: "Documents/" + t, removeExisting: false)
        }
    }
}
