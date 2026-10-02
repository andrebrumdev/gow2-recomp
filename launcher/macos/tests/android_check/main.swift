import Foundation

// Launcher Android checks. No device, no network: a fake adb in a fake SDK and a fake script runner.
runAndroidPureChecks()
await runAndroidBackendChecks()
print(checkFails == 0 ? "android_check: PASS" : "android_check: FAIL \(checkFails)")
exit(checkFails == 0 ? 0 : 1)
