import Foundation

struct XcodeTeam: Equatable, Identifiable {
    let id: String            // team id (DEVELOPMENT_TEAM)
    let name: String
    let free: Bool
}

struct ProfileInfo: Equatable {
    let name: String
    let appID: String         // "<TEAM>.<bundle id>"
    let team: String
    let uuid: String
    let created: Date
    let expires: Date
}

struct RetiredProfile: Equatable {
    let original: URL
    let retired: URL
}

/// The Mac's re-sign badge: same rule as the phone's (whole days rounded up; red at 0-2).
enum ExpiryBadge: Equatable {
    case unknown, ok(days: Int), soon(days: Int), expired

    var urgent: Bool {
        switch self {
        case .soon, .expired: return true
        default: return false
        }
    }

    var text: String {
        switch self {
        case .unknown: return "Validade da assinatura desconhecida"
        case .ok(let d): return "Assinatura válida por mais \(d) dias"
        case .soon(let d): return d == 1 ? "Reassine hoje: falta 1 dia" : "Reassine logo: faltam \(d) dias"
        case .expired: return "Assinatura expirada — use Reassinar"
        }
    }
}

enum Signing {
    static let freeTeamLimits = "Conta gratuita da Apple (Personal Team): o app instalado vale 7 dias; depois disso o iPhone não abre o GoW2 até você usar Reassinar (o jogo e os saves continuam lá). No máximo 3 apps seus instalados ao mesmo tempo no aparelho, e até 10 identificadores de app novos por semana — por isso use sempre o mesmo identificador."

    static func teams(xcodePrefs data: Data) -> [XcodeTeam] {
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let byAccount = plist["IDEProvisioningTeamByIdentifier"] as? [String: Any] else { return [] }
        var seen = Set<String>()
        var out: [XcodeTeam] = []
        for key in byAccount.keys.sorted() {
            for t in (byAccount[key] as? [[String: Any]]) ?? [] {
                guard let id = t["teamID"] as? String, LocalEnvFile.valid(id), !seen.contains(id) else { continue }
                seen.insert(id)
                let free = (t["isFreeProvisioningTeam"] as? Bool) ?? ((t["isFreeProvisioningTeam"] as? Int) == 1)
                out.append(XcodeTeam(id: id, name: (t["teamName"] as? String) ?? id, free: free))
            }
        }
        return out
    }

    private static func stdout(_ tool: String, _ args: [String]) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: tool, code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\(tool) falhou"])
        }
        return data
    }

    static func readXcodePrefs() -> Data? { try? stdout("/usr/bin/defaults", ["export", "com.apple.dt.Xcode", "-"]) }

    /// The plist inside a .mobileprovision (a CMS blob).
    static func decodeProfile(_ url: URL) throws -> Data { try stdout("/usr/bin/security", ["cms", "-D", "-i", url.path]) }

    /// A developer-built app whose bundle is GoW2.app: the phone's current GoW2
    /// (keeping its bundle id keeps its data container and a free-team app slot).
    static func suggestedBundle(_ apps: [IOSApp]) -> String? {
        apps.filter { a in
            a.builtByDeveloper && (a.url.hasSuffix("/GoW2.app/") || a.url.hasSuffix("/GoW2.app"))
        }.map(\.bundleID).sorted().first
    }

    static func profile(plist data: Data) -> ProfileInfo? {
        guard let p = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let name = p["Name"] as? String, let uuid = p["UUID"] as? String,
              let team = (p["TeamIdentifier"] as? [String])?.first,
              let created = p["CreationDate"] as? Date, let expires = p["ExpirationDate"] as? Date,
              let appID = (p["Entitlements"] as? [String: Any])?["application-identifier"] as? String else { return nil }
        return ProfileInfo(name: name, appID: appID, team: team, uuid: uuid, created: created, expires: expires)
    }

    static func daysLeft(_ expiry: Date?, now: Date) -> Int {
        guard let e = expiry else { return -1 }
        let s = Int64(e.timeIntervalSince1970), n = Int64(now.timeIntervalSince1970)
        if s <= n { return 0 }
        return Int((s - n + 86399) / 86400)
    }

    static func badge(_ expiry: Date?, now: Date) -> ExpiryBadge {
        let d = daysLeft(expiry, now: now)
        if d < 0 { return .unknown }
        if d == 0 { return .expired }
        return d <= 2 ? .soon(days: d) : .ok(days: d)
    }

    static func profilesDir(home: URL) -> URL {
        home.appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles")
    }

    /// Moves (never deletes) the cached profiles of `appID` into `backup`.
    static func retireProfiles(appID: String, from dir: URL, to backup: URL,
                               reader: (URL) throws -> Data) throws -> [RetiredProfile] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        var moved: [RetiredProfile] = []
        for n in names.sorted() where n.hasSuffix(".mobileprovision") {
            let u = dir.appendingPathComponent(n)
            guard let info = (try? reader(u)).flatMap(profile(plist:)), info.appID == appID else { continue }
            try fm.createDirectory(at: backup, withIntermediateDirectories: true)
            let dst = backup.appendingPathComponent(n)
            try fm.moveItem(at: u, to: dst)
            moved.append(RetiredProfile(original: u, retired: dst))
        }
        return moved
    }

    static func restore(_ moved: [RetiredProfile]) {
        for m in moved where !FileManager.default.fileExists(atPath: m.original.path) {
            try? FileManager.default.moveItem(at: m.retired, to: m.original)
        }
    }
}
