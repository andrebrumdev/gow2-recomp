#!/usr/bin/env python3
"""Guard (P2 Task 20): the iOS host starts on the home screen. main() prepares
only the display, before the home starts (no ELF before "Jogar"), allows
portrait for the home, keeps touches from turning into mouse events and hands
over to gow2_ios_home_begin; gow2_boot_prepare_guest is called only on the
guest thread (guest_main), before gow2_boot_run_guest; the lifecycle's input op
drops touch contacts on resign; the home runs the phone UI profile, polls the
pad only until the guest starts, presents UI-only frames, starts the guest on
the overlay's request and hands events/overlay to the game on the first guest
frame (IN_GAME first, then the event thread changes); the host never feeds
rsx_overlay_touch itself (only the backend's pump does, on the event thread);
the blocking "not installed" alert is gone; the iPhone plist allows portrait,
the iPad plist stays landscape."""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
IOS = HERE.parent / "ios"


def strip(t):
    t = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), t, flags=re.S)
    return re.sub(r"//[^\n]*", "", t)


def body(text, signature):
    m = re.search(signature + r"\s*\{", text)
    if not m:
        return None
    depth, i = 1, m.end()
    while depth and i < len(text):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        i += 1
    return text[m.end():i - 1]


def before(text, a, b):
    i, j = text.find(a), text.find(b)
    return i >= 0 and j >= 0 and i < j


def main():
    fails = []
    main_m = strip((IOS / "Sources/gow2_ios_main.m").read_text(encoding="utf-8"))
    host = strip((IOS / "Sources/gow2_ios_host.m").read_text(encoding="utf-8"))
    yml = (IOS / "project.yml").read_text(encoding="utf-8")
    if "gow2_boot_prepare_display()" not in main_m or re.search(r"gow2_boot_prepare\(", main_m):
        fails.append("main() must call gow2_boot_prepare_display() and not gow2_boot_prepare()")
    if not before(main_m, "gow2_ios_host_load_config()", "gow2_boot_prepare_display()"):
        fails.append("the configuration must load before the display is prepared")
    if not before(main_m, "gow2_boot_prepare_display()", "gow2_ios_home_begin()"):
        fails.append("the display must be prepared before the home screen starts")
    if "gow2_boot_prepare_guest(" in main_m or len(re.findall(r"gow2_boot_prepare_guest\(", host)) != 1:
        fails.append("gow2_boot_prepare_guest must be called once, on the guest thread only")
    if "rsx_overlay_touch(" in host or "rsx_overlay_touch(" in main_m:
        fails.append("the host must not feed rsx_overlay_touch (the backend's pump does, on the event thread)")
    if "gow2_ios_home_begin()" not in main_m or "gow2_ios_start_game()" in main_m:
        fails.append("main() must start the home screen, not the game")
    if not re.search(r'SDL_HINT_ORIENTATIONS,\s*"[^"]*Portrait', main_m):
        fails.append("main() must allow portrait for the home screen")
    if not re.search(r'SDL_HINT_TOUCH_MOUSE_EVENTS,\s*"0"', main_m):
        fails.append("touches must not become SDL mouse events")
    gm = body(host, r"static void\* guest_main\(void\* arg\)")
    if gm is None or not before(gm, "gow2_boot_prepare_guest(", "gow2_boot_run_guest()"):
        fails.append("guest_main must prepare the guest before running it")
    si = body(host, r"static void host_set_input_active\(int on\)")
    if si is None or "rsx_overlay_touch_cancel_all()" not in si or "cpgc_set_app_active(on)" not in si:
        fails.append("host_set_input_active must gate the keyboard and cancel touch contacts")
    if ".set_input_active = host_set_input_active" not in host:
        fails.append("the lifecycle's set_input_active op must be host_set_input_active")
    hf = body(host, r"static void home_frame\(void\* arg\)")
    if hf is None:
        fails.append("home_frame missing")
    else:
        for tok in ("rsx_metal_backend_pump_messages()", "rsx_overlay_take_start_request()", "gow2_ios_start_game()",
                    "rsx_metal_backend_present_ui()", "rsx_metal_backend_guest_frames()"):
            if tok not in hf:
                fails.append(f"home_frame must call {tok}")
        if not before(hf, "rsx_overlay_app_game_started()", "rsx_metal_backend_set_host_ui(0)"):
            fails.append("home_frame: switch the overlay to IN_GAME before handing events to the guest thread")
    hb = body(host, r"void gow2_ios_home_begin\(void\)")
    if hb is None or not all(t in hb for t in ("rsx_metal_backend_set_host_ui(1)", "rsx_overlay_touch_enable(1)",
                                              "rsx_overlay_set_ui_profile(RSX_OVERLAY_UI_PHONE)",
                                              "rsx_overlay_app_enable_home()", "SDL_iPhoneSetAnimationCallback(")):
        fails.append("gow2_ios_home_begin must own the UI, set the phone profile, enable touch and the home, "
                     "and start the frame callback")
    elif not before(hb, "rsx_metal_backend_set_host_ui(1)", "SDL_iPhoneSetAnimationCallback("):
        fails.append("the host must own the UI before its frame callback runs")
    if hf is not None and not re.search(r"if\s*\(\s*!s_starting\s*\)\s*\{[^}]*cpgc_poll\(", hf):
        fails.append("home_frame may poll the pad only until the guest starts (the guest thread polls it then)")
    if "SDL_ShowSimpleMessageBox" in host:
        fails.append("the blocking 'Jogo não instalado' alert must be gone (the home shows it)")
    m = re.search(r"UISupportedInterfaceOrientations:\s*\[([^\]]*)\]", yml)
    mi = re.search(r"UISupportedInterfaceOrientations~ipad:\s*\[([^\]]*)\]", yml)
    if not m or "UIInterfaceOrientationPortrait" not in m.group(1):
        fails.append("iPhone orientations must include portrait (home)")
    if not mi or "Portrait" in mi.group(1):
        fails.append("iPad orientations stay landscape")
    for f in fails:
        print("FAIL:", f)
    print("PASS" if not fails else f"FAIL {len(fails)}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
