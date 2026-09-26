import Foundation

let fxDevices = #"""
{"info":{"outcome":"success","jsonVersion":5},"result":{"devices":[
 {"identifier":"SIM-1","connectionProperties":{"pairingState":"paired","transportType":"sameMachine","tunnelState":"disconnected"},
  "deviceProperties":{"bootState":"shutdown","name":"iPhone 18 Pro","osVersionNumber":"27.0"},
  "hardwareProperties":{"marketingName":"iPhone 18 Pro","platform":"iOS","reality":"simulated","udid":"SIM-UDID"}},
 {"identifier":"CORE-1","connectionProperties":{"pairingState":"paired","transportType":"localNetwork","tunnelState":"connected"},
  "deviceProperties":{"bootState":"booted","developerModeStatus":"enabled","name":"iPhone Teste","osVersionNumber":"26.6"},
  "hardwareProperties":{"marketingName":"iPhone 14","platform":"iOS","reality":"physical","udid":"00008110-TEST"}}]}}
"""#
let fxLock = #"{"info":{"outcome":"success"},"result":{"deviceIdentifier":"CORE-1","passcodeRequired":true,"unlockedSinceBoot":true}}"#
let fxApps = #"""
{"info":{"outcome":"success"},"result":{"apps":[{"appClip":false,"builtByDeveloper":true,"bundleIdentifier":"com.example.gow2",
 "bundleVersion":"1","name":"God of War II","removable":true,
 "url":"file:///private/var/containers/Bundle/Application/9E07BD20-0000/GoW2.app/","version":"1.0"}]}}
"""#
let fxProcs = #"""
{"info":{"outcome":"success"},"result":{"runningProcesses":[{"executable":"file:///sbin/launchd","processIdentifier":1},
 {"executable":"file:///private/var/containers/Bundle/Application/9E07BD20-0000/GoW2.app/GoW2","processIdentifier":812}]}}
"""#
let fxFiles = #"""
{"info":{"outcome":"success"},"result":{"files":[
 {"metadata":{"lastModDate":"2026-09-02T20:19:45.000Z","size":5673936},"name":"EBOOT.ELF","relativePath":"EBOOT.ELF",
  "resources":{"isDirectory":false}},
 {"metadata":{"lastModDate":"2026-09-24T14:34:51.000Z","size":160},"name":"USRDIR","relativePath":"USRDIR",
  "resources":{"isDirectory":true}},
 {"metadata":{"lastModDate":"2026-07-20T04:29:49.000Z","size":6987947360},"name":"USRDIR/gow2.psarc",
  "relativePath":"USRDIR/gow2.psarc","resources":{"isDirectory":false}}]}}
"""#
let fxError7000 = #"""
{"info":{"outcome":"failed"},"error":{"code":7000,"domain":"com.apple.dt.CoreDeviceError",
 "userInfo":{"NSLocalizedDescription":{"string":"Failed to retrieve the file node for Documents/nope.txt"}}}}
"""#
/// Synthetic nesting: 10002 under an underlying error. The Task 1 device-facts
/// session (docs/superpowers/specs/2026-09-25-ios-p3-devicectl-facts.md, F7) did
/// NOT capture a real 10002 JSON — a `copy to` while the phone was locked
/// returned `outcome: success` with a null `.error` (data protection on this
/// app's Documents did not block the write), and the `install app` probe on a
/// missing local file failed with unrelated local-filesystem codes (3002/1005),
/// not 10002. So there is no real fixture to paste here: this fixture is
/// synthetic, built only from the documented CoreDeviceError domain/code shape
/// (`com.apple.dt.CoreDeviceError`, `NSUnderlyingError` nesting), and it alone
/// pins the `code == 10002 -> isLocked` mapping until a real one is observed.
let fxErrorLocked = #"""
{"info":{"outcome":"failed"},"error":{"code":1,"domain":"com.apple.dt.CoreDeviceError",
 "userInfo":{"NSLocalizedDescription":{"string":"The operation couldn't be completed."},
  "NSUnderlyingError":{"error":{"code":10002,"domain":"com.apple.dt.CoreDeviceError","userInfo":{}}}}}}
"""#

func runModelChecks() {
    let devs = try! DevicectlJSON.devices(Data(fxDevices.utf8))
    check(devs.count == 1 && devs[0].udid == "00008110-TEST", "physical iOS devices only: \(devs)")
    check(devs[0].overWiFi && devs[0].paired && devs[0].booted && devs[0].developerMode
          && devs[0].model == "iPhone 14" && devs[0].osVersion == "26.6" && devs[0].name == "iPhone Teste", "props \(devs[0])")
    check(IOSPolicy.pickDevice(devs, preferred: "") == devs[0], "the only device is picked")
    let two = devs + [IOSDevice(udid: "X2", name: "b", model: "iPhone 15", osVersion: "26.0", transport: "wired",
                                paired: true, booted: true, developerMode: true)]
    check(IOSPolicy.pickDevice(two, preferred: "") == nil, "two devices and no preference -> ask the user")
    check(IOSPolicy.pickDevice(two, preferred: "X2")?.udid == "X2", "local.env's device wins")
    check(IOSPolicy.pickDevice(two, preferred: "gone") == nil, "unknown preference with two devices")
    check(IOSPolicy.pickDevice(devs, preferred: "gone") == devs[0], "unknown preference, one device -> that one")

    let lock = try! DevicectlJSON.lockState(Data(fxLock.utf8))
    check(lock == IOSLockState(passcodeRequired: true, unlockedSinceBoot: true), "lock \(lock)")
    var f7 = DeviceFacts()
    check(!IOSPolicy.isLocked(lock, facts: f7), "F7 not measured: lockState alone never says locked")
    f7.lockStateTracksLock = false
    check(!IOSPolicy.isLocked(lock, facts: f7), "F7 false: lockState ignored")
    f7.lockStateTracksLock = true
    check(IOSPolicy.isLocked(lock, facts: f7), "F7 true: passcodeRequired means locked")
    check(!IOSPolicy.isLocked(IOSLockState(passcodeRequired: false, unlockedSinceBoot: true), facts: f7), "F7 true, unlocked")

    // Recorded facts: missing file = nothing measured; a partial file keeps the rest nil.
    let fdir = tempDir("facts")
    check(DeviceFacts.load(fdir.appendingPathComponent("none.json")) == DeviceFacts(), "no facts file")
    writeFile(fdir.appendingPathComponent("f.json"), #"{"measured":"2026-09-26","copyFromNestsDirectory":false}"#)
    let facts = DeviceFacts.load(fdir.appendingPathComponent("f.json"))
    check(facts.copyFromNestsDirectory == false && facts.removeExistingContentDeletesExtras == nil
          && facts.measured == "2026-09-26", "partial facts \(facts)")
    check(DeviceError(code: DeviceError.factMissing, domain: "facts", message: "F5").userMessage.contains("ios_device_facts.json"),
          "fact-missing message")

    let apps = try! DevicectlJSON.apps(Data(fxApps.utf8))
    check(apps == [IOSApp(bundleID: "com.example.gow2", name: "God of War II",
                          url: "file:///private/var/containers/Bundle/Application/9E07BD20-0000/GoW2.app/",
                          builtByDeveloper: true)], "apps \(apps)")
    let procs = try! DevicectlJSON.processes(Data(fxProcs.utf8))
    check(procs.count == 2 && IOSPolicy.appRunning(executables: procs, appURL: apps[0].url), "GoW2 running")
    check(!IOSPolicy.appRunning(executables: ["file:///sbin/launchd"], appURL: apps[0].url), "GoW2 not running")
    check(IOSPolicy.appRunning(executables: ["file:///var/containers/Bundle/Application/9E07BD20-0000/GoW2.app/GoW2"],
                               appURL: apps[0].url), "/private prefix normalized")
    check(IOSPolicy.appRunning(executables: procs, appURL: ""), "no app url -> unknown, treated as running (fail closed)")
    check(IOSPolicy.appRunning(executables: [], appURL: ""), "no app url, no processes -> still refused")

    let files = try! DevicectlJSON.files(Data(fxFiles.utf8))
    check(files == [RemoteFile(path: "EBOOT.ELF", size: 5673936, mtime: 1788380385, isDirectory: false),
                    RemoteFile(path: "USRDIR", size: 160, mtime: 1790260491, isDirectory: true),
                    RemoteFile(path: "USRDIR/gow2.psarc", size: 6987947360, mtime: 1784521789, isDirectory: false)],
          "files \(files)")
    check(DevicectlJSON.seconds("2026-09-02T20:19:45.000Z") == 1788380385, "iso with fraction")
    check(DevicectlJSON.seconds("2026-09-02T20:19:45Z") == 1788380385, "iso without fraction")
    check(DevicectlJSON.seconds("yesterday") == nil, "junk date")

    do { _ = try DevicectlJSON.files(Data(fxError7000.utf8)); check(false, "7000 must throw") }
    catch let e as DeviceError {
        check(e.isNotFound && e.message.contains("nope.txt"), "7000 \(e)")
        check(e.isMissingFileNode, "real 'Failed to retrieve the file node' 7000 is the missing-node shape \(e)")
    }
    catch { check(false, "7000 wrong error \(error)") }
    // Incident 2026-09-26: only THIS message maps to "not present" -- a different 7000 must not.
    check(!DeviceError(code: DeviceError.notFound, domain: "com.apple.dt.CoreDeviceError", message: "some other 7000 meaning")
              .isMissingFileNode, "isMissingFileNode is scoped to the exact message, not the bare code")
    do { _ = try DevicectlJSON.lockState(Data(fxErrorLocked.utf8)); check(false, "locked must throw") }
    catch let e as DeviceError { check(e.isLocked && e.userMessage.contains("bloqueado"), "10002 nested \(e)") }
    catch { check(false, "10002 wrong error \(error)") }
    do { _ = try DevicectlJSON.devices(Data("not json".utf8)); check(false, "junk must throw") }
    catch let e as DeviceError { check(e.code == -1, "junk \(e)") }
    catch { check(false, "junk wrong error \(error)") }
    check(DeviceError(code: 1000, domain: "", message: "").userMessage.contains("cabo USB"), "1000 message")
    check(DeviceError(code: 42, domain: "d", message: "m").userMessage.contains("42"), "generic message keeps the code")

    check(IOSPolicy.macGameRunning(psComm: "/sbin/launchd\n/Users/x/gow2-recomp/g2play\n"), "g2play")
    check(IOSPolicy.macGameRunning(psComm: "/Applications/God of War II HD.app/Contents/MacOS/boot_gow2\n"), "app bundle binary")
    check(IOSPolicy.macGameRunning(psComm: "./boot_gow2_p3test\n"), "test binary")
    check(!IOSPolicy.macGameRunning(psComm: "/usr/bin/g2playlist\n/bin/zsh\n/Users/x/GoW2 Recomp.app/Contents/MacOS/GoW2Recomp\n"),
          "no false positives")
    // Final review 8: suffixed builds with '.', '-' or '_' count; look-alikes do not.
    for name in ["boot_gow2.new", "boot_gow2-p3", "boot_gow2_e435.bak", "boot_gow2_ios-p3"] {
        check(IOSPolicy.macGameRunning(psComm: "/Users/x/gow2-recomp/\(name)\n"), "suffixed build \(name)")
    }
    for name in ["g2playlist", "boot_gow2x", "boot_gow2_", "xg2play", "boot_gow22", "myboot_gow2"] {
        check(!IOSPolicy.macGameRunning(psComm: "/usr/bin/\(name)\n"), "look-alike \(name) is not the game")
    }
}
