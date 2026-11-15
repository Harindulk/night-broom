# Builds media/cover.png (630x500) from the game's own Kenney tiles.
import random
from PIL import Image, ImageDraw, ImageFont
random.seed(7)
col = Image.open('assets/sprites/tiles.png').convert('RGBA')
mono = Image.open('assets/sprites/tiles_mono.png').convert('RGBA')
W, H = 630, 500

def tile(c, r, scale, tint=None, src=None, rot=0, flip=False):
    im = (src or col).crop((c*16, r*16, c*16+16, r*16+16))
    if tint:
        px = im.load()
        for x in range(16):
            for y in range(16):
                p = px[x, y]
                if p[3]:
                    px[x, y] = (int(p[0]*tint[0]/255), int(p[1]*tint[1]/255), int(p[2]*tint[2]/255), p[3])
    if flip: im = im.transpose(Image.FLIP_LEFT_RIGHT)
    if rot: im = im.rotate(rot, expand=False)
    return im.resize((16*scale, 16*scale), Image.NEAREST)

def put(img, im, cx, cy): img.alpha_composite(im, (int(cx - im.width/2), int(cy - im.height/2)))

img = Image.new('RGBA', (W, H))
d = ImageDraw.Draw(img)
top, low = (10, 5, 26), (52, 22, 80)
for i in range(20):
    t = i / 19
    c = tuple(int(top[k] + (low[k]-top[k])*t) for k in range(3))
    d.rectangle([0, i*H*0.75/20, W, (i+1)*H*0.75/20 + 1], fill=c + (255,))
for _ in range(90):
    x, y = random.randrange(W), random.randrange(int(H*0.7))
    a = random.randint(80, 255)
    d.rectangle([x, y, x+1, y+1], fill=(255, 255, 230, a))
put(img, tile(20, 5, 6, (255, 242, 190), mono), 555, 225)
# village
x = 0
for c, r in [(2,19),(3,20),(4,21),(0,1),(6,20),(2,1),(7,21),(5,19),(8,20),(3,1)]:
    s = 4 if r > 10 else 3
    put(img, tile(c, r, s, (60, 40, 92), mono), x + 8*s, 375 - 8*s)
    x += 16*s + 6
d.rectangle([0, 375, W, H], fill=(23, 15, 38, 255))
d.rectangle([0, 375, W, 376], fill=(76, 52, 115, 255))
for px_ in [60, 250, 470]:
    put(img, tile(33, 18, 3, (255, 140, 30), mono), px_, 360)
# actors
put(img, tile(34, 3, 9, (217, 153, 90), mono, rot=-45), 292, 268)
put(img, tile(26, 9, 8, (158, 255, 140), mono), 300, 222)
for (bx, by, s) in [(105, 200, 5), (470, 300, 4), (170, 305, 3)]:
    put(img, tile(26, 8, s, (255, 107, 128), mono), bx, by)
for (cx, cy, i) in [(430, 210, 0), (200, 245, 1), (380, 300, 2)]:
    put(img, tile(32+i, 10, 3), cx, cy)
# keyboard: left key haunted, its arrow points right
keys = [(315, 418, 0, False), (315, 469, 180, False), (264, 469, 90, True), (366, 469, -90, False)]
for (kx, ky, rot, h) in keys:
    d.rounded_rectangle([kx-23, ky-23, kx+23, ky+23], 6, fill=(150, 90, 230, 255) if h else (217, 209, 230, 255), outline=(13, 6, 25, 255), width=3)
    put(img, tile(28, 21, 3, (255, 255, 255) if h else (31, 20, 51), mono, rot=(-90 if h else rot)), kx, ky)
put(img, tile(27, 8, 3, (190, 242, 255)), 238, 432)
# ghost on its way down
put(img, tile(27, 8, 4, (190, 242, 255)), 150, 395)
f = ImageFont.truetype('assets/fonts/kenpixel.ttf', 68)
f2 = ImageFont.truetype('assets/fonts/kenpixel.ttf', 20)
def txt(y, s, font, fill, o=4):
    w = d.textlength(s, font=font); x = (W - w) / 2
    for dx in range(-o, o+1, 2):
        for dy in range(-o, o+1, 2): d.text((x+dx, y+dy), s, font=font, fill=(13, 6, 25, 255))
    d.text((x, y), s, font=font, fill=fill)
txt(26, 'NIGHT BROOM', f, (255, 178, 64, 255))
txt(110, 'ghosts are haunting your keyboard', f2, (225, 205, 255, 255), 2)
img.convert('RGB').save('media/cover.png')
print('ok')
