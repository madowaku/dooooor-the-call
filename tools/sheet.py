import sys, glob, os
from PIL import Image
d, pat, out = sys.argv[1], sys.argv[2], sys.argv[3]
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 3
fs = sorted(glob.glob(os.path.join(d, pat)))
W, H = 512, 384
rows = (len(fs) + cols - 1) // cols
sh = Image.new("RGB", (W * cols, H * rows))
for i, f in enumerate(fs):
    sh.paste(Image.open(f).convert("RGB").resize((W, H)), ((i % cols) * W, (i // cols) * H))
sh.save(out)
print(len(fs), [os.path.basename(f) for f in fs])
