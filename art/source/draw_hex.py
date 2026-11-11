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


# ct_chevronWide: the guide lane's ground chevron, a wide flat "^" across the lane (apex at the top
# centre), white with its blurred copy behind at 50% as a glow; the margin keeps the blur unclipped.
def clear_tide_lane():
	from PIL import ImageChops, ImageFilter

	os.makedirs(CT_OUT, exist_ok=True)
	cw, ch, margin, drop = 512, 256, 20, 72  # drop: the arms' vertical thickness (~60 px across)
	img = Image.new("L", (cw * SS, ch * SS), 0)
	d = ImageDraw.Draw(img)
	top, bottom = margin, ch - margin
	points = [
		(margin, bottom - drop),
		(cw / 2, top),
		(cw - margin, bottom - drop),
		(cw - margin, bottom),
		(cw / 2, top + drop),
		(margin, bottom),
	]
	d.polygon([(x * SS, y * SS) for x, y in points], fill=255)
	shape = img.resize((cw, ch), Image.LANCZOS)
	halo = shape.filter(ImageFilter.GaussianBlur(14)).point(lambda v: v // 2)
	out = Image.new("RGBA", (cw, ch), (255, 255, 255, 0))
	out.putalpha(ImageChops.screen(shape, halo))
	out.save(os.path.join(CT_OUT, "ct_chevronWide.png"))


CT_LANE_GLOW = (0xFF, 0xE4, 0x5C)
CT_LANE_CORE = (0xFF, 0xFA, 0xD8)


# ct_laneTile: the guide lane Beam's tile, drawn with U (x) along the lane, V (y) across. Rails on the
# top and bottom edges run off both sides so the tile repeats along U; one filled chevron points to +U.
def clear_tide_lane_tile():
	from PIL import ImageChops, ImageFilter

	os.makedirs(CT_OUT, exist_ok=True)
	size = 512
	rail_y, rail_core = 36, 26
	chev_top, chev_bottom, chev_depth, chev_thick = 64, 448, 185, 135  # thick: horizontal, ~100 px across the arm
	apex = size / 2 + (chev_depth + chev_thick) / 2

	# Three tiles wide so the rails' blur wraps cleanly; the middle one is kept.
	def canvas():
		return Image.new("L", (size * 3 * SS, size * SS), 0)

	def rails(grow):
		img = canvas()
		d = ImageDraw.Draw(img)
		for y in (rail_y, size - rail_y):
			d.rectangle((0, (y - rail_core / 2 - grow) * SS, size * 3 * SS, (y + rail_core / 2 + grow) * SS), fill=255)
		return img

	def chevron(grow):
		img = canvas()
		x0 = size + apex - chev_depth
		points = [
			(x0, chev_top),
			(size + apex, size / 2),
			(x0, chev_bottom),
			(x0 - chev_thick, chev_bottom),
			(size + apex - chev_thick, size / 2),
			(x0 - chev_thick, chev_top),
		]
		ImageDraw.Draw(img).polygon([(x * SS, y * SS) for x, y in points], fill=255, outline=255, width=grow * 2 * SS)
		return img

	def finish(img, blur):
		small = img.resize((size * 3, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(blur))
		return small.crop((size, 0, size * 2, size))

	core = finish(ImageChops.lighter(rails(0), chevron(0)), 7)
	glow = finish(ImageChops.lighter(rails(12), chevron(14)), 26)

	out = Image.new("RGBA", (size, size), CT_LANE_GLOW + (0,))
	out.putalpha(glow.point(lambda v: min(255, round(v * 1.3))))
	top = Image.new("RGBA", (size, size), CT_LANE_CORE + (0,))
	top.putalpha(core)
	# Drawn with U along x; a Beam lays an image's y along its length (top at Start), so it is turned.
	tile = Image.alpha_composite(out, top).transpose(Image.Transpose.ROTATE_270)
	tile.save(os.path.join(CT_OUT, "ct_laneTile.png"))


CT_OL_DARK = (0x14, 0x16, 0x1C)
CT_OL_COIN = (0x7A, 0x4A, 0x00)
CT_OL_WIDTH = 14  # px on the 256 canvas: ~3 px around a 56 px icon on screen
CT_OL_FIT = 0.84  # the art shrinks so its outline fits the canvas
CT_RIM_THICK = 18  # ~4 px on a 110 px hex


# Round 3 (owner, 2026-11-11): every icon gets a darker-hue outline (`_ol`), plus the pin and
# stopwatch for the run panel, a water drop, the hotbar's wave line and a thicker hex rim.
def clear_tide_outlined():
	from PIL import ImageChops

	os.makedirs(CT_OUT, exist_ok=True)
	cs = 256
	big = cs * SS

	def grow(mask, px):
		# Dilate by a disc: the mask shifted around rings from px down to the centre.
		out = mask
		r = px
		while r > 0:
			steps = max(8, round(2 * math.pi * r / SS))
			for i in range(steps):
				a = 2 * math.pi * i / steps
				out = ImageChops.lighter(out, ImageChops.offset(mask, round(r * math.cos(a)), round(r * math.sin(a))))
			r -= 2 * SS
		return out

	def outlined(art, colour, name):
		fit = round(big * CT_OL_FIT)
		placed = Image.new("RGBA", (big, big), (0, 0, 0, 0))
		placed.alpha_composite(art.resize((fit, fit), Image.LANCZOS), ((big - fit) // 2, (big - fit) // 2))
		edge = Image.new("RGBA", (big, big), colour + (0,))
		edge.putalpha(grow(placed.getchannel("A"), CT_OL_WIDTH * SS))
		edge.alpha_composite(placed)
		edge.resize((cs, cs), Image.LANCZOS).save(os.path.join(CT_OUT, name + "_ol.png"))

	def loaded(*path):
		return Image.open(os.path.join(os.path.dirname(__file__), "..", "ui", *path)).convert("RGBA").resize((big, big), Image.LANCZOS)

	def white(mask):
		art = Image.new("RGBA", mask.size, (255, 255, 255, 0))
		art.putalpha(mask)
		return art

	def s(*v):
		return [n * SS for n in v]

	outlined(loaded("clear-tide", "ct_coin.png"), CT_OL_COIN, "ct_coin")
	outlined(loaded("honeycomb", "area_flag.png"), CT_OL_DARK, "ct_flag")
	for name in ("ct_lock", "ct_check", "ct_backArrow"):
		outlined(loaded("clear-tide", name + ".png"), CT_OL_DARK, name)

	# Map pin: a round head tapering to a point, a hole through the head.
	img = Image.new("L", (big, big), 0)
	d = ImageDraw.Draw(img)
	head, cx, cy, tip = 84, 128, 104, 244
	d.ellipse(s(cx - head, cy - head, cx + head, cy + head), fill=255)
	touch = math.asin(head / (tip - cy))
	side = [(cx + head * math.cos(touch) * k, cy + head * math.sin(touch)) for k in (-1, 1)]
	d.polygon([(x * SS, y * SS) for x, y in (side[0], side[1], (cx, tip))], fill=255)
	d.ellipse(s(cx - 34, cy - 34, cx + 34, cy + 34), fill=0)
	outlined(white(img), CT_OL_DARK, "ct_pin")

	# Stopwatch: a full face with its crown; the hands are cut out so the outline colour shows through.
	img = Image.new("L", (big, big), 0)
	d = ImageDraw.Draw(img)
	cx, cy, rad = 128, 146, 104
	d.ellipse(s(cx - rad, cy - rad, cx + rad, cy + rad), fill=255)
	d.rounded_rectangle(s(96, 6, 160, 38), radius=10 * SS, fill=255)
	d.rectangle(s(114, 30, 142, 50), fill=255)
	hand = 22 * SS
	for x, y in ((cx, cy - 70), (cx + 46, cy - 26)):
		d.line(s(cx, cy, x, y), fill=0, width=hand)
		d.ellipse((x * SS - hand / 2, y * SS - hand / 2, x * SS + hand / 2, y * SS + hand / 2), fill=0)
	d.ellipse(s(cx - 20, cy - 20, cx + 20, cy + 20), fill=0)
	outlined(white(img), CT_OL_DARK, "ct_clock")

	# Water drop: a round bottom rising to a point.
	img = Image.new("L", (big, big), 0)
	d = ImageDraw.Draw(img)
	rad, cx, cy, tip = 92, 128, 152, 6
	d.ellipse(s(cx - rad, cy - rad, cx + rad, cy + rad), fill=255)
	touch = math.asin(rad / (cy - tip))
	side = [(cx + rad * math.cos(touch) * k, cy - rad * math.sin(touch)) for k in (-1, 1)]
	d.polygon([(x * SS, y * SS) for x, y in (side[0], side[1], (cx, tip))], fill=255)
	outlined(white(img), CT_OL_DARK, "ct_drop")

	# ct_waveTile: one period of the hotbar's wave, as tall as a slot (2x of 124x104: a slot and its
	# gap), seamless left to right; each slot sits on a crossing. The ends fade in the place.
	tw, th, line, edge = 248, 208, 26, 6
	amp = th / 2 - line / 2 - edge - 4
	wave = Image.new("RGBA", (tw * SS, th * SS), CT_OL_DARK + (0,))
	d = ImageDraw.Draw(wave)
	pts = []
	for i in range(-200, 1401):
		x = tw * i / 1200
		pts.append((x * SS, (th / 2 - amp * math.sin(x / tw * 2 * math.pi)) * SS))
	# Stamped discs, not d.line: its joints leave dark slivers across the white.
	for width, colour in ((line + 2 * edge, CT_OL_DARK), (line, (255, 255, 255))):
		w = width * SS
		for x, y in pts:
			d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=colour + (255,))
	wave = wave.resize((tw, th), Image.LANCZOS)
	wave.save(os.path.join(CT_OUT, "ct_waveTile.png"))

	# ct_hexRim_thick: ct_hexRim three times as wide.
	cx, cy = W * SS / 2, H * SS / 2
	r = (W / 2 - 1) * SS
	apothem = r * math.sqrt(3) / 2

	def inset(px):
		return r * (apothem - px * SS) / apothem

	def rim(d):
		d.polygon(hex_points(cx, cy, inset(CT_RIM_INSET), CORNER * SS * 0.8), fill=255)
		d.polygon(hex_points(cx, cy, inset(CT_RIM_INSET + CT_RIM_THICK), CORNER * SS * 0.6), fill=0)

	white(hexagon(rim)).save(os.path.join(CT_OUT, "ct_hexRim_thick.png"))


if __name__ == "__main__":
	import sys

	if sys.argv[1:] == ["clear-tide"]:
		clear_tide()
	elif sys.argv[1:] == ["clear-tide-icons"]:
		clear_tide_icons()
	elif sys.argv[1:] == ["clear-tide-lane"]:
		clear_tide_lane()
	elif sys.argv[1:] == ["clear-tide-lane-tile"]:
		clear_tide_lane_tile()
	elif sys.argv[1:] == ["clear-tide-outlined"]:
		clear_tide_outlined()
	else:
		main()
