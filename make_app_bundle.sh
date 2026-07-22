#!/usr/bin/env bash
# Gera "God of War II HD.app" -- um bundle macOS que apresenta o binario
# recompilado como o jogo real: nome, icone (Finder/Dock/barra de menus) e
# duplo-clique, tudo a partir dos DADOS DO PROPRIO JOGO (PARAM.SFO/ICON0.PNG).
#
# O .app NAO e' versionado (contem hard-link do boot_gow2 + icone derivado do
# jogo). Re-correr apos cada ./build_macos.sh (o hard-link aponta para o binario
# de entao). Uso: ./make_app_bundle.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

[ -x ./boot_gow2 ] || { echo "boot_gow2 nao existe -- rode ./build_macos.sh primeiro" >&2; exit 1; }
SFO="extracted/PARAM.SFO"; ICON="extracted/ICON0.PNG"
[ -f "$SFO" ]  || { echo "$SFO nao encontrado" >&2; exit 1; }
[ -f "$ICON" ] || { echo "$ICON nao encontrado" >&2; exit 1; }

# --- 1. Metadados do jogo (TITLE + APP_VER) + icone master 1024, do jogo ------
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
python3 - "$SFO" "$ICON" "$WORK/master.png" "$WORK/meta.txt" <<'PY'
import struct, sys
from PIL import Image, ImageDraw
sfo, icon, master_out, meta_out = sys.argv[1:5]

# PARAM.SFO -> TITLE, APP_VER
d = open(sfo, 'rb').read()
_, _, ks, ds, n = struct.unpack_from('<IIIII', d, 0)
title, ver = 'God of War II HD', '1.00'
for i in range(n):
    ko, fmt, dl, dm, do = struct.unpack_from('<HHIII', d, 0x14 + i*16)
    k = d[ks+ko:d.index(b'\0', ks+ko)].decode('ascii', 'replace')
    v = d[ds+do:ds+do+dl].split(b'\0')[0].decode('utf-8', 'replace')
    if k == 'TITLE':   title = v
    elif k == 'APP_VER': ver = v
open(meta_out, 'w').write(title + '\n' + ver + '\n')

# ICON0.PNG -> tile 1024 (fundo escuro arredondado + arte centrada, aspect ok)
S = 1024
tile = Image.new('RGBA', (S, S), (0, 0, 0, 0))
mask = Image.new('L', (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S-1, S-1], radius=185, fill=255)
bg = Image.new('RGBA', (S, S), (18, 18, 26, 255))
tile.paste(bg, (0, 0), mask)
art = Image.open(icon).convert('RGBA')
target_w = int(S * 0.86)
scale = target_w / art.width
art = art.resize((target_w, max(1, int(art.height * scale))), Image.LANCZOS)
tile.paste(art, ((S - art.width)//2, (S - art.height)//2), art)
tile.save(master_out)
PY

TITLE="$(sed -n '1p' "$WORK/meta.txt")"
APPVER="$(sed -n '2p' "$WORK/meta.txt")"
# Nome de ficheiro sem simbolos de marca.
FNAME="$(printf '%s' "$TITLE" | sed 's/[®™©]//g; s/  */ /g; s/^ *//; s/ *$//')"
APP="$HERE/${FNAME}.app"
echo "[bundle] TITLE=\"$TITLE\"  APP_VER=$APPVER  ->  ${FNAME}.app"

# --- 2. .icns a partir do master (iconutil) -----------------------------------
ISET="$WORK/AppIcon.iconset"; mkdir -p "$ISET"
gen() { sips -z "$2" "$2" "$WORK/master.png" --out "$ISET/$1" >/dev/null; }
gen icon_16x16.png 16;      gen icon_16x16@2x.png 32
gen icon_32x32.png 32;      gen icon_32x32@2x.png 64
gen icon_128x128.png 128;   gen icon_128x128@2x.png 256
gen icon_256x256.png 256;   gen icon_256x256@2x.png 512
gen icon_512x512.png 512;   gen icon_512x512@2x.png 1024
iconutil -c icns "$ISET" -o "$WORK/AppIcon.icns"

# --- 3. Estrutura do bundle ---------------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# boot_gow2 DENTRO do bundle (hard-link, sem custo de disco) -> [NSBundle
# mainBundle] resolve para o .app e a barra de menus mostra CFBundleName.
ln -f "$HERE/boot_gow2" "$APP/Contents/MacOS/boot_gow2"

# Launcher = CFBundleExecutable: prepara env do jogo e faz exec do boot dentro
# do bundle. GAME_DIR e' embutido (onde vivem EBOOT.ELF/extracted/env_gow2.sh).
cat > "$APP/Contents/MacOS/launch" <<LAUNCH
#!/bin/bash
BUNDLE_MACOS="\$(cd "\$(dirname "\$0")" && pwd)"
GAME_DIR="$HERE"
cd "\$GAME_DIR" || exit 1
. "\$GAME_DIR/env_gow2.sh"
export PS3_FULLSCREEN="\${PS3_FULLSCREEN:-1}"   # padrao de jogo (ESC sai)
exec "\$BUNDLE_MACOS/boot_gow2" "\$GAME_DIR/EBOOT.ELF"
LAUNCH
chmod +x "$APP/Contents/MacOS/launch"

# Info.plist (nome/icone/versao do jogo; MetalFX pede macOS 13+).
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${FNAME}</string>
    <key>CFBundleDisplayName</key><string>${TITLE}</string>
    <key>CFBundleExecutable</key><string>launch</string>
    <key>CFBundleIdentifier</key><string>com.ps3recomp.npua80491</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${APPVER}</string>
    <key>CFBundleVersion</key><string>${APPVER}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.action-games</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" >/dev/null && echo "[bundle] Info.plist ok"
touch "$APP"   # Finder refresca o icone
echo "[bundle] pronto: $APP"
echo "[bundle] abrir:  open \"$APP\"   (ou duplo-clique no Finder)"
