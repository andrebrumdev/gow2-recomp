import Foundation

func runPrereqChecks() {
    let repo = URL(fileURLWithPath: "/k/gow2-recomp")
    let dev = "/Applications/Xcode.app/Contents/Developer"
    var exe: Set<String> = ["\(dev)/usr/bin/xcodebuild", "/opt/homebrew/bin/xcodegen", "/k/py"]
    var dirs: Set<String> = ["\(dev)/Platforms/iPhoneOS.platform/Developer/SDKs"]
    var files: Set<String> = ["/k/gow2-recomp/recomp_macos_e435/.spu_build_flags"]
    func probe() -> IOSPrereqs.Probe {
        let e = exe, d = dirs, f = files
        return IOSPrereqs.Probe(isExecutable: { e.contains($0) }, isDir: { d.contains($0) }, isFile: { f.contains($0) })
    }
    let env = ["PATH": "/opt/homebrew/bin:/usr/bin:/bin", "PY": "/k/py", "DEVELOPER_DIR": dev]
    func failing(_ e: [String: String]) -> [String] { IOSPrereqs.check(repo: repo, env: e, probe: probe()).filter { !$0.ok }.map(\.id) }

    let all = IOSPrereqs.check(repo: repo, env: env, probe: probe())
    check(all.allSatisfy(\.ok) && all.map(\.id) == ["xcode", "ios-sdk", "xcodegen", "python", "mac-build"]
          && all.allSatisfy { $0.message.isEmpty }, "everything present: \(all)")

    exe.remove("\(dev)/usr/bin/xcodebuild")
    let noXcode = IOSPrereqs.check(repo: repo, env: env, probe: probe())
    check(noXcode.map(\.id) == ["xcode", "xcodegen", "python", "mac-build"] && failing(env) == ["xcode"],
          "no Xcode: one row, no SDK row: \(noXcode)")
    check(noXcode[0].message.contains("Xcode completo") && noXcode[0].message.contains("App Store"), "Xcode text: \(noXcode[0].message)")
    exe.insert("\(dev)/usr/bin/xcodebuild")

    dirs.removeAll()
    let noSDK = IOSPrereqs.check(repo: repo, env: env, probe: probe()).first { !$0.ok }
    check(noSDK?.id == "ios-sdk" && noSDK?.message.contains("Componentes") == true, "no iOS platform: \(String(describing: noSDK))")
    dirs.insert("\(dev)/Platforms/iPhoneOS.platform/Developer/SDKs")

    // Finder PATH: judged with the environment the scripts get (Review Focus 4).
    let finder = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "PY": "/k/py", "DEVELOPER_DIR": dev]
    check(failing(finder) == ["xcodegen"], "raw Finder PATH does not see Homebrew's xcodegen: \(failing(finder))")
    let scriptsEnv = IOSScripts.environment(finder, isExecutable: { _ in false })
    check(failing(scriptsEnv) == [], "Finder PATH: same env as the scripts finds it: \(failing(scriptsEnv))")
    exe.remove("/opt/homebrew/bin/xcodegen")
    let noGen = IOSPrereqs.check(repo: repo, env: env, probe: probe()).first { !$0.ok }
    check(noGen?.id == "xcodegen" && noGen?.message.contains("brew install xcodegen") == true, "xcodegen text: \(String(describing: noGen))")
    exe.insert("/opt/homebrew/bin/xcodegen")

    var noPY = env
    noPY["PY"] = nil
    check(failing(noPY) == ["python"], "no PY and no python3.11+ on PATH: \(failing(noPY))")
    let pyText = IOSPrereqs.check(repo: repo, env: noPY, probe: probe()).first { !$0.ok }?.message ?? ""
    check(pyText.contains("3.11") && pyText.contains("./kit/setup.sh"), "python text: \(pyText)")
    exe.insert("/opt/homebrew/bin/python3.12")
    check(failing(noPY) == [], "a python3.12 on PATH is enough")
    exe.remove("/opt/homebrew/bin/python3.12")
    var badPY = env
    badPY["PY"] = "/nope/python3"
    check(failing(badPY) == ["python"], "a PY that is not executable is missing")

    files.removeAll()
    let noBuild = IOSPrereqs.check(repo: repo, env: env, probe: probe()).first { !$0.ok }
    check(noBuild?.id == "mac-build" && noBuild?.message.contains("./kit/setup.sh") == true, "no Mac build: \(String(describing: noBuild))")
}
