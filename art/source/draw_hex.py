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


if __name__ == "__main__":
	main()
