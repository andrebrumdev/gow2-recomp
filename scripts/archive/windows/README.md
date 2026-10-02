# Windows bring-up archive (July 2026)

Scripts written on the original Windows/MinGW machine before the project moved to the Mac
(`build_macos.sh`). They hard-code that machine's paths (`/c/Users/softlive/...`, `boot_hle.exe`,
`taskkill`, `ps -W`) and are kept only as history: the session notes that cite them still make sense.
Nothing in the current build, kit, launchers or tests calls them.

| Folder | Contents |
|---|---|
| [`trace/`](trace/README.md) | 46 one-off `tr*.sh` trace runs + `cas.pl` |
| [`diag/`](diag/README.md) | gdb attach / sample / watch / dump scripts + 2 gdb command files |
| [`build/`](build/README.md) | legacy MinGW lift-and-link scripts |

Moved here from the repository root on 2026-10-02 (`git log --follow` shows their history).
