# Draws the honeycomb shop's white (tintable) images: hexFill, hexOutline, hexBottom (lower rim), check.
# Flat-top hexagon (points left/right) at 512x444 with slightly rounded corners, 4x supersampled.
import math
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "ui", "honeycomb")
SS = 4
W, H = 512, 444
CORNER = 18
RING = 22
DROP = round(5 * H / 96)


def hex_points(cx, cy, r, corner):
	# A regular hexagon's interior angle is 120 deg: tangent points sit corner/sqrt(3) from each vertex.
	verts = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in range(0, 360, 60)]
	pts = []
	for i, (vx, vy) in enumerate(verts):
		toward_centre = math.atan2(cy - vy, cx - vx)
		centre_dist = corner / math.sin(math.radians(60))
		ax, ay = vx + centre_dist * math.cos(toward_centre), vy + centre_dist * math.sin(toward_centre)
		outward = toward_centre + math.pi
		for step in range(13):
			t = outward + math.radians(-30 + 60 * step / 12)
			pts.append((ax + corner * math.cos(t), ay + corner * math.sin(t)))
	return pts


def hexagon(draw_fn):
	img = Image.new("L", (W * SS, H * SS), 0)
	draw_fn(ImageDraw.Draw(img))
	return img.resize((W, H), Image.LANCZOS)


def save(mask, name, size):
	out = Image.new("RGBA", size, (255, 255, 255, 0))
	out.putalpha(mask)
	out.save(os.path.join(OUT, name + ".png"))


def main():
	os.makedirs(OUT, exist_ok=True)
	cx, cy = W * SS / 2, H * SS / 2
	r = (W / 2 - 1) * SS
	apothem = r * math.sqrt(3) / 2
	inner_r = r * (apothem - RING * SS) / apothem

	fill = lambda d: d.polygon(hex_points(cx, cy, r, CORNER * SS), fill=255)
	save(hexagon(fill), "hexFill", (W, H))

	def ring(d):
		d.polygon(hex_points(cx, cy, r, CORNER * SS), fill=255)
		d.polygon(hex_points(cx, cy, inner_r, CORNER * SS * 0.6), fill=0)

	save(hexagon(ring), "hexOutline", (W, H))

	# Hud is ZIndexBehavior Sibling, so Bottom (a child) draws over the hex: draw only the rim that
	# shows below it when Bottom sits DROP px lower (5 of 96 on screen).
	def bottom(d):
		d.polygon(hex_points(cx, cy, r, CORNER * SS), fill=255)
		d.polygon(hex_points(cx, cy - DROP * SS, r, CORNER * SS), fill=0)

	save(hexagon(bottom), "hexBottom", (W, H))

	cs = 256
	img = Image.new("L", (cs * SS, cs * SS), 0)
	d = ImageDraw.Draw(img)
	stroke = 44 * SS
	path = [(52 * SS, 136 * SS), (106 * SS, 190 * SS), (206 * SS, 72 * SS)]
	d.line(path, fill=255, width=stroke, joint="curve")
	for x, y in (path[0], path[-1]):
		d.ellipse((x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2), fill=255)
	save(img.resize((cs, cs), Image.LANCZOS), "check", (cs, cs))

	# Back hex: a chunky left arrow with rounded ends.
	img = Image.new("L", (cs * SS, cs * SS), 0)
	d = ImageDraw.Draw(img)
	stroke = 52 * SS
	tip, head = (50 * SS, 128 * SS), 74 * SS
	arms = [(tip[0] + head, tip[1] - head), tip, (tip[0] + head, tip[1] + head)]
	d.line(arms, fill=255, width=stroke, joint="curve")
	d.line([tip, (212 * SS, 128 * SS)], fill=255, width=stroke)
	for x, y in (arms[0], arms[2], tip, (212 * SS, 128 * SS)):
		d.ellipse((x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2), fill=255)
	save(img.resize((cs, cs), Image.LANCZOS), "back_arrow", (cs, cs))

	# Areas hex: a waving flag on a pole.
	img = Image.new("L", (cs * SS, cs * SS), 0)
	d = ImageDraw.Draw(img)
	pole = 24 * SS
	px = 66 * SS
	d.rounded_rectangle((px - pole / 2, 28 * SS, px + pole / 2, 236 * SS), radius=pole / 2, fill=255)
	d.ellipse((px - 22 * SS, 14 * SS, px + 22 * SS, 58 * SS), fill=255)
	top, bottom, left, right = 50 * SS, 146 * SS, px, 220 * SS
	wave = 14 * SS
	upper = [(left + (right - left) * t / 24, top + wave * math.sin(t / 24 * 2 * math.pi)) for t in range(25)]
	lower = [(left + (right - left) * t / 24, bottom + wave * math.sin(t / 24 * 2 * math.pi)) for t in range(24, -1, -1)]
	d.polygon(upper + lower, fill=255)
	save(img.resize((cs, cs), Image.LANCZOS), "area_flag", (cs, cs))


# clear-tide style: white fill (tinted by a UIGradient), a thin rim inset from the edge, and a soft
# black glow drawn on a 1.25x canvas so the blur isn't clipped (size its ImageLabel 1.25x the hex).
CT_OUT = os.path.join(os.path.dirname(__file__), "..", "ui", "clear-tide")
CT_RIM_INSET = 10
CT_RIM_WIDTH = 6
CT_GLOW_GROW = 1.08
CT_GLOW_CANVAS = 1.25
CT_GLOW_BLUR = 12


def clear_tide():
	from PIL import ImageFilter

	os.makedirs(CT_OUT, exist_ok=True)

	def save_ct(mask, name, colour):
		out = Image.new("RGBA", mask.size, colour + (0,))
		out.putalpha(mask)
		out.save(os.path.join(CT_OUT, name + ".png"))

	cx, cy = W * SS / 2, H * SS / 2
	r = (W / 2 - 1) * SS
	apothem = r * math.sqrt(3) / 2

	def inset(px):
		return r * (apothem - px * SS) / apothem

	save_ct(hexagon(lambda d: d.polygon(hex_points(cx, cy, r, CORNER * SS), fill=255)), "ct_hexFill", (255, 255, 255))

	def rim(d):
		d.polygon(hex_points(cx, cy, inset(CT_RIM_INSET), CORNER * SS * 0.8), fill=255)
		d.polygon(hex_points(cx, cy, inset(CT_RIM_INSET + CT_RIM_WIDTH), CORNER * SS * 0.75), fill=0)

	save_ct(hexagon(rim), "ct_hexRim", (255, 255, 255))

	gw, gh = round(W * CT_GLOW_CANVAS), round(H * CT_GLOW_CANVAS)
	img = Image.new("L", (gw * SS, gh * SS), 0)
	ImageDraw.Draw(img).polygon(
		hex_points(gw * SS / 2, gh * SS / 2, r * CT_GLOW_GROW, CORNER * SS * CT_GLOW_GROW), fill=255
	)
	glow = img.resize((gw, gh), Image.LANCZOS).filter(ImageFilter.GaussianBlur(CT_GLOW_BLUR))
	save_ct(glow, "ct_hexGlow", (0, 0, 0))


CT_COIN_FACE = (0xFD, 0xCE, 0x21)
CT_COIN_MARK = (0xE8, 0xA8, 0x00)
CT_COIN_EDGE = (0xC9, 0x8A, 0x00)
CT_ROUND_RADIUS = 16


# clear-tide icons and glows: white (tintable) except the coin, 4x supersampled.
def clear_tide_icons():
	from PIL import ImageChops, ImageFilter

	os.makedirs(CT_OUT, exist_ok=True)
	cs = 256

	def save_white(mask, name):
		out = Image.new("RGBA", mask.size, (255, 255, 255, 0))
		out.putalpha(mask)
		out.save(os.path.join(CT_OUT, name + ".png"))

	def canvas(w=cs, h=cs):
		img = Image.new("L", (w * SS, h * SS), 0)
		return img, ImageDraw.Draw(img)

	def dot(d, x, y, stroke, fill=255):
		d.ellipse((x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2), fill=fill)

	def stroke_path(d, path, stroke):
		d.line(path, fill=255, width=round(stroke), joint="curve")
		for x, y in path:
			dot(d, x, y, stroke)

	def s(*v):
		return [n * SS for n in v]

	# 1. ct_hexGlowWhite: ct_hexGlow's halo in white, for tinted glows.
	r = (W / 2 - 1) * SS
	gw, gh = round(W * CT_GLOW_CANVAS), round(H * CT_GLOW_CANVAS)
	img, d = canvas(gw, gh)
	d.polygon(hex_points(gw * SS / 2, gh * SS / 2, r * CT_GLOW_GROW, CORNER * SS * CT_GLOW_GROW), fill=255)
	save_white(img.resize((gw, gh), Image.LANCZOS).filter(ImageFilter.GaussianBlur(CT_GLOW_BLUR)), "ct_hexGlowWhite")

	# 2. ct_softGlow: radial ellipse fading smoothly to nothing at its edge.
	gw, gh = 256, 128
	pixels = []
	for y in range(gh):
		for x in range(gw):
			dx, dy = (x + 0.5 - gw / 2) / (gw / 2), (y + 0.5 - gh / 2) / (gh / 2)
			t = max(0.0, 1.0 - math.sqrt(dx * dx + dy * dy))
			pixels.append(round(255 * t * t * (3 - 2 * t)))
	glow = Image.new("L", (gw, gh))
	glow.putdata(pixels)
	save_white(glow, "ct_softGlow")

	# 3. ct_coin (in colour): a darker edge peeking below the face, an inner ring and a star.
	coin = Image.new("RGBA", (cs * SS, cs * SS), (0, 0, 0, 0))
	d = ImageDraw.Draw(coin)
	rad = 120
	d.ellipse(s(128 - rad, 132 - rad, 128 + rad, 132 + rad), fill=CT_COIN_EDGE)
	d.ellipse(s(128 - rad, 124 - rad, 128 + rad, 124 + rad), fill=CT_COIN_FACE)
	d.ellipse(s(128 - 92, 124 - 92, 128 + 92, 124 + 92), fill=CT_COIN_MARK)
	d.ellipse(s(128 - 80, 124 - 80, 128 + 80, 124 + 80), fill=CT_COIN_FACE)
	star = []
	for i in range(10):
		a = math.radians(-90 + 36 * i)
		rr = 46 if i % 2 == 0 else 20
		star.append((128 * SS + rr * SS * math.cos(a), 128 * SS + rr * SS * math.sin(a)))
	d.polygon(star, fill=CT_COIN_MARK)
	coin.resize((cs, cs), Image.LANCZOS).save(os.path.join(CT_OUT, "ct_coin.png"))

	# 4. ct_lock: rounded shackle and body with a keyhole cut through.
	img, d = canvas()
	d.rounded_rectangle(s(64, 28, 192, 150), radius=64 * SS, fill=255)
	d.rounded_rectangle(s(90, 54, 166, 150), radius=38 * SS, fill=0)
	d.rounded_rectangle(s(44, 108, 212, 236), radius=28 * SS, fill=255)
	d.ellipse(s(114, 146, 142, 174), fill=0)
	d.rounded_rectangle(s(121, 158, 135, 202), radius=7 * SS, fill=0)
	save_white(img.resize((cs, cs), Image.LANCZOS), "ct_lock")

	# 5. ct_check: bold, rounded ends.
	img, d = canvas()
	stroke_path(d, [(n * SS, m * SS) for n, m in ((54, 134), (106, 186), (204, 76))], 46 * SS)
	save_white(img.resize((cs, cs), Image.LANCZOS), "ct_check")

	# 6. ct_backArrow: bold left arrow, rounded ends.
	img, d = canvas()
	stroke = 50 * SS
	tip, head = (52 * SS, 128 * SS), 70 * SS
	stroke_path(d, [(tip[0] + head, tip[1] - head), tip, (tip[0] + head, tip[1] + head)], stroke)
	stroke_path(d, [tip, (206 * SS, 128 * SS)], stroke)
	save_white(img.resize((cs, cs), Image.LANCZOS), "ct_backArrow")

	# 7. ct_chevron: pointing up, with its own blurred copy behind at 50% as a glow.
	img, d = canvas()
	stroke_path(d, [(n * SS, m * SS) for n, m in ((68, 164), (128, 104), (188, 164))], 40 * SS)
	shape = img.resize((cs, cs), Image.LANCZOS)
	halo = shape.filter(ImageFilter.GaussianBlur(12)).point(lambda v: v // 2)
	save_white(ImageChops.screen(shape, halo), "ct_chevron")

	# 8. ct_beam: opaque centre column fading to both sides and toward the top.
	bw, bh = 64, 256
	pixels = []
	for y in range(bh):
		v = y / (bh - 1)
		v = v * v * (3 - 2 * v)
		for x in range(bw):
			h = max(0.0, 1.0 - max(0.0, abs(x + 0.5 - bw / 2) - 0.5) / (bw / 2 - 0.5))
			pixels.append(round(255 * h * h * (3 - 2 * h) * v))
	beam = Image.new("L", (bw, bh))
	beam.putdata(pixels)
	save_white(beam, "ct_beam")

	# 9. ct_roundRect: 9-slice centre Rect.new(16, 16, 112, 112).
	img, d = canvas(128, 128)
	d.rounded_rectangle((0, 0, 128 * SS - 1, 128 * SS - 1), radius=CT_ROUND_RADIUS * SS, fill=255)
	save_white(img.resize((128, 128), Image.LANCZOS), "ct_roundRect")


if __name__ == "__main__":
	import sys

	if sys.argv[1:] == ["clear-tide"]:
		clear_tide()
	elif sys.argv[1:] == ["clear-tide-icons"]:
		clear_tide_icons()
	else:
		main()
