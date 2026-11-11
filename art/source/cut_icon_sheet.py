"""Cuts the Studio icon sheet (StarterGui.IconSheet: the 3D models the UI shows, framed like
ToolModels.showIn, on magenta, six per page) out of a screenshot into one transparent PNG per model.

Run: python cut_icon_sheet.py <screenshot.png> <page>   (page 0, 1, ...)
The screenshot: snap_studio.ps1 -Out <png> (the Studio window only). Writes art/ui/renders/<Name>.png.
"""
import os
import sys

from PIL import Image

# The sheet's layout and order (the Studio script builds it the same way). Three columns keep the
# page clear of Studio's view gizmo in the viewport's top-right corner.
CELL, GAP, COLS, ROWS = 256, 8, 3, 2
NAMES = [
	"Spoon", "Cup", "Bucket", "Bathtub", "KiddiePool", "SwimmingPool", "CargoShip", "TheMoon",
	"WaterGun", "GardenHose", "HeatGloves", "IcePick", "JetpackTank", "CloudNet",
	"BackpackTank", "BigTank", "TwinTanks", "InsulatedTank", "CloudBag",
	"FireTruck", "Tanker", "SnowcatTanker", "WaterBomber",
	"Pump", "WaterTower", "Pipeline", "RainMachine",
	"Helper", "Lifeguard", "Firefighter", "Plumber",
]
OUT = os.path.join(os.path.dirname(__file__), "..", "ui", "renders")


def magenta(r, g, b):
	"""How much a pixel looks like the key: 1 on the background, ~0 on the model."""
	return (min(r, b) - g) / 255 if abs(r - b) < 60 else 0.0


def main():
	path, page = sys.argv[1], int(sys.argv[2])
	names = NAMES[page * COLS * ROWS : (page + 1) * COLS * ROWS]
	shot = Image.open(path).convert("RGB")
	px = shot.load()
	w, h = shot.size
	xs, ys = [], []
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			r, g, b = px[x, y]
			if r > 240 and g < 15 and b > 240:
				xs.append(x)
				ys.append(y)
	if not xs:
		sys.exit(f"No magenta sheet in {path}")
	left, top, right, bottom = min(xs), min(ys), max(xs) + 1, max(ys) + 1
	scale = (right - left) / (COLS * CELL + (COLS + 1) * GAP)
	print(f"{path}: sheet at {left},{top} to {right},{bottom}, scale {scale:.3f}")
	os.makedirs(OUT, exist_ok=True)
	key = (255, 0, 255)
	for i, name in enumerate(names):
		col, row = i % COLS, i // COLS
		x0 = left + round((GAP + col * (CELL + GAP)) * scale)
		y0 = top + round((GAP + row * (CELL + GAP)) * scale)
		size = round(CELL * scale)
		cell = shot.crop((x0, y0, x0 + size, y0 + size))
		out = Image.new("RGBA", cell.size)
		src, dst = cell.load(), out.load()
		for y in range(size):
			for x in range(size):
				r, g, b = src[x, y]
				m = magenta(r, g, b)
				if m > 0.75:
					continue  # background
				a = 1.0 if m < 0.35 else (0.75 - m) / 0.4
				# Take the key's share back out of an edge pixel.
				c = [min(255, max(0, round((v - (1 - a) * k) / a))) for v, k in zip((r, g, b), key)]
				dst[x, y] = (c[0], c[1], c[2], round(a * 255))
		out.save(os.path.join(OUT, name + ".png"))
	print(f"Saved {', '.join(names)} to {os.path.abspath(OUT)}")


if __name__ == "__main__":
	main()
