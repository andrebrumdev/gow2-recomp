import SwiftUI
import AppKit

/// Instalar no Android: o app é gerado neste Mac a partir dos seus dados e instalado só no seu
/// aparelho, por USB. All state lives in AndroidBackend; this view only binds it.
struct AndroidView: View {
    @EnvironmentObject var android: AndroidBackend

    var body: some View {
        Form {
            ScreenHeader(title: "Android",
                         subtitle: "Compile o GoW2 neste Mac e instale no seu celular ou tablet Android por cabo USB.")
            Section("Aparelho") {
                HStack {
                    Image(systemName: android.deviceReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(android.deviceReady ? Theme.C.laurel : Theme.C.amber)
                    Text(android.deviceLine).font(Theme.F.body).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Procurar de novo") { Task { await android.refresh() } }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(android.busy != nil)
                }
            }
            Section("Requisitos deste Mac") {
                ForEach(android.prereqs) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: p.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(p.ok ? Theme.C.laurel : Theme.C.bloodHi)
                            Text(p.title).font(Theme.F.body)
                        }
                        if !p.ok { Text(p.hint).font(Theme.F.caption).foregroundStyle(Theme.C.amber) }
                    }
                }
            }
            Section("Instalação") {
                HStack(spacing: Theme.S.md) {
                    Button { android.requestInstall(data: false) } label: { Label("Instalar no Android", systemImage: "arrow.down.app") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!android.canInstall)
                    Button { android.requestInstall(data: true) } label: { Label("Instalar com o jogo", systemImage: "externaldrive.badge.plus") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!android.canInstall)
                    Spacer()
                    if let op = android.busy {
                        ProgressView().controlSize(.small)
                        Text(op.rawValue).font(Theme.F.caption).foregroundStyle(Theme.C.ash)
                    }
                }
                if !android.progress.isEmpty { Text(android.progress).font(Theme.F.caption).foregroundStyle(Theme.C.parchment) }
                if let r = android.lastResult { Label(r, systemImage: "checkmark.seal.fill").font(Theme.F.body).foregroundStyle(Theme.C.laurel) }
                if let e = android.error { Label(e, systemImage: "exclamationmark.triangle.fill").font(Theme.F.body).foregroundStyle(Theme.C.bloodHi) }
                Text("\"Instalar no Android\" compila o app e o instala. \"Instalar com o jogo\" também copia o jogo (≈ 7 GB; pelo cabo leva alguns minutos): deixe o aparelho desbloqueado durante a cópia. Antes de qualquer instalação os saves do aparelho são copiados para o Mac e conferidos; se algo falhar, o aparelho volta ao que era. O app contém código derivado do jogo: ele fica só no seu aparelho e nunca deve ser compartilhado.")
                    .font(Theme.F.caption).foregroundStyle(Theme.C.ash)
            }
        }
        .formStyle(.grouped)
        .task { await android.refresh() }
        .alert("Este aparelho é seu?", isPresented: $android.askOwnership) {
            Button("Sim, é meu aparelho") { android.confirmOwnership() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O app God of War II será gerado no seu Mac a partir dos seus arquivos do jogo e instalado somente em \(android.device?.model ?? "este aparelho"). Ele contém código derivado do jogo: não o copie, não o compartilhe e não instale em aparelhos de outras pessoas.")
        }
    }
}
