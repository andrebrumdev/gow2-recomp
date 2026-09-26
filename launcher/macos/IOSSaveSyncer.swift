import Foundation

struct SaveSyncReport: Equatable {
    var pushed: [String] = []
    var pulled: [String] = []
    var same: [String] = []
    var conflicts: [SaveConflict] = []
    var missingSource: [String] = []   // forced direction, source lacks it: nothing copied, sides differ
    var recovered: [String] = []       // Mac saves put back from an interrupted swap
    var backups: [URL] = []
}

/// Runs a save sync: refuses while the game runs on either side (checked at the
/// start AND right before every destructive step), recovers an interrupted Mac
/// swap first, reads the phone's savedata, decides per directory
/// (SaveSyncPlan), backs up and verifies the side about to be replaced BEFORE
/// touching it, writes, verifies, and records the synced hash.
final class SaveSyncer {
    static let remoteRoot = "Documents/savedata"   // PS3_SAVEDATA_ROOT on iOS (P1 host)

    let transport: DeviceTransport
    let device: String
    let bundle: String
    let macRoot: URL
    let backupRoot: URL
    let stateURL: URL
    let staging: URL
    let facts: DeviceFacts
    let macGameRunning: () -> Bool
    let now: () -> Date
    /// FileManager.moveItem; a test seam for the swap's failure points.
    var moveItem: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    init(transport: DeviceTransport, device: String, bundle: String, macRoot: URL, backupRoot: URL, stateURL: URL,
         staging: URL, facts: DeviceFacts, macGameRunning: @escaping () -> Bool, now: @escaping () -> Date) {
        self.transport = transport
        self.device = device
        self.bundle = bundle
        self.macRoot = macRoot
        self.backupRoot = backupRoot
        self.stateURL = stateURL
        self.staging = staging
        self.facts = facts
        self.macGameRunning = macGameRunning
        self.now = now
    }

    func run(_ mode: SyncMode) throws -> SaveSyncReport {
        try guardNotRunning()
        var report = SaveSyncReport()
        let stamp = now()
        try recoverMacSwaps(stamp: stamp, report: &report)
        let phoneDir = try fetchPhone()
        defer { try? FileManager.default.removeItem(at: phoneDir) }
        let mac = try SaveSnapshot.take(macRoot), phone = try SaveSnapshot.take(phoneDir)
        var state = SyncState.load(stateURL)
        for action in SaveSyncPlan.decide(mac: mac, phone: phone, base: state.base, mode: mode) {
            switch action {
            case .same(let n):
                state.base[n] = mac[n]!.hash
                report.same.append(n)
            case .push(let n):
                try push(n, mac: mac[n]!, phone: phone[n], phoneDir: phoneDir, stamp: stamp, state: &state, report: &report)
                state.base[n] = mac[n]!.hash
                report.pushed.append(n)
            case .pull(let n):
                try pull(n, phone: phone[n]!, hadMac: mac[n] != nil, phoneDir: phoneDir, stamp: stamp, report: &report)
                state.base[n] = phone[n]!.hash
                report.pulled.append(n)
            case .conflict(let n):
                report.conflicts.append(SaveConflict(name: n, mac: mac[n]!, phone: phone[n]!))
            case .missingSource(let n):
                report.missingSource.append(n)
            }
            try state.save(stateURL)          // per directory: a later failure keeps what already succeeded
        }
        return report
    }

    /// The user's pick for a conflict: `keep` overwrites the other side (after its backup).
    func resolve(_ name: String, keep: SaveSide) throws -> SaveSyncReport {
        try guardNotRunning()
        var report = SaveSyncReport()
        let stamp = now()
        try recoverMacSwaps(stamp: stamp, report: &report)
        let phoneDir = try fetchPhone()
        defer { try? FileManager.default.removeItem(at: phoneDir) }
        let mac = try SaveSnapshot.take(macRoot), phone = try SaveSnapshot.take(phoneDir)
        var state = SyncState.load(stateURL)
        switch keep {
        case .mac:
            guard let m = mac[name] else { throw SaveSyncError.unknownSave(name) }
            try push(name, mac: m, phone: phone[name], phoneDir: phoneDir, stamp: stamp, state: &state, report: &report)
            state.base[name] = m.hash
            report.pushed.append(name)
        case .iphone:
            guard let p = phone[name] else { throw SaveSyncError.unknownSave(name) }
            try pull(name, phone: p, hadMac: mac[name] != nil, phoneDir: phoneDir, stamp: stamp, report: &report)
            state.base[name] = p.hash
            report.pulled.append(name)
        }
        try state.save(stateURL)
        return report
    }

    private func guardNotRunning() throws {
        if macGameRunning() { throw SaveSyncError.gameRunningMac }
        guard let app = try transport.apps(device).first(where: { $0.bundleID == bundle }) else {
            throw SaveSyncError.appNotInstalled
        }
        if IOSPolicy.appRunning(executables: try transport.processes(device), appURL: app.url) {
            throw SaveSyncError.gameRunningPhone
        }
    }

    /// An interrupted Mac swap leaves `.<name>.sync-old`. Target missing: put it back.
    /// Target present: the swap finished, keep the old copy among the backups. Never
    /// deleted. Stale `.sync-new` (a copy of phone data) is safe to drop.
    private func recoverMacSwaps(stamp: Date, report: inout SaveSyncReport) throws {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: macRoot.path) else { return }
        for item in names.sorted() where item.hasPrefix(".") {
            let url = macRoot.appendingPathComponent(item)
            if item.hasSuffix(".sync-new") { try? fm.removeItem(at: url); continue }
            guard item.hasSuffix(".sync-old") else { continue }
            let name = String(item.dropFirst().dropLast(".sync-old".count))
            let target = macRoot.appendingPathComponent(name)
            if !fm.fileExists(atPath: target.path) {
                try moveItem(url, target)
                report.recovered.append(name)
            } else {
                try keepAmongBackups(url, name: name, stamp: stamp, report: &report)
            }
        }
    }

    /// Moves `item` to <backupRoot>/<stamp>-mac-recovered[-N]/<name>: never deleted.
    private func keepAmongBackups(_ item: URL, name: String, stamp: Date, report: inout SaveSyncReport) throws {
        let fm = FileManager.default
        var folder = backupRoot.appendingPathComponent(SaveBackup.folderName(stamp, side: .mac) + "-recovered")
        var n = 2
        while fm.fileExists(atPath: folder.appendingPathComponent(name).path) {
            folder = backupRoot.appendingPathComponent(SaveBackup.folderName(stamp, side: .mac) + "-recovered-\(n)")
            n += 1
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try moveItem(item, folder.appendingPathComponent(name))
        report.backups.append(folder)
    }

    private func freshStaging(_ tag: String) throws -> URL {
        let d = staging.appendingPathComponent("\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// A local copy of the phone's savedata (empty when the phone never saved).
    private func fetchPhone() throws -> URL {
        let dir = try freshStaging("phone")
        do { _ = try transport.files(device, bundle: bundle, under: SaveSyncer.remoteRoot) }
        catch let e as DeviceError where e.isNotFound { return dir }
        try transport.copyDirectoryFrom(device, bundle: bundle, remote: SaveSyncer.remoteRoot, local: dir)
        return dir
    }

    private func phoneHash(_ remote: String) throws -> String? {
        let check = try freshStaging("verify")
        defer { try? FileManager.default.removeItem(at: check) }
        do { try transport.copyDirectoryFrom(device, bundle: bundle, remote: remote, local: check) }
        catch let e as DeviceError where e.isNotFound { return nil }
        do { return try SaveSnapshot.digest(check).hash }
        catch is SaveSyncError { return nil }             // empty/unreadable copy: not the expected save
    }

    private func push(_ n: String, mac: SaveDirSnapshot, phone: SaveDirSnapshot?, phoneDir: URL, stamp: Date,
                      state: inout SyncState, report: inout SaveSyncReport) throws {
        let exact = facts.removeExistingContentDeletesExtras == true          // F6
        var backup: URL?
        if phone != nil {
            if !exact {
                // Without F6 a copy only adds/overwrites: extra phone files would survive and
                // mix two saves. Refuse before touching the phone.
                let macFiles = Set(try SaveSnapshot.digest(macRoot.appendingPathComponent(n)).rows.map(\.rel))
                let phoneFiles = Set(try SaveSnapshot.digest(phoneDir.appendingPathComponent(n)).rows.map(\.rel))
                if !phoneFiles.isSubset(of: macFiles) { throw SaveSyncError.cannotReplaceExactly(n) }
            }
            let folder = try SaveBackup.write(dir: phoneDir.appendingPathComponent(n), name: n, into: backupRoot,
                                              folder: SaveBackup.folderName(stamp, side: .iphone))   // verified copy
            report.backups.append(folder)
            backup = folder.appendingPathComponent(n)
        }
        try guardNotRunning()                                                  // right before the destructive step
        let remote = SaveSyncer.remoteRoot + "/" + n
        // Forget the last-synced hash on disk BEFORE the phone is touched: a copy that stops
        // half-way (or a launcher that dies) must not leave base == Mac behind, or the next
        // bidirectional sync would pull the partial phone save over the Mac's. Without a base
        // a differing phone save is a conflict. The base comes back only when the phone
        // holds (or got back) its old save; the caller records the new one on success.
        let prior = state.base[n]
        state.base[n] = nil
        try state.save(stateURL)
        func phoneBackToOld(_ s: inout SyncState) {
            s.base[n] = prior
            try? s.save(stateURL)
        }
        do {
            try transport.copyDirectoryTo(device, bundle: bundle, local: macRoot.appendingPathComponent(n), remote: remote,
                                          removeExisting: exact)
        } catch {
            // The copy may have stopped half-way (cable, lock): if the phone no longer holds
            // its old save, put the verified backup back; then report the transport's error.
            if let b = backup, let old = phone {
                if (try? phoneHash(remote)) != old.hash {
                    try restorePhone(n, backup: b, old: old, remote: remote, exact: exact)
                }
                phoneBackToOld(&state)
            }
            throw error
        }
        if try phoneHash(remote) == mac.hash { return }
        // The phone copy is wrong: put the backed-up save back and say whether that conferred.
        guard let b = backup, let old = phone else { throw SaveSyncError.verifyFailed(n) }
        try restorePhone(n, backup: b, old: old, remote: remote, exact: exact)
        phoneBackToOld(&state)
        throw SaveSyncError.verifyFailed(n)
    }

    /// Copies the verified backup back to the phone; throws restoreFailed (naming the
    /// backup folder) unless the re-downloaded save matches the old one.
    private func restorePhone(_ n: String, backup b: URL, old: SaveDirSnapshot, remote: String, exact: Bool) throws {
        try? transport.copyDirectoryTo(device, bundle: bundle, local: b, remote: remote, removeExisting: exact)
        if (try? phoneHash(remote)) != old.hash { throw SaveSyncError.restoreFailed(n, b.path) }
    }

    /// Mac side: backup, stage + verify, then target -> .sync-old, staging -> target
    /// (restoring .sync-old if that fails), and only then drop .sync-old.
    private func pull(_ n: String, phone: SaveDirSnapshot, hadMac: Bool, phoneDir: URL, stamp: Date,
                      report: inout SaveSyncReport) throws {
        let fm = FileManager.default
        let target = macRoot.appendingPathComponent(n)
        if hadMac {
            report.backups.append(try SaveBackup.write(dir: target, name: n, into: backupRoot,
                                                       folder: SaveBackup.folderName(stamp, side: .mac)))
        }
        try fm.createDirectory(at: macRoot, withIntermediateDirectories: true)
        let fresh = macRoot.appendingPathComponent(".\(n).sync-new"), old = macRoot.appendingPathComponent(".\(n).sync-old")
        try? fm.removeItem(at: fresh)
        var swapped = false
        defer { if !swapped { try? fm.removeItem(at: fresh) } }               // staging = a copy of phone data
        try fm.copyItem(at: phoneDir.appendingPathComponent(n), to: fresh)
        guard try SaveSnapshot.digest(fresh).hash == phone.hash else { throw SaveSyncError.verifyFailed(n) }
        try guardNotRunning()                                                  // right before the destructive step
        let hadTarget = (try? fm.attributesOfItem(atPath: target.path)) != nil   // also a dangling link
        if hadTarget { try moveItem(target, old) }
        do {
            try moveItem(fresh, target)
            swapped = true
        } catch {
            if hadTarget, (try? fm.attributesOfItem(atPath: target.path)) == nil { try? moveItem(old, target) }
            throw error
        }
        guard hadTarget else { return }
        // The old save is backed up and verified (hadMac): drop it. Anything else that sat
        // there (not a save the snapshot saw) is kept among the backups, never deleted.
        if hadMac { try? fm.removeItem(at: old) } else { try keepAmongBackups(old, name: n, stamp: stamp, report: &report) }
    }
}
