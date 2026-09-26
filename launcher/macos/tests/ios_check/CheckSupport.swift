import Foundation

var checkFails = 0

func check(_ ok: Bool, _ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) {
    if !ok {
        checkFails += 1
        print("FAIL \(file):\(line): \(message())")
    }
}

/// A fresh directory under the temp dir, symlinks resolved (/var -> /private/var).
func tempDir(_ tag: String) -> URL {
    let u = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ios_check-\(tag)-\(getpid())-\(UUID().uuidString.prefix(8))")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u.resolvingSymlinksInPath()
}

func writeFile(_ u: URL, _ text: String, mtime: Date? = nil) {
    try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data(text.utf8).write(to: u)
    if let m = mtime { try! FileManager.default.setAttributes([.modificationDate: m], ofItemAtPath: u.path) }
}

/// The iOS app's own verdict (gow2_ios_install_state) on a Documents dir: 0 missing, 1 ok, 2 incomplete.
func probeState(_ docs: URL) -> Int {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
    p.arguments = [docs.path]
    let out = Pipe()
    p.standardOutput = out
    try! p.run()
    p.waitUntilExit()
    let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard let r = text.range(of: "state=") else { return -1 }
    return Int(String(text[r.upperBound...].prefix(1))) ?? -1
}
