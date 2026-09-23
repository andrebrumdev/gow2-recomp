import SwiftUI

/// Player-facing options. Every one maps to an environment switch the
/// runtime already reads; nothing here invents behaviour.
@MainActor
final class GameSettings: ObservableObject {
    @AppStorage("fullscreen") var fullscreen = true
    @AppStorage("vsync") var vsync = true
    @AppStorage("metalFX") var metalFX = true
    @AppStorage("hdr") var hdr = false
    @AppStorage("frameFence") var frameFence = true
    @AppStorage("soundOn") var soundOn = true
    @AppStorage("movieSkip") var movieSkip = true
    @AppStorage("autostart") var autostart = false
    @AppStorage("extraEnv") var extraEnv = ""

    private func flag(_ on: Bool) -> String { on ? "1" : "0" }

    var environment: [String: String] {
        var env: [String: String] = [
            "PS3_FULLSCREEN": flag(fullscreen),     // rsx_metal_backend.m
            "PS3_METAL_VSYNC": flag(vsync),
            "PS3_METALFX": flag(metalFX),            // MetalFX spatial upscale
            "PS3_METAL_HDR": flag(hdr),
            "PS3_METAL_FRAME_FENCE": flag(frameFence), // no 1-frame giant triangle
            "PS3_MUTE": flag(!soundOn),              // audio_mute.c
            "PS3_MOVIE_SKIP": flag(movieSkip),       // cellPad.c: START/CROSS skips
            "PS3_PAD_AUTOSTART": flag(autostart),    // presses Start through the intro
        ]
        // Advanced: KEY=VALUE per line, for testers.
        for line in extraEnv.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2, parts[0].hasPrefix("PS3_") { env[parts[0]] = parts[1] }
        }
        return env
    }
}
