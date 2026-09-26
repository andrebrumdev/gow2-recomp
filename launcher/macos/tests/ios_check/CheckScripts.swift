import Foundation

func runScriptChecks() {
    let r = ScriptResult(status: 0, output: "building\nGOW2_IOS_APP=/old\nmore\nGOW2_IOS_APP=/x/GoW2.app\n")
    check(r.value("GOW2_IOS_APP") == "/x/GoW2.app", "the last value wins")
    check(r.value("NOPE") == nil, "absent key")
    check(ScriptResult(status: 1, output: "ERROR: Locked (com.apple.dt.CoreDeviceError error 10002 (0x2712))\n").deviceErrorCode == 10002,
          "device error code in script output")
    check(ScriptResult(status: 1, output: "ld: error").deviceErrorCode == nil, "no device error")

    let env = IOSScripts.environment(["PATH": "/usr/bin:/bin", "HOME": "/h"], isExecutable: { $0 == "/opt/homebrew/bin/python3" })
    check(env["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "GUI PATH gets Homebrew: \(env["PATH"] ?? "")")
    check(env["PY"] == "/opt/homebrew/bin/python3" && env["HOME"] == "/h"
          && env["DEVELOPER_DIR"] == "/Applications/Xcode.app/Contents/Developer", "env \(env)")
    let keep = IOSScripts.environment(["PATH": "/opt/homebrew/bin:/usr/bin", "PY": "/my/py", "DEVELOPER_DIR": "/X"],
                                      isExecutable: { _ in true })
    check(keep["PATH"] == "/opt/homebrew/bin:/usr/bin" && keep["PY"] == "/my/py" && keep["DEVELOPER_DIR"] == "/X",
          "caller values kept \(keep)")
    let bare = IOSScripts.environment([:], isExecutable: { _ in false })
    check(bare["PY"] == nil && bare["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "defaults \(bare)")

    let cfg = IOSScripts.config(ScriptResult(status: 0,
        output: "GOW2_IOS_TEAM=T\nGOW2_IOS_DEVICE=D\nGOW2_IOS_BUNDLE=com.t.g\nGOW2_IOS_APP=/a/GoW2.app\n"))
    check(cfg == IOSScripts.Config(team: "T", device: "D", bundle: "com.t.g", app: "/a/GoW2.app"), "config \(String(describing: cfg))")
    check(IOSScripts.config(ScriptResult(status: 1, output: "")) == nil, "failed print_config")
    check(IOSScripts.defaultBundle(team: "ABCDE12345") == "com.abcde12345.gow2recomp", "ios_env.sh's default bundle")

    let dir = tempDir("localenv")
    let f = LocalEnvFile(url: dir.appendingPathComponent("ios/local.env"))
    try! f.update(["GOW2_IOS_TEAM": "ABCDE12345"])
    check(f.read()["GOW2_IOS_TEAM"] == "ABCDE12345", "created")
    try! "# Copy to local.env\nGOW2_IOS_TEAM=OLD1234567          # personal team\nGOW2_WORK=/w\nGOW2_IOS_BUNDLE_ID=com.x.y\n"
        .write(to: f.url, atomically: true, encoding: .utf8)
    check(f.read() == ["GOW2_IOS_TEAM": "OLD1234567", "GOW2_WORK": "/w", "GOW2_IOS_BUNDLE_ID": "com.x.y"],
          "read ignores comments like bash does: \(f.read())")
    try! f.update(["GOW2_IOS_TEAM": "ABCDE12345", "GOW2_IOS_DEVICE": "00008110-TEST"])
    let text = try! String(contentsOf: f.url, encoding: .utf8)
    check(text == "# Copy to local.env\nGOW2_IOS_TEAM=ABCDE12345\nGOW2_WORK=/w\nGOW2_IOS_BUNDLE_ID=com.x.y\nGOW2_IOS_DEVICE=00008110-TEST\n",
          "updated in place, other lines kept:\n\(text)")
    do { try f.update(["GOW2_IOS_TEAM": "a b; rm -rf ~"]); check(false, "unsafe value must throw") }
    catch let e as LocalEnvError { check(e == .invalid(key: "GOW2_IOS_TEAM"), "\(e)") }
    catch { check(false, "\(error)") }
    check(!LocalEnvFile.valid("") && !LocalEnvFile.valid("$(x)") && !LocalEnvFile.valid("é")
          && LocalEnvFile.valid("com.example.gow2-1_a"), "valid()")
    let mode = (try! FileManager.default.attributesOfItem(atPath: f.url.path)[.posixPermissions] as! NSNumber).intValue
    check(mode == 0o600, "local.env mode 0600, got \(String(mode, radix: 8))")
    check(LocalEnvFile.at(repo: URL(fileURLWithPath: "/r")).url.path == "/r/ios/local.env", "location")
}
