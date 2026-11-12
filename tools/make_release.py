"""Build out/release/Tekken8Access-<ver>.zip (mod folder still Mods/TekkenA11y): extract into TEKKEN 8\Polaris\Binaries\Win64.
Contains UE4SS 3.0.1 (from the game folder's UE4SS-For-Tekken8.zip, with the tested settings ini)
and the built mod from out/TekkenA11y. Entries use forward slashes."""
import os, sys, zipfile
ver = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
win64 = r"C:\Program Files (x86)\Steam\steamapps\common\TEKKEN 8\Polaris\Binaries\Win64"
outdir = os.path.join(root, "out", "release"); os.makedirs(outdir, exist_ok=True)
dst = os.path.join(outdir, f"Tekken8Access-{ver}.zip")
if os.path.exists(dst): os.remove(dst)
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z, zipfile.ZipFile(os.path.join(win64, "UE4SS-For-Tekken8.zip")) as ue:
    for n in ue.namelist():
        if n.endswith("/") or n in ("README.md", "Changelog.md"): continue
        if n == "UE4SS-settings.ini":
            z.write(os.path.join(win64, n), n)          # tested settings (console window off)
        else:
            z.writestr(n.replace("\\", "/"), ue.read(n))
    z.write(os.path.join(root, "third_party", "UE4SS-LICENSE.txt"), "UE4SS-LICENSE.txt")
    mod = os.path.join(root, "out", "TekkenA11y")
    for d, _, files in os.walk(mod):
        for f in files:
            if f in ("dev.txt",) or f.endswith(".log"): continue
            p = os.path.join(d, f)
            z.write(p, "Mods/TekkenA11y/" + os.path.relpath(p, mod).replace("\\", "/"))
    z.write(os.path.join(mod, "README.txt"), "Tekken 8 Access README.txt")
bad = [n for n in zipfile.ZipFile(dst).namelist() if "\\" in n]
print(dst, os.path.getsize(dst), "bytes; backslash names:", bad)
