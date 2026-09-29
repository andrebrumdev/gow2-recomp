import Foundation

/// One thing the iPhone build needs on this Mac, as the iPhone screen shows it.
struct Prereq: Equatable, Identifiable {
    let id: String
    let ok: Bool
    /// What to do, in pt-BR, when !ok; "" when ok.
    let message: String
}

/// The iPhone build's prerequisites, judged with the SAME environment the ios scripts
/// get (IOSScripts.environment): a Finder-launched app has no Homebrew on PATH, so a
/// check with the app's own PATH would call xcodegen missing although the build finds it.
enum IOSPrereqs {
    struct Probe {
        var isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
        var isDir: (String) -> Bool = { LauncherCore.isDir($0) }
        var isFile: (String) -> Bool = { LauncherCore.isFile($0) }
    }

    static let pythonNames = ["python3.14", "python3.13", "python3.12", "python3.11"]

    static func check(repo: URL, env: [String: String], probe: Probe = Probe()) -> [Prereq] {
        let dev = env["DEVELOPER_DIR"] ?? "/Applications/Xcode.app/Contents/Developer"
        let path = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        func onPath(_ tool: String) -> Bool { path.contains { probe.isExecutable("\($0)/\(tool)") } }
        func row(_ id: String, _ ok: Bool, _ text: String) -> Prereq { Prereq(id: id, ok: ok, message: ok ? "" : text) }

        var out: [Prereq] = []
        let xcode = probe.isExecutable("\(dev)/usr/bin/xcodebuild")
        out.append(row("xcode", xcode,
            "Falta o Xcode completo (App Store). Só as Command Line Tools não compilam para iPhone: instale o Xcode, abra-o uma vez e aceite a licença."))
        if xcode {
            out.append(row("ios-sdk", probe.isDir("\(dev)/Platforms/iPhoneOS.platform/Developer/SDKs"),
                "O Xcode está sem a plataforma iOS: abra o Xcode → Ajustes → Componentes e baixe o iOS."))
        }
        out.append(row("xcodegen", onPath("xcodegen"),
            "Falta o xcodegen: no Terminal, rode brew install xcodegen."))
        let py = env["PY"].map(probe.isExecutable) ?? pythonNames.contains(where: onPath)
        out.append(row("python", py,
            "Falta um Python 3.11 ou mais novo para as ferramentas de compilação: rode ./kit/setup.sh (ele compila um, se faltar)."))
        out.append(row("mac-build", probe.isFile(repo.appendingPathComponent("recomp_macos_e435/.spu_build_flags").path),
            "O jogo do Mac ainda não foi compilado nesta pasta: rode ./kit/setup.sh primeiro (o app do iPhone reaproveita essa compilação)."))
        return out
    }
}
