import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SidebarItem: String, CaseIterable, Identifiable {
    case play = "Jogar"
    case files = "Arquivos do jogo"
    case graphics = "Gráficos"
    case audioControls = "Áudio e controles"
    case patches = "Patches"
    case mods = "Mods"
    case log = "Log"
    case about = "Sobre"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .play: return "play.circle.fill"
        case .files: return "externaldrive.fill"
        case .graphics: return "display"
        case .audioControls: return "gamecontroller.fill"
        case .patches: return "wand.and.stars"
        case .mods: return "puzzlepiece.extension.fill"
        case .log: return "doc.text.magnifyingglass"
        case .about: return "info.circle"
        }
    }
}

/// Sidebar selection. An ObservableObject instead of @State: the Command Line
/// Tools toolchain has no SwiftUI macro plugin, and @State is a macro in the
/// current SDK.
final class NavModel: ObservableObject {
    @Published var section: SidebarItem? = .play
}

struct ContentView: View {
    @EnvironmentObject var backend: Backend
    @StateObject private var nav = NavModel()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $nav.section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            Group {
                switch nav.section ?? .play {
                case .play: PlayView()
                case .files: FilesView()
                case .graphics: GraphicsView()
                case .audioControls: AudioControlsView()
                case .patches: PatchesView()
                case .mods: ModsView()
                case .log: LogView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task { await backend.refresh() }
    }
}

// MARK: - Play

struct PlayView: View {
    @EnvironmentObject var backend: Backend
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var patchStore: PatchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Hero()
                VStack(alignment: .leading, spacing: 18) {
                    if let err = backend.error {
                        Banner(text: err, color: .red, icon: "exclamationmark.triangle.fill")
                    }
                    if let st = backend.status {
                        StatusRow(ok: st.elf_ok, title: "EBOOT.ELF", detail: st.elf)
                        StatusRow(ok: st.vfs_ok, title: "Pasta USRDIR", detail: st.vfs_root)
                        StatusRow(ok: !st.binary.isEmpty, title: "Executável nativo",
                                  detail: st.binary.isEmpty ? "Compile com ./build_macos.sh recomp_macos_e435" : st.binary)
                        HStack(spacing: 12) {
                            if backend.running {
                                Button(role: .destructive) { backend.stop() } label: {
                                    Label("Parar", systemImage: "stop.fill").frame(minWidth: 140)
                                }
                                .controlSize(.large)
                                ProgressView().controlSize(.small)
                                Text("Rodando — o log fica em Log.").foregroundStyle(.secondary)
                            } else {
                                Button { backend.play(resume: false, settings: settings, patchFile: patchStore.writePatchFile()) } label: {
                                    Label("Jogar", systemImage: "play.fill").frame(minWidth: 140)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(!st.setup_ok || st.binary.isEmpty)
                                Button { backend.play(resume: true, settings: settings, patchFile: patchStore.writePatchFile()) } label: {
                                    Label("Continuar", systemImage: "clock.arrow.circlepath")
                                }
                                .controlSize(.large)
                                .disabled(!st.autosave || !st.setup_ok || st.binary.isEmpty)
                                .help(st.autosave ? "Retoma o último save automático" : "Nenhum autosave ainda")
                            }
                        }
                        if !st.setup_ok {
                            Text(st.message).foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView("Verificando arquivos…")
                        if let hint = backend.waitingHint {
                            Banner(text: hint, color: .orange, icon: "lock.shield")
                        }
                    }
                }
                .padding(28)
            }
        }
    }
}

struct Hero: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = Bundle.main.url(forResource: "hero", withExtension: "jpg"),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(height: 260).clipped()
            } else {
                Rectangle().fill(.black).frame(height: 260)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                .frame(height: 260)
            VStack(alignment: .leading, spacing: 4) {
                Text("God of War II HD").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                Text("Port nativo para Apple Silicon por recompilação estática")
                    .font(.headline).foregroundStyle(.white.opacity(0.85))
            }
            .padding(24)
        }
    }
}

struct StatusRow: View {
    let ok: Bool
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(ok ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail.isEmpty ? "—" : detail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }
}

struct Banner: View {
    let text: String
    let color: Color
    let icon: String
    var body: some View {
        Label(text, systemImage: icon)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(color)
    }
}

// MARK: - Files

struct FilesView: View {
    @EnvironmentObject var backend: Backend

    var body: some View {
        Form {
            Section {
                Text("Como no Dusk, o jogo não vem junto: aponte para a sua própria cópia de God of War II HD (NPUA80491). O EBOOT precisa estar descriptografado (RPCS3 → Utilities → Decrypt PS3 Binaries).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let st = backend.status {
                PathPicker(title: "EBOOT.ELF", path: st.elf, ok: st.elf_ok, directory: false) { url in
                    Task { await backend.setPaths(elf: url.path) }
                }
                PathPicker(title: "Pasta USRDIR", path: st.vfs_root, ok: st.vfs_ok, directory: true) { url in
                    Task { await backend.setPaths(usrdir: url.path) }
                }
                PathPicker(title: "Cache de vídeos (movie_cache)", path: st.movie_cache,
                           ok: st.movie_cache_ok, directory: true) { url in
                    Task { await backend.setPaths(movieCache: url.path) }
                }
                Section("Saves") {
                    HStack {
                        Text(st.savedata_root).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Mostrar no Finder") { backend.reveal(st.savedata_root) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PathPicker: View {
    let title: String
    let path: String
    let ok: Bool
    let directory: Bool
    let onPick: (URL) -> Void

    var body: some View {
        Section(title) {
            HStack {
                Image(systemName: ok ? "checkmark.circle.fill" : "questionmark.circle")
                    .foregroundStyle(ok ? .green : .orange)
                Text(path.isEmpty ? "Não definido" : path).font(.callout)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Escolher…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = !directory
                    panel.canChooseDirectories = directory
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url { onPick(url) }
                }
            }
        }
    }
}

// MARK: - Graphics / Audio

struct GraphicsView: View {
    @EnvironmentObject var settings: GameSettings
    var body: some View {
        Form {
            Section("Tela") {
                Toggle("Tela cheia ao abrir", isOn: $settings.fullscreen)
                Text("F11 ou Cmd+Enter alternam durante o jogo; Esc solta o mouse.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("VSync", isOn: $settings.vsync)
            }
            Section("Imagem") {
                Toggle("Upscale MetalFX (720p → resolução da tela)", isOn: $settings.metalFX)
                Toggle("HDR (EDR)", isOn: $settings.hdr)
                Toggle("Ritmo de quadros estável (fence por quadro)", isOn: $settings.frameFence)
                Text("O fence evita um triângulo gigante que pisca por um quadro, com um pequeno custo de fps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Avançado") {
                Text("Variáveis PS3_* extras, uma por linha (ex.: PS3_TRACE_FPS=1)")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $settings.extraEnv)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
            }
        }
        .formStyle(.grouped)
    }
}

struct AudioControlsView: View {
    @EnvironmentObject var settings: GameSettings
    private let keys: [(String, String)] = [
        ("Mover", "W A S D"), ("Câmera", "Mouse"), ("✕ / ○ / □ / △", "Espaço / E / J / K"),
        ("L1 / R1", "Shift esq. / Q"), ("L2 / R2", "Ctrl esq. / R"), ("L3 / R3", "F / G"),
        ("Start / Select", "Enter / Tab"), ("D-pad", "Setas"),
    ]
    var body: some View {
        Form {
            Section("Áudio") { Toggle("Som ligado", isOn: $settings.soundOn) }
            Section("Cutscenes") {
                Toggle("Pular cutscene com Start ou ✕", isOn: $settings.movieSkip)
                Toggle("Apertar Start automaticamente na intro", isOn: $settings.autostart)
            }
            Section("Controle") {
                Text("DualShock 4, DualSense, Xbox e MFi funcionam ao conectar, com vibração.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Teclado e mouse") {
                ForEach(keys, id: \.0) { k in
                    LabeledContent(k.0) { Text(k.1).font(.system(.body, design: .monospaced)) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Patches

struct PatchesView: View {
    @EnvironmentObject var backend: Backend
    @EnvironmentObject var store: PatchStore

    var body: some View {
        Form {
            Section {
                Text("Patches no formato do RPCS3 (patch.yml), escolhidos pelo hash do seu EBOOT como o RPCS3 faz. Patches de dados funcionam aqui; patches de código não têm efeito, porque o código já foi recompilado.")
                    .font(.callout).foregroundStyle(.secondary)
                if let p = store.progress {
                    ProgressView("Analisando o EBOOT…", value: p)
                } else if let h = store.ppuHash {
                    LabeledContent("Executável") { Text(h).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                }
                if let e = store.error { Banner(text: e, color: .red, icon: "exclamationmark.triangle.fill") }
                HStack {
                    Button("Importar patch.yml…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.yaml]
                        if panel.runModal() == .OK, let url = panel.url {
                            Task { await store.importFile(url, elf: backend.status?.elf ?? "") }
                        }
                    }
                    Button("Recarregar") { Task { await store.load(elf: backend.status?.elf ?? "") } }
                }
                Text("Fontes: " + (store.sources.isEmpty ? "nenhuma (instale o RPCS3 ou importe um patch.yml)" : store.sources.map(\.lastPathComponent).joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.patches.isEmpty, store.progress == nil {
                Section { Text("Nenhum patch para este executável.").foregroundStyle(.secondary) }
            }
            ForEach(store.patches) { patch in
                Section {
                    Toggle(isOn: Binding(get: { store.enabled.contains(patch.id) },
                                         set: { on in if on { store.enabled.insert(patch.id) } else { store.enabled.remove(patch.id) } })) {
                        HStack {
                            Text(patch.name).font(.headline)
                            Text(store.isCode(patch) ? "código · sem efeito" : "dados")
                                .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                .background((store.isCode(patch) ? Color.orange : Color.green).opacity(0.2), in: Capsule())
                        }
                    }
                    if !patch.author.isEmpty { LabeledContent("Autor", value: patch.author) }
                    ForEach(patch.configurables, id: \.name) { cfg in
                        if !cfg.options.isEmpty {
                            Picker(cfg.name, selection: Binding(
                                get: { store.values[patch.id + "/" + cfg.name] ?? cfg.defaultValue },
                                set: { store.values[patch.id + "/" + cfg.name] = $0 })) {
                                ForEach(cfg.options, id: \.1) { opt in Text(opt.0).tag(opt.1) }
                                if !cfg.options.contains(where: { $0.1 == cfg.defaultValue }) {
                                    Text("Padrão (\(cfg.defaultValue))").tag(cfg.defaultValue)
                                }
                            }
                        }
                    }
                    if !patch.notes.isEmpty {
                        Text(patch.notes).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task(id: backend.status?.elf) { await store.load(elf: backend.status?.elf ?? "") }
    }
}

// MARK: - Mods

struct ModsView: View {
    @EnvironmentObject var backend: Backend
    var body: some View {
        Form {
            Section {
                Text("Mods substituem arquivos da USRDIR. Importe um .zip; ele é copiado para a pasta de mods.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Importar .zip…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.zip]
                        if panel.runModal() == .OK, let url = panel.url {
                            Task { await backend.importMod(zip: url) }
                        }
                    }
                    Button("Abrir pasta de mods") { backend.reveal(backend.status?.mods_dir ?? "") }
                }
            }
            if let mods = backend.status?.mods, !mods.isEmpty {
                Section("Instalados") {
                    ForEach(mods) { mod in
                        Toggle(mod.name, isOn: Binding(
                            get: { mod.enabled },
                            set: { on in
                                var names = mods.filter { $0.enabled }.map(\.name)
                                if on { names.append(mod.name) } else { names.removeAll { $0 == mod.name } }
                                Task { await backend.setMods(enabled: names) }
                            }))
                    }
                }
            } else {
                Section { Text("Nenhum mod instalado.").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Log / About

struct LogView: View {
    @EnvironmentObject var backend: Backend
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(backend.logURL.path).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Atualizar") { backend.readLogTail() }
                Button("Abrir no Console") { NSWorkspace.shared.open(backend.logURL) }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(backend.logTail.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled).id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: backend.logTail.count) { _, n in
                    if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
                }
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .onAppear { backend.readLogTail() }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GoW2 Recomp").font(.largeTitle.bold())
            Text("God of War II HD recompilado estaticamente para macOS/arm64: o código PowerPC e SPU do jogo vira C/C++ nativo, rodando sobre uma reimplementação do sistema do PS3 com Metal, VideoToolbox e CoreAudio. Nenhum código ou arquivo do jogo é distribuído.")
                .fixedSize(horizontal: false, vertical: true)
            Link("Projeto no GitHub", destination: URL(string: "https://github.com/andrebrumdev/gow2-recomp")!)
            Text("God of War II © Sony Interactive Entertainment. Projeto sem afiliação com a Sony; é preciso ter o jogo. Motor ps3recomp sob licença MIT.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
    }
}
