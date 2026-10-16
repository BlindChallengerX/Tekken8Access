"""Step right through the character select grid; for each fighter record the id the
game passes to OnSetCurrentName and a crop of the name picture. Writes a contact
sheet (names.png) labelled with ids. Needs ah.lua hooks (argl) installed."""
import os, sys, time
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(__file__))
import t8

out = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 50
STAGE = len(sys.argv) > 3 and sys.argv[3] == 'stage'
crops = []
seen = []
for i in range(n):
    t8.lua("argl = {}")
    t8.press("right", after=0.9)
    pat = '_SetSelectedStageID%(number:(%d+)' if STAGE else 'OnSetCurrentName%(boolean:true | number:(%d+)'
    r = t8.lua("for i = #argl, 1, -1 do local id = argl[i]:match('" + pat + "') if id then return id end end return 'none'")
    cid = r.replace("=> ", "").strip()
    p = os.path.join(out, f"n{i}.png")
    t8.shot(p)
    im = Image.open(p)
    w, h = im.size
    crop = im.crop((int(w * 0.05), int(h * 0.08), int(w * 0.9), int(h * 0.28))) if STAGE else im.crop((int(w * 0.05), int(h * 0.76), int(w * 0.35), int(h * 0.90)))
    crops.append((cid, crop))
    print(i, cid, flush=True)
    if cid in seen[:3] and i > 5:
        break
    seen.append(cid)

cw, ch = crops[0][1].size
cols = 2 if STAGE else 4
rows = (len(crops) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cw, rows * (ch + 24)), "black")
d = ImageDraw.Draw(sheet)
for k, (cid, c) in enumerate(crops):
    x, y = (k % cols) * cw, (k // cols) * (ch + 24)
    sheet.paste(c, (x, y + 24))
    d.text((x + 5, y + 4), f"id {cid}", fill="yellow")
sheet.save(os.path.join(out, "names.png"))
