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
    var userMessage: String {
        switch self {
        case .cannotReplaceExactly(let n):
            return "O save \(n) do iPhone tem arquivos que o do Mac não tem, e o devicectl deste Mac não apaga arquivos a mais numa cópia (fato F6). Nada foi copiado."
        case .restoreFailed(let n, let backup):
            return "A cópia de \(n) para o iPhone não conferiu e a restauração automática também falhou. O save antigo do iPhone está guardado em \(backup): não apague essa pasta; tente Mac → iPhone de novo ou copie a pasta de volta com Finder → iPhone."
        case .gameRunningMac: return "O GoW2 está aberto no Mac. Feche o jogo e tente de novo."
        case .gameRunningPhone: return "O GoW2 está aberto no iPhone (mesmo em segundo plano). Feche-o no alternador de apps (deslize o app para cima) e tente de novo."
        case .appNotInstalled: return "O GoW2 não está instalado neste iPhone: use Instalar no iPhone."
        case .verifyFailed(let n): return "A cópia de \(n) não conferiu depois de gravada. Nada foi perdido (o lado substituído está na pasta de backups); tente de novo."
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

    /// Regular, non-hidden files under `dir`, sorted by path.
    static func digest(_ dir: URL) throws -> Digest {
        var rows: [Row] = []
        var newest: Int64 = 0
        if let e = FileManager.default.enumerator(atPath: dir.path) {
            while let rel = e.nextObject() as? String {
                let type = e.fileAttributes?[.type] as? FileAttributeType
                if (rel as NSString).lastPathComponent.hasPrefix(".") {
                    if type == .typeDirectory { e.skipDescendants() }
                    continue
                }
                guard type == .typeRegular else { continue }
                let u = dir.appendingPathComponent(rel)
                let data = try Data(contentsOf: u)
                rows.append(Row(rel: rel, size: Int64(data.count), sha: hex(data)))
                newest = max(newest, try HashCache.fileInfo(u).mtime)
            }
        }
        rows.sort { $0.rel < $1.rel }
        let text = rows.map { "\($0.rel)\t\($0.size)\t\($0.sha)\n" }.joined()
        return Digest(hash: hex(Data(text.utf8)), newest: newest, rows: rows)
    }

    /// GoW2's save directories under a savedata root (missing root = none).
    static func take(_ root: URL) throws -> [String: SaveDirSnapshot] {
        guard LauncherCore.isDir(root.path) else { return [:] }
        var out: [String: SaveDirSnapshot] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() where name.hasPrefix(titlePrefix) {
            let d = root.appendingPathComponent(name)
            guard LauncherCore.isDir(d.path) else { continue }
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
        var target = root.appendingPathComponent(folder)
        var n = 2
        while fm.fileExists(atPath: target.appendingPathComponent(name).path) {
            target = root.appendingPathComponent("\(folder)-\(n)")
            n += 1
        }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let copy = target.appendingPathComponent(name)
        try fm.copyItem(at: dir, to: copy)
        let src = try SaveSnapshot.digest(dir)
        guard try SaveSnapshot.digest(copy).hash == src.hash else { throw SaveSyncError.verifyFailed(name) }
        let list = target.appendingPathComponent("sha256.txt")
        let old = (try? String(contentsOf: list, encoding: .utf8)) ?? ""
        try (old + src.rows.map { "\($0.sha)  \(name)/\($0.rel)\n" }.joined()).write(to: list, atomically: true, encoding: .utf8)
        return target
    }
}
