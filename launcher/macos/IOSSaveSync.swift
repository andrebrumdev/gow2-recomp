import Foundation
import CryptoKit

// Save sync Mac <-> iPhone (P3, controller rulings 1-5). The unit is a whole
// PS3 save directory (BCUS98229_GOW2): MASTER.BIN and PARAM.SFO index the
// DATAxx files and are rewritten with them, so files are never mixed.

enum SaveSide: String, Equatable { case mac, iphone }
enum SyncMode: Equatable { case both, macToPhone, phoneToMac }
/// `missingSource`: a forced direction whose source side lacks the save; nothing
/// is copied and the sides stay different (reported, never shown as success).
enum SaveAction: Equatable { case same(String), push(String), pull(String), conflict(String), missingSource(String) }

struct SaveDirSnapshot: Equatable {
    let name: String
    let hash: String          // content only (paths, sizes, SHA-256): mtimes do not count
    let newest: Int64         // newest file mtime, shown to the user
    let files: Int
}

struct SaveConflict: Equatable, Identifiable {
    let name: String
    let mac: SaveDirSnapshot
    let phone: SaveDirSnapshot
    var id: String { name }
}

enum SaveSyncError: Error, Equatable {
    case gameRunningMac, gameRunningPhone, appNotInstalled, verifyFailed(String), unknownSave(String)
    case cannotReplaceExactly(String), restoreFailed(String, String)
    /// The snapshot fails closed: a save it cannot read completely (or an empty one)
    /// and a save holding a symbolic link are errors, never a smaller snapshot.
    case unreadableSave(String), symlinkInSave(String)
    /// A phone copy that did not verify, rolled back: the phone holds its old save again
    /// (re-downloaded and hash-checked). verifyFailed = nothing existing was replaced.
    case phoneRestored(String)
    /// The phone listed a savedata that did not come back complete on the copy: never read
    /// as "the phone has no save" (CoreDeviceError 7000 is ambiguous, incident fix 2).
    case phoneUnreadable
    /// A push with no phone save (hence no backup) found one there right before the copy.
    case phoneSaveAppeared(String)
    var userMessage: String {
        switch self {
        case .phoneUnreadable:
            return "Não deu para ler os saves do iPhone (o devicectl listou a pasta, mas a cópia veio incompleta). Nada foi copiado. Conecte o iPhone pelo cabo USB, desbloqueie-o e tente de novo."
        case .phoneSaveAppeared(let n):
            return "Apareceu um save \(n) no iPhone durante a sincronia. Nada foi copiado por cima dele; sincronize de novo."
        case .unreadableSave(let n):
            return "Não deu para ler todo o save \(n) (pasta vazia, sem permissão ou com algo que não é arquivo). Nada foi copiado; confira a pasta e tente de novo."
        case .symlinkInSave(let n):
            return "O save \(n) é ou contém um link simbólico. Nada foi copiado: troque o link pelos arquivos de verdade e tente de novo."
        case .cannotReplaceExactly(let n):
            return "O save \(n) do iPhone tem arquivos que o do Mac não tem, e o devicectl deste Mac não apaga arquivos a mais numa cópia (fato F6). Nada foi copiado."
        case .restoreFailed(let n, let backup):
            return "A cópia de \(n) para o iPhone não conferiu e a restauração automática também falhou. O save antigo do iPhone está guardado em \(backup): não apague essa pasta; tente Mac → iPhone de novo ou copie a pasta de volta com Finder → iPhone."
        case .gameRunningMac: return "O GoW2 está aberto no Mac. Feche o jogo e tente de novo."
        case .gameRunningPhone: return "O GoW2 está aberto no iPhone (mesmo em segundo plano). Feche-o no alternador de apps (deslize o app para cima) e tente de novo."
        case .appNotInstalled: return "O GoW2 não está instalado neste iPhone: use Instalar no iPhone."
        case .verifyFailed(let n): return "A cópia de \(n) não conferiu depois de gravada. Nenhum save existente foi substituído (o do Mac está intacto); tente de novo."
        case .phoneRestored(let n): return "A cópia de \(n) para o iPhone não conferiu depois de gravada. O save anterior do iPhone foi restaurado e conferido (e há uma cópia dele na pasta de backups): nada foi perdido; tente de novo."
        case .unknownSave(let n): return "O save \(n) não existe mais nesse lado. Sincronize de novo."
        }
    }
}

/// Last-synced content hash per save directory (per device + bundle, on the Mac).
struct SyncState: Codable, Equatable {
    var version = 1
    var base: [String: String] = [:]

    static func load(_ url: URL) -> SyncState {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SyncState.self, from: $0) } ?? SyncState()
    }

    func save(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}

enum SaveSnapshot {
    static let titlePrefix = "BCUS98229"

    struct Row: Equatable {
        let rel: String
        let size: Int64
        let sha: String
    }

    struct Digest: Equatable {
        let hash: String
        let newest: Int64
        let rows: [Row]
    }

    static func hex(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    /// Regular, non-hidden files under `dir`, sorted by path. Fails closed (spec:
    /// never lose a save): `dir` or anything inside it being a symbolic link, an
    /// enumeration error (unreadable folder), an entry that is neither a regular
    /// file nor a folder, or no file at all throws instead of returning a smaller
    /// snapshot. Links are never followed (checked on the link itself).
    static func digest(_ dir: URL) throws -> Digest {
        let fm = FileManager.default
        let name = dir.lastPathComponent
        let top = (try? fm.attributesOfItem(atPath: dir.path)[.type]) as? FileAttributeType
        if top == .typeSymbolicLink { throw SaveSyncError.symlinkInSave(name) }
        guard top == .typeDirectory else { throw SaveSyncError.unreadableSave(name) }
        var failed = false
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: keys,
                                    options: [.skipsHiddenFiles, .producesRelativePathURLs],
                                    errorHandler: { _, _ in failed = true; return false })
        else { throw SaveSyncError.unreadableSave(name) }
        var rows: [Row] = []
        var newest: Int64 = 0
        while let u = e.nextObject() as? URL {
            let v = try u.resourceValues(forKeys: Set(keys))
            if v.isSymbolicLink == true { throw SaveSyncError.symlinkInSave(name) }
            if v.isDirectory == true { continue }
            guard v.isRegularFile == true else { throw SaveSyncError.unreadableSave(name) }
            let data = try Data(contentsOf: u)
            rows.append(Row(rel: u.relativePath, size: Int64(data.count), sha: hex(data)))
            newest = max(newest, try HashCache.fileInfo(u).mtime)
        }
        if failed || rows.isEmpty { throw SaveSyncError.unreadableSave(name) }
        rows.sort { $0.rel < $1.rel }
        let text = rows.map { "\($0.rel)\t\($0.size)\t\($0.sha)\n" }.joined()
        return Digest(hash: hex(Data(text.utf8)), newest: newest, rows: rows)
    }

    /// GoW2's save directories under a savedata root (missing root = none).
    /// A `BCUS98229*` entry that is a folder or a symbolic link is a save and
    /// must digest cleanly (a link throws); a plain file of that name is ignored.
    static func take(_ root: URL) throws -> [String: SaveDirSnapshot] {
        guard LauncherCore.isDir(root.path) else { return [:] }
        let fm = FileManager.default
        var out: [String: SaveDirSnapshot] = [:]
        for name in try fm.contentsOfDirectory(atPath: root.path).sorted() where name.hasPrefix(titlePrefix) {
            let d = root.appendingPathComponent(name)
            let type = try fm.attributesOfItem(atPath: d.path)[.type] as? FileAttributeType
            guard type == .typeDirectory || type == .typeSymbolicLink else { continue }
            let g = try digest(d)
            out[name] = SaveDirSnapshot(name: name, hash: g.hash, newest: g.newest, files: g.rows.count)
        }
        return out
    }
}

enum SaveSyncPlan {
    static func decide(mac: [String: SaveDirSnapshot], phone: [String: SaveDirSnapshot],
                       base: [String: String], mode: SyncMode) -> [SaveAction] {
        var out: [SaveAction] = []
        for name in Set(mac.keys).union(phone.keys).sorted() {
            let m = mac[name], p = phone[name]
            if let m = m, let p = p, m.hash == p.hash {
                out.append(.same(name))
                continue
            }
            switch mode {
            case .macToPhone:
                out.append(m != nil ? .push(name) : .missingSource(name))
            case .phoneToMac:
                out.append(p != nil ? .pull(name) : .missingSource(name))
            case .both:
                guard let m = m else { out.append(.pull(name)); continue }
                guard let p = p else { out.append(.push(name)); continue }
                let b = base[name]
                if b == m.hash { out.append(.pull(name)) }
                else if b == p.hash { out.append(.push(name)) }
                else { out.append(.conflict(name)) }
            }
        }
        return out
    }
}

enum SaveBackup {
    /// The user's dated backups folder when present, else ~/Documents/GoW2 Saves.
    static func defaultRoot(home: URL, isDir: (String) -> Bool = LauncherCore.isDir) -> URL {
        let personal = home.appendingPathComponent("Documents/PESSOAL/gow2-saves")
        return isDir(personal.path) ? personal : home.appendingPathComponent("Documents/GoW2 Saves")
    }

    static func folderName(_ d: Date, side: SaveSide, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return "\(f.string(from: d))-\(side.rawValue)"
    }

    /// Copies `dir` to <root>/<folder>[-N]/<name>, verifies the copy, appends
    /// "<sha>  <name>/<file>" lines to <folder>/sha256.txt. Returns the folder.
    static func write(dir: URL, name: String, into root: URL, folder: String) throws -> URL {
        let fm = FileManager.default
        let src = try SaveSnapshot.digest(dir)   // refuses links/unreadable saves before creating anything
        var target = root.appendingPathComponent(folder)
        var n = 2
        while fm.fileExists(atPath: target.appendingPathComponent(name).path) {
            target = root.appendingPathComponent("\(folder)-\(n)")
            n += 1
        }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let copy = target.appendingPathComponent(name)
        try fm.copyItem(at: dir, to: copy)
        guard try SaveSnapshot.digest(copy).hash == src.hash else { throw SaveSyncError.verifyFailed(name) }
        let list = target.appendingPathComponent("sha256.txt")
        let old = (try? String(contentsOf: list, encoding: .utf8)) ?? ""
        try (old + src.rows.map { "\($0.sha)  \(name)/\($0.rel)\n" }.joined()).write(to: list, atomically: true, encoding: .utf8)
        return target
    }
}
