import SwiftUI
import AppKit

/// Instalar no iPhone, Reassinar, validade e saves (P3). All state lives in
/// IOSBackend; this view only binds it.
struct IPhoneView: View {
    @EnvironmentObject var ios: IOSBackend

    private var badgeColor: Color {
        switch ios.badge {
        case .unknown: return Theme.C.ash
        case .ok: return Theme.C.gold
        case .soon, .expired: return Theme.C.bloodHi
        }
    }

    var body: some View {
        Form {
            ScreenHeader(title: "iPhone",
                         subtitle: "Instale o GoW2 no seu iPhone, reassine a cada 7 dias e leve os saves entre o Mac e o celular.")
            Section("Aparelho") {
                HStack {
                    Image(systemName: ios.deviceReady ? "checkmark.circle.fill" : "iphone.slash")
                        .foregroundStyle(ios.deviceReady ? Theme.C.laurel : Theme.C.amber)
                    Text(ios.deviceLine).font(Theme.F.body).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Procurar de novo") { Task { await ios.refresh() } }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(ios.busy != nil)
                }
            }
            Section("Assinatura") {
                Picker("Equipe (Apple ID)", selection: $ios.team) {
                    if !ios.teams.contains(where: { $0.id == ios.team }) {
                        Text(ios.team.isEmpty ? "Nenhuma — entre no Xcode com o seu Apple ID" : ios.team).tag(ios.team)
                    }
                    ForEach(ios.teams) { t in Text(t.free ? "\(t.name) — gratuita" : t.name).tag(t.id) }
                }
                .disabled(ios.busy != nil)
                TextField("Identificador do app", text: $ios.bundle).font(Theme.F.mono)
                    .disabled(ios.busy != nil)
                if let w = ios.bundleWarning {
                    Label(w, systemImage: "exclamationmark.triangle.fill").font(Theme.F.caption).foregroundStyle(Theme.C.amber)
                }
                HStack {
                    Image(systemName: "seal.fill").foregroundStyle(badgeColor)
                    Text(ios.badge.text + (ios.record.expiry.map { " (até \(IOSText.date($0)))" } ?? ""))
                        .font(Theme.F.body)
                }
                Text(Signing.freeTeamLimits).font(Theme.F.caption).foregroundStyle(Theme.C.ash)
            }
            Section("Instalação") {
                HStack(spacing: Theme.S.md) {
                    Button { Task { await ios.install() } } label: { Label("Instalar no iPhone", systemImage: "iphone.and.arrow.forward") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(ios.busy != nil)
                    Button { Task { await ios.resign() } } label: { Label("Reassinar", systemImage: "signature") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(ios.busy != nil || ios.installedBundle == nil)
                    Spacer()
                    if let op = ios.busy {
                        ProgressView().controlSize(.small)
                        Text(op.rawValue).font(Theme.F.caption).foregroundStyle(Theme.C.ash)
                    }
                    if ios.canCancel {
                        Button("Cancelar") { ios.cancel() }.buttonStyle(SecondaryButtonStyle(tint: Theme.C.blood))
                    }
                }
                if !ios.progress.isEmpty { Text(ios.progress).font(Theme.F.caption).foregroundStyle(Theme.C.parchment) }
                Text("Instalar compila o app, instala e copia o jogo (≈ 7 GB; pelo cabo leva minutos, pelo Wi-Fi bem mais). Se a cópia parar, use Instalar de novo: ela continua de onde parou e o iPhone mostra \"Jogo não instalado\" até terminar. Deixe o iPhone desbloqueado durante a cópia. Reassinar reinstala só o app: o jogo e os saves ficam.")
                    .font(Theme.F.caption).foregroundStyle(Theme.C.ash)
            }
            Section("Saves") {
                HStack(spacing: Theme.S.md) {
                    Button { Task { await ios.syncSaves(.both) } } label: { Label("Sincronizar saves", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Mac → iPhone") { Task { await ios.syncSaves(.macToPhone) } }.buttonStyle(SecondaryButtonStyle())
                    Button("iPhone → Mac") { Task { await ios.syncSaves(.phoneToMac) } }.buttonStyle(SecondaryButtonStyle())
                }
                .disabled(ios.busy != nil || ios.installedBundle == nil)
                if ios.deps.facts.copyFromNestsDirectory == nil {
                    Label("A sincronia de saves fica bloqueada até o fato F5 do devicectl ser medido (launcher/macos/ios_device_facts.json).",
                          systemImage: "lock.fill").font(Theme.F.caption).foregroundStyle(Theme.C.amber)
                }
                ForEach(ios.conflicts) { c in
                    VStack(alignment: .leading, spacing: Theme.S.xs) {
                        Label("Conflito em \(c.name): os dois lados mudaram desde a última sincronização.",
                              systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.C.amber)
                        Text("Mac: \(IOSText.date(Date(timeIntervalSince1970: TimeInterval(c.mac.newest)))) · iPhone: \(IOSText.date(Date(timeIntervalSince1970: TimeInterval(c.phone.newest))))")
                            .font(Theme.F.caption).foregroundStyle(Theme.C.ash)
                        HStack {
                            Button("Manter o do Mac") { Task { await ios.resolve(c.name, keep: .mac) } }.buttonStyle(SecondaryButtonStyle())
                            Button("Manter o do iPhone") { Task { await ios.resolve(c.name, keep: .iphone) } }.buttonStyle(SecondaryButtonStyle())
                        }
                        .disabled(ios.busy != nil)
                    }
                }
                HStack {
                    Text("Antes de substituir um lado, uma cópia dele vai para \(ios.backupRootPath). Feche o jogo no Mac e no iPhone antes de sincronizar.")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.ash)
                    Spacer()
                    Button("Mostrar backups") {
                        try? FileManager.default.createDirectory(atPath: ios.backupRootPath, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(URL(fileURLWithPath: ios.backupRootPath))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            if let e = ios.error {
                Section { Label(e, systemImage: "xmark.octagon.fill").foregroundStyle(Theme.C.bloodHi).textSelection(.enabled) }
            }
            if let r = ios.lastResult {
                Section { Label(r, systemImage: "checkmark.seal.fill").foregroundStyle(Theme.C.laurel) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.C.stone950)
        .task { await ios.refresh() }
    }
}
