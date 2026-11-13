#!/bin/sh
# Builds the TekkenA11y helper with the 64-bit w64devkit and assembles the mod in out/TekkenA11y.
set -e
cd "$(dirname "$0")"
export PATH="/c/Users/michm/tools/w64x64/w64devkit/bin:$PATH"
mkdir -p out/TekkenA11y/speaker out/TekkenA11y/Scripts
gcc -O2 -Wall -Wno-misleading-indentation -mwindows -municode -s -o out/TekkenA11y/speaker/TekkenA11yHelper.exe \
  helper/main.c helper/speech.c helper/audio.c helper/beacon.c helper/attack.c helper/walls.c \
  -Ithird_party/prism -Ihelper -static -lole32 -luuid -lsapi -lwinmm
cp -u third_party/prism/prism.dll out/TekkenA11y/speaker/
cp -r mod/Scripts/. out/TekkenA11y/Scripts/
cp mod/README.txt out/TekkenA11y/ 2>/dev/null || true
touch out/TekkenA11y/enabled.txt
echo built
