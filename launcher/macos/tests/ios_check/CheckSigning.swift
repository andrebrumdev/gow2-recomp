import Foundation

/// `defaults export com.apple.dt.Xcode -` (the part we read), identifiers replaced.
let fxXcodePrefs = #"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>IDEProvisioningTeamByIdentifier</key><dict>
  <key>523C3767-0000-0000-0000-000000000000</key><array><dict>
   <key>isFreeProvisioningTeam</key><true/><key>teamID</key><string>ABCDE12345</string>
   <key>teamName</key><string>Fulano (Personal Team)</string><key>teamType</key><string>Personal Team</string>
  </dict></array>
 </dict>
 <key>SomethingElse</key><integer>1</integer>
</dict></plist>
"""#

/// The plist inside an embedded.mobileprovision (after `security cms -D`).
func profilePlist(expires: String, appID: String = "ABCDE12345.com.example.gow2") -> Data {
    Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict>
     <key>Name</key><string>iOS Team Provisioning Profile: com.example.gow2</string>
     <key>UUID</key><string>11111111-2222-3333-4444-555555555555</string>
     <key>TeamIdentifier</key><array><string>ABCDE12345</string></array>
     <key>CreationDate</key><date>2026-09-24T14:19:03Z</date>
     <key>ExpirationDate</key><date>\(expires)</date>
     <key>Entitlements</key><dict><key>application-identifier</key><string>\(appID)</string></dict>
    </dict></plist>
    """.utf8)
}

func runSigningChecks() {
    let teams = Signing.teams(xcodePrefs: Data(fxXcodePrefs.utf8))
    check(teams == [XcodeTeam(id: "ABCDE12345", name: "Fulano (Personal Team)", free: true)], "teams \(teams)")
    check(Signing.teams(xcodePrefs: Data("junk".utf8)).isEmpty, "junk prefs -> no teams")

    let p = Signing.profile(plist: profilePlist(expires: "2026-10-01T14:19:03Z"))
    check(p?.appID == "ABCDE12345.com.example.gow2" && p?.team == "ABCDE12345"
          && p?.expires == Date(timeIntervalSince1970: 1790864343) && p?.created == Date(timeIntervalSince1970: 1790259543),
          "profile \(String(describing: p))")
    check(Signing.profile(plist: Data("<plist/>".utf8)) == nil, "not a profile")

    // Same rule as the phone's badge (rsx_app_sign_days_left / rsx_app_sign_urgent).
    let now = Date(timeIntervalSince1970: 1790372701)
    check(Signing.badge(Date(timeIntervalSince1970: 1790864343), now: now) == .ok(days: 6), "6 days")
    check(Signing.badge(now.addingTimeInterval(2 * 86400 + 1), now: now) == .ok(days: 3), "just over 2 days -> 3")
    check(Signing.badge(now.addingTimeInterval(2 * 86400), now: now) == .soon(days: 2), "2 days -> red")
    check(Signing.badge(now.addingTimeInterval(1), now: now) == .soon(days: 1), "1 s left -> 1 day, red")
    check(Signing.badge(now, now: now) == .expired && Signing.badge(nil, now: now) == .unknown, "expired / unknown")
    check(ExpiryBadge.soon(days: 2).urgent && ExpiryBadge.expired.urgent && !ExpiryBadge.ok(days: 3).urgent, "urgent")
    check(ExpiryBadge.soon(days: 2).text.contains("2 dias") && ExpiryBadge.expired.text.contains("Reassinar")
          && ExpiryBadge.ok(days: 6).text.contains("6 dias"), "texts")

    let gow2 = IOSApp(bundleID: "com.example.gow2", name: "God of War II",
                      url: "file:///private/var/containers/Bundle/Application/A/GoW2.app/", builtByDeveloper: true)
    let other = IOSApp(bundleID: "com.example.other", name: "Other",
                       url: "file:///private/var/containers/Bundle/Application/B/Other.app/", builtByDeveloper: true)
    let store = IOSApp(bundleID: "com.store.gow2", name: "Fake",
                       url: "file:///private/var/containers/Bundle/Application/C/GoW2.app/", builtByDeveloper: false)
    check(Signing.suggestedBundle([other, store, gow2]) == "com.example.gow2", "the developer-built GoW2.app")
    check(Signing.suggestedBundle([other, store]) == nil, "no GoW2 installed")

    let home = tempDir("signing")
    let dir = Signing.profilesDir(home: home)
    check(dir.path.hasSuffix("Library/Developer/Xcode/UserData/Provisioning Profiles"), "Xcode's profile cache")
    writeFile(dir.appendingPathComponent("mine.mobileprovision"), "mine")
    writeFile(dir.appendingPathComponent("other.mobileprovision"), "other")
    let reader: (URL) throws -> Data = { u in
        profilePlist(expires: "2026-10-01T14:19:03Z",
                     appID: u.lastPathComponent.hasPrefix("mine") ? "ABCDE12345.com.example.gow2" : "ABCDE12345.com.example.other")
    }
    let moved = try! Signing.retireProfiles(appID: "ABCDE12345.com.example.gow2", from: dir,
                                            to: home.appendingPathComponent("retired"), reader: reader)
    check(moved.count == 1 && !FileManager.default.fileExists(atPath: dir.appendingPathComponent("mine.mobileprovision").path)
          && FileManager.default.fileExists(atPath: dir.appendingPathComponent("other.mobileprovision").path)
          && FileManager.default.fileExists(atPath: moved[0].retired.path), "only this app's profile retired, never deleted")
    Signing.restore(moved)
    check(FileManager.default.fileExists(atPath: dir.appendingPathComponent("mine.mobileprovision").path), "restored")
    check((try? Signing.retireProfiles(appID: "x", from: home.appendingPathComponent("none"), to: home, reader: reader)) == [],
          "no cache dir -> nothing to retire")
    check(Signing.freeTeamLimits.contains("7 dias") && Signing.freeTeamLimits.contains("3 apps"), "free-team limits documented")
}
