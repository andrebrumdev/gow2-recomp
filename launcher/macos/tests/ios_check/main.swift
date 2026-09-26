import Foundation

// Launcher iOS checks (P3). No device, no network. argv[1] = manifest_probe.
runModelChecks()
runManifestChecks()
runPusherChecks()
runScriptChecks()
runSigningChecks()
runSaveSyncPlanChecks()
runSaveSyncerChecks()
await runBackendChecks()
print(checkFails == 0 ? "ios_check: PASS" : "ios_check: FAIL \(checkFails)")
exit(checkFails == 0 ? 0 : 1)
