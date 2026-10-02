import Foundation

var checkFails = 0
func check(_ ok: Bool, _ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
    if !ok { checkFails += 1; print("FAIL \(file):\(line): \(message())") }
}
func tmp(_ tag: String) -> URL {
    let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("android_check-\(tag)-\(getpid())-\(UUID().uuidString.prefix(6))")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u.resolvingSymlinksInPath()
}

final class FakeRunner: ScriptRunning, @unchecked Sendable {
    var calls: [(script: String, args: [String])] = []
    var envs: [[String: String]] = []
    var status: (String, [String]) -> Int32 = { _, _ in 0 }
    func run(_ script: URL, _ args: [String], env: [String: String], log: URL) throws -> ScriptResult {
        calls.append((script.lastPathComponent, args)); envs.append(env)
        return ScriptResult(status: status(script.lastPathComponent, args), output: "")
    }
}

func runAndroidPureChecks() {
    // ---- adb devices -l ----
    let list = """
    * daemon not running; starting now at tcp:5037
    * daemon started successfully
    List of devices attached
    RX2X403ZPVJ            device usb:1-1 product:gts9fepwifi model:SM_X610 device:gts9fepwifi transport_id:1
    R58M12345              unauthorized usb:1-2 transport_id:2
    ABC                    offline
    XYZ                    no permissions (user in plugdev group; are your udev rules wrong?); see [x]

    """
    let d = AndroidText.parseDevices(list)
    check(d.count == 4, "4 devices, got \(d.count)")
    check(d[0] == AndroidDevice(serial: "RX2X403ZPVJ", state: "device", model: "SM X610"), "ready device: \(d[0])")
    check(d[1].state == "unauthorized" && d[1].model == "R58M12345", "unauthorized falls back to the serial as the model: \(d[1])")
    check(d[2].state == "offline", "offline")
    check(d[3].state == "no permissions", "no permissions: \(d[3].state)")
    check(AndroidText.parseDevices("List of devices attached\n\n").isEmpty, "no devices")
    check(AndroidText.ready(d)?.serial == "RX2X403ZPVJ", "ready() picks the first ready device")
    check(AndroidText.ready([d[1], d[2]]) == nil, "nothing ready")
    check(AndroidText.deviceLine(d).contains("pronto") && AndroidText.deviceLine(d).contains("mais de um"), "ready line + several devices")
    check(AndroidText.deviceLine([d[0]]).contains("SM X610 pronto para instalar"), "single ready device line")
    check(AndroidText.deviceLine([]).contains("Bloqueador automático"), "empty line names the Samsung Auto Blocker")
    check(AndroidText.deviceLine([d[1]]).contains("Permitir depuração USB"), "unauthorized line")
    check(AndroidText.deviceLine([d[2]]).contains("offline"), "offline line")
    check(AndroidText.deviceLine([d[3]]).contains("permissão"), "no permissions line")

    // ---- paths and environment ----
    let repo = URL(fileURLWithPath: "/w/gow2-recomp")
    check(AndroidScripts.engineRoot(repo: repo, env: [:]) { _ in false }.path == "/w/ps3recomp", "engine next to the port")
    check(AndroidScripts.engineRoot(repo: repo, env: [:]) { $0 == "/w/ps3recomp/tools/android/install_android.sh" }.path == "/w/ps3recomp", "main checkout has tools/android")
    check(AndroidScripts.engineRoot(repo: repo, env: [:]) { $0 == "/w/ps3recomp/.worktrees/android/tools/android/install_android.sh" }.path == "/w/ps3recomp/.worktrees/android", "android worktree until merged")
    check(AndroidScripts.engineRoot(repo: repo, env: ["PS3_ENGINE_ROOT": "/e"]).path == "/e", "PS3_ENGINE_ROOT wins")
    check(AndroidScripts.engineRoot(repo: repo, env: ["GOW2_ENGINE_ROOT": "/g", "PS3_ENGINE_ROOT": "/e"]).path == "/g", "GOW2_ENGINE_ROOT first")
    let eng = URL(fileURLWithPath: "/e")
    check(AndroidScripts.buildScript(repo: repo, engine: eng) { _ in false }.path == "/w/gow2-recomp/android/build_android.sh", "build script default")
    check(AndroidScripts.buildScript(repo: repo, engine: eng) { $0 == "/e/games/gow2/android/build_android.sh" }.path == "/e/games/gow2/android/build_android.sh", "build script via the engine's games/gow2")
    check(AndroidScripts.buildScript(repo: repo, engine: eng) { _ in true }.path == "/w/gow2-recomp/android/build_android.sh", "the port's own script wins")
    check(AndroidScripts.installScript(engine: URL(fileURLWithPath: "/e")).path == "/e/tools/android/install_android.sh", "install script")
    check(AndroidScripts.buildDir(engine: eng, env: [:]).path == "/e/build-android", "build dir next to the engine, not in the game folder")
    check(AndroidScripts.buildDir(engine: eng, env: ["GOW2_ANDROID_BUILD": "/b"]).path == "/b", "GOW2_ANDROID_BUILD wins")
    check(AndroidScripts.transportFile(engine: URL(fileURLWithPath: "/e"), env: [:]).path == "/e/tools/android/device_transport.env", "transport file default")
    let home = URL(fileURLWithPath: "/Users/u")
    let env = AndroidScripts.environment(["PATH": "/usr/bin:/bin"], repo: repo, engine: URL(fileURLWithPath: "/e"), home: home) { p in
        p == "/opt/homebrew/opt/openjdk@17/bin/javac" || p == "/opt/homebrew/bin/python3" }
    check(env["PATH"]?.hasPrefix("/opt/homebrew/opt/openjdk@17/bin:") == true, "JDK bin first in PATH: \(env["PATH"] ?? "")")
    check(env["PATH"]?.contains("/opt/homebrew/bin") == true && env["PATH"]?.hasSuffix("/usr/bin:/bin") == true, "Homebrew added, system PATH kept")
    check(env["JAVA_HOME"] == "/opt/homebrew/opt/openjdk@17" && env["PY"] == "/opt/homebrew/bin/python3", "JAVA_HOME and PY")
    check(env["GOW2_WORK"] == "/w/gow2-recomp" && env["PS3_ENGINE_ROOT"] == "/e" && env["GOW2_ANDROID_BUILD"] == "/e/build-android", "GOW2_WORK / PS3_ENGINE_ROOT / GOW2_ANDROID_BUILD")

    // ---- prerequisites ----
    let allOK = AndroidScripts.prerequisites(repo: repo, engine: URL(fileURLWithPath: "/e"), env: [:], home: home) { _ in true }
    check(allOK.count == 6 && allOK.allSatisfy { $0.ok }, "everything present -> all ok")
    let none = AndroidScripts.prerequisites(repo: repo, engine: URL(fileURLWithPath: "/e"), env: [:], home: home) { _ in false }
    check(none.allSatisfy { !$0.ok }, "nothing present -> none ok")
    check(none.first { $0.id == "ndk" }?.hint.contains("install_ndk.sh") == true, "NDK hint names install_ndk.sh")
    let noNdk = AndroidScripts.prerequisites(repo: repo, engine: URL(fileURLWithPath: "/e"), env: [:], home: home) { p in !p.contains("/ndk/") }
    check(noNdk.filter { !$0.ok }.map { $0.id } == ["ndk"], "only the NDK missing: \(noNdk.filter { !$0.ok }.map { $0.id })")
    check(AndroidScripts.sdkRoot(env: ["ANDROID_SDK_ROOT": "/s"], home: home) { $0 == "/s/platform-tools" } == "/s", "ANDROID_SDK_ROOT is used")
    check(AndroidScripts.sdkRoot(env: [:], home: home) { $0 == "/Users/u/Library/Android/sdk/platform-tools" } == "/Users/u/Library/Android/sdk", "~/Library/Android/sdk fallback")

    // ---- the install plan and each step's command line ----
    check(AndroidScripts.plan(transportProven: true, probeApkExists: true, data: false) == [.buildGame, .install(data: false)], "proven transport: build + install")
    check(AndroidScripts.plan(transportProven: false, probeApkExists: true, data: true) == [.bootstrap, .buildGame, .install(data: true)], "unproven transport: bootstrap first")
    check(AndroidScripts.plan(transportProven: false, probeApkExists: false, data: false) == [.buildProbe, .bootstrap, .buildGame, .install(data: false)], "no probe APK yet: build it first")
    let a1 = AndroidScripts.arguments(.install(data: true), serial: "S1", ownConfirmed: true)
    check(a1.script == "install" && a1.args == ["--serial", "S1", "--data", "--i-own-this-device"], "install args: \(a1.args)")
    check(AndroidScripts.arguments(.install(data: false), serial: "S1", ownConfirmed: false).args == ["--serial", "S1"], "install args without data and flag")
    check(AndroidScripts.arguments(.bootstrap, serial: "S1", ownConfirmed: true).args == ["--bootstrap", "--serial", "S1", "--i-own-this-device"], "bootstrap args")
    check(AndroidScripts.arguments(.buildProbe, serial: "S1", ownConfirmed: true).args == ["--probe-only"], "probe build args")
    check(AndroidScripts.arguments(.buildGame, serial: "S1", ownConfirmed: true).args.isEmpty, "game build has no args")
    let banned = ["--remove-existing-content"]
    let all = [AndroidStep.buildProbe, .bootstrap, .buildGame, .install(data: true), .install(data: false)]
        .flatMap { AndroidScripts.arguments($0, serial: "S", ownConfirmed: true).args }
    check(all.allSatisfy { a in !banned.contains(a) }, "no step can pass a destructive flag")

    // ---- ownership record and error messages ----
    check(AndroidScripts.ownershipRecorded(serial: "S1", home: home) { _ in "{\"device_serial\":\"S1\",\"x\":1}" }, "record with the serial")
    check(!AndroidScripts.ownershipRecorded(serial: "S2", home: home) { _ in "{\"device_serial\":\"S1\"}" }, "record for another serial")
    check(!AndroidScripts.ownershipRecorded(serial: "S1", home: home) { _ in nil }, "no record file")
    check(AndroidText.stepError(.install(data: false), status: 21, logPath: "~/l").contains("Nada foi instalado"), "21")
    check(AndroidText.stepError(.install(data: false), status: 30, logPath: "~/l").contains("nada foi alterado"), "30")
    check(AndroidText.stepError(.install(data: false), status: 31, logPath: "~/l").contains("desfeita"), "31")
    check(AndroidText.stepError(.install(data: false), status: 32, logPath: "~/l").contains("ATENÇÃO"), "32")
    check(AndroidText.stepError(.buildGame, status: 1, logPath: "~/l").contains("compilação"), "build failure")
}

@MainActor
func runAndroidBackendChecks() async {
    // a fake SDK whose adb prints the device list kept in devices.txt
    let sdk = tmp("sdk"), work = tmp("work"), home = tmp("home")
    try! FileManager.default.createDirectory(at: sdk.appendingPathComponent("platform-tools"), withIntermediateDirectories: true)
    let adb = sdk.appendingPathComponent("platform-tools/adb")
    try! Data("#!/bin/bash\ncat \"\(work.path)/devices.txt\"\n".utf8).write(to: adb)
    try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
    func devices(_ text: String) { try! Data(text.utf8).write(to: work.appendingPathComponent("devices.txt")) }
    let env = ["ANDROID_SDK_ROOT": sdk.path, "PS3_ENGINE_ROOT": "/e"]
    let repo = URL(fileURLWithPath: "/w/gow2-recomp")
    func wait(_ b: AndroidBackend, _ r: FakeRunner, calls: Int) async {
        for _ in 0..<200 { if b.busy == nil && r.calls.count >= calls { break }; try? await Task.sleep(nanoseconds: 25_000_000) }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    // no device: the screen says what to do, install stays disabled
    devices("List of devices attached\n\n")
    var runner = FakeRunner()
    var b = AndroidBackend(repo: repo, runner: runner, env: env, home: home) { _ in true }
    await b.refresh()
    check(!b.deviceReady && !b.canInstall && b.deviceLine.contains("Nenhum aparelho"), "no device: \(b.deviceLine)")
    b.requestInstall(data: false)
    check(!b.askOwnership && runner.calls.isEmpty, "install with no device asks nothing and runs nothing")

    // a ready tablet, first install: the ownership question comes first, then bootstrap + build + install
    devices("List of devices attached\nRX2X403ZPVJ device usb:1-1 model:SM_X610 transport_id:1\n")
    runner = FakeRunner()
    b = AndroidBackend(repo: repo, runner: runner, env: env, home: home) { p in !p.hasSuffix("device_transport.env") }
    await b.refresh()
    check(b.deviceReady && b.canInstall && b.device?.serial == "RX2X403ZPVJ", "ready device: \(b.deviceLine)")
    b.requestInstall(data: true)
    check(b.askOwnership && runner.calls.isEmpty, "first install asks ownership before running anything")
    b.askOwnership = false
    b.confirmOwnership()
    await wait(b, runner, calls: 3)
    check(runner.calls.map { $0.script } == ["install_android.sh", "build_android.sh", "install_android.sh"], "sequence: \(runner.calls.map { $0.script })")
    check(runner.calls.first?.args == ["--bootstrap", "--serial", "RX2X403ZPVJ", "--i-own-this-device"], "bootstrap args: \(runner.calls.first?.args ?? [])")
    check(runner.calls.last?.args == ["--serial", "RX2X403ZPVJ", "--data", "--i-own-this-device"], "install args: \(runner.calls.last?.args ?? [])")
    check(b.error == nil && b.lastResult?.contains("God of War II") == true && b.busy == nil, "success message: \(b.lastResult ?? "nil") / \(b.error ?? "")")
    check(runner.envs.allSatisfy { $0["GOW2_WORK"] == repo.path && $0["PS3_ENGINE_ROOT"] == "/e" }, "scripts get GOW2_WORK and PS3_ENGINE_ROOT")

    // ownership already recorded for the serial: no question, no flag
    let rec = home.appendingPathComponent("Library/Application Support/GoW2 Recomp/android_ownership.json")
    try! FileManager.default.createDirectory(at: rec.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data("{\"version\":1,\"entries\":[\n{\"device_serial\":\"RX2X403ZPVJ\"}\n]}".utf8).write(to: rec)
    runner = FakeRunner()
    b = AndroidBackend(repo: repo, runner: runner, env: env, home: home) { _ in true }
    await b.refresh()
    b.requestInstall(data: false)
    check(!b.askOwnership, "recorded ownership: no question")
    await wait(b, runner, calls: 2)
    check(runner.calls.map { $0.script } == ["build_android.sh", "install_android.sh"], "proven transport: build + install only: \(runner.calls.map { $0.script })")
    check(runner.calls.last?.args == ["--serial", "RX2X403ZPVJ"], "no ownership flag once recorded: \(runner.calls.last?.args ?? [])")

    // a failed install is reported with the rollback message and stops the sequence
    runner = FakeRunner()
    runner.status = { script, _ in script == "install_android.sh" ? 31 : 0 }
    b = AndroidBackend(repo: repo, runner: runner, env: env, home: home) { _ in true }
    await b.refresh()
    b.requestInstall(data: false)
    await wait(b, runner, calls: 2)
    check(b.error?.contains("desfeita") == true && b.lastResult == nil && b.busy == nil, "rollback message: \(b.error ?? "nil")")

    // a failed build never reaches the install
    runner = FakeRunner()
    runner.status = { script, _ in script == "build_android.sh" ? 1 : 0 }
    b = AndroidBackend(repo: repo, runner: runner, env: env, home: home) { _ in true }
    await b.refresh()
    b.requestInstall(data: false)
    await wait(b, runner, calls: 1)
    check(runner.calls.map { $0.script } == ["build_android.sh"] && b.error?.contains("compilação") == true, "failed build stops before the install: \(runner.calls.map { $0.script })")

    // missing prerequisites disable the install
    runner = FakeRunner()
    b = AndroidBackend(repo: repo, runner: runner, env: env, home: home) { p in !p.contains("/ndk/") }
    await b.refresh()
    check(b.deviceReady && b.missingPrereqs && !b.canInstall, "missing NDK: install disabled")
}
