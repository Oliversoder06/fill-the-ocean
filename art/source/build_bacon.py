"""The bacon-hair (story villain): an exact rebuild of the placeholder in the place, and the fat one
that drank the ocean (a ball you can roll), from the same parts.

Run headless (Blender 5.2):
    blender -b --factory-startup --python art/source/build_bacon.py -- <out_dir> <face.png>
<face.png>: Roblox's own default face (the Head's Decal is rbxasset://textures/face.png; it ships
in the Roblox install under content/textures/face.png).

Source of truth: art/models/story/BaconHair.parts.json, read from ReplicatedStorage.Story.BaconHair
(every part's size, CFrame, colour, material). Both models are built in Roblox space (studs, +Y up,
front -Z) and converted to Blender (x, -z, y) so the +Y-up GLB comes out in Roblox coordinates:
import it and every part lands where the place's part is. One mesh per part, named like the part.
Writes <out_dir>/BaconHair.glb, BaconHairFat.glb, FaceSkin.png and renders/*.png.
"""
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
PARTS = os.path.join(HERE, "..", "models", "story", "BaconHair.parts.json")

# The fat one: a ball body (shirt above PANTS_LINE, pants below), the original head and hair on top.
FAT_RADIUS = 66  # studs: twice the original torso's half-width and then some; he drank an ocean
PANTS_LINE = 36  # studs above the ground where the shirt ends
HEAD_SINK = 8  # studs the head sits into the ball
ARM_FROM = 25  # degrees above the ball's equator where the arms leave it
ARM_RAISE = 40  # degrees the arms point up from horizontal (flailing as he rolls)
SLEEVE = (30, 36, 30)
HAND = (30, 15, 30)
ARM_SINK = 10  # studs of each sleeve inside the ball
FOOT = (30, 26, 30)
FOOT_X = 20
FOOT_Z = -40  # feet poke out at the front of the ball's bottom


def srgb_to_linear(c):
	c = c / 255
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rb2bl(p):
	"""Roblox (x, y, z) to Blender, so a +Y-up glTF export gives back Roblox coordinates."""
	return Vector((p[0], -p[2], p[1]))


def transform(cf, local):
	"""A CFrame's components (x, y, z, R00..R22) applied to a local point."""
	x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf
	lx, ly, lz = local
	return (x + r00 * lx + r01 * ly + r02 * lz, y + r10 * lx + r11 * ly + r12 * lz, z + r20 * lx + r21 * ly + r22 * lz)


def rot_z(degrees, at):
	a = math.radians(degrees)
	c, s = math.cos(a), math.sin(a)
	return [at[0], at[1], at[2], c, -s, 0, s, c, 0, 0, 0, 1]


_materials = {}


def material(rgb, name):
	key = tuple(rgb)
	if key in _materials:
		return _materials[key]
	m = bpy.data.materials.new(name)
	lin = [srgb_to_linear(v) for v in rgb]
	m.use_nodes = True
	m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*lin, 1)
	m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
	m.diffuse_color = (*lin, 1)
	_materials[key] = m
	return m


def face_material(face_png, skin_rgb, out_dir):
	"""Roblox's face composited onto the skin colour (opaque), for the head's front."""
	face = bpy.data.images.load(face_png)
	w, h = face.size
	px = np.array(face.pixels[:], dtype=np.float32).reshape(-1, 4)
	skin = np.array([v / 255 for v in skin_rgb], dtype=np.float32)
	a = px[:, 3:4]
	out = np.ones_like(px)
	out[:, :3] = px[:, :3] * a + skin * (1 - a)
	img = bpy.data.images.new("FaceSkin", w, h, alpha=False)
	img.pixels = out.ravel().tolist()
	img.filepath_raw = os.path.join(out_dir, "FaceSkin.png")
	img.file_format = "PNG"
	img.save()
	m = bpy.data.materials.new("Face")
	m.use_nodes = True
	nodes = m.node_tree.nodes
	tex = nodes.new("ShaderNodeTexImage")
	tex.image = img
	m.node_tree.links.new(tex.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
	nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
	m.diffuse_color = (*[srgb_to_linear(v) for v in skin_rgb], 1)
	return m


# Box faces as (corner indices, outward axis); corners are (±x, ±y, ±z) in bit order x, y, z.
BOX_FACES = [
	((0, 2, 6, 4), "-x"), ((1, 5, 7, 3), "+x"),
	((0, 4, 5, 1), "-y"), ((2, 3, 7, 6), "+y"),
	((0, 1, 3, 2), "-z"), ((4, 6, 7, 5), "+z"),
]


def box(name, size, cf, mat, front_mat=None):
	"""A Roblox block part: `size` along its own axes at CFrame `cf`. `front_mat` paints its -Z face
	(the Front a Decal sits on), upright when seen from the front."""
	hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
	local = [((hx if i & 1 else -hx), (hy if i & 2 else -hy), (hz if i & 4 else -hz)) for i in range(8)]
	bm = bmesh.new()
	verts = [bm.verts.new(rb2bl(transform(cf, p))) for p in local]
	uv = bm.loops.layers.uv.new("UVMap")
	for idx, axis in BOX_FACES:
		f = bm.faces.new([verts[i] for i in idx])
		f.material_index = 1 if (front_mat and axis == "-z") else 0
		for loop in f.loops:
			lx, ly, _ = local[verts.index(loop.vert)]
			# Seen from the front the character's left (+x) is on the viewer's left: u runs toward -x.
			loop[uv].uv = ((hx - lx) / (2 * hx), (ly + hy) / (2 * hy))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	mesh.materials.append(mat)
	if front_mat:
		mesh.materials.append(front_mat)
	ob = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(ob)
	return ob


def ball_part(name, centre, radius, keep_above, cut_y, mat):
	"""The part of a ball above (or below) the height `cut_y`, smooth shaded."""
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=32, radius=radius)
	bmesh.ops.translate(bm, verts=bm.verts, vec=rb2bl(centre))
	geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
	bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, cut_y), plane_no=(0, 0, 1), clear_inner=keep_above, clear_outer=not keep_above)
	for f in bm.faces:
		f.smooth = True
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	mesh.materials.append(mat)
	ob = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(ob)
	return ob


def unique_names(parts):
	"""Repeated part names (HairSide, BaconStrip, Fringe) get a number so every mesh is findable."""
	seen, total = {}, {}
	for p in parts:
		total[p["name"]] = total.get(p["name"], 0) + 1
	for p in parts:
		n = p["name"]
		if total[n] > 1:
			seen[n] = seen.get(n, 0) + 1
			p["mesh"] = f"{n}{seen[n]}"
		else:
			p["mesh"] = n
	return parts


def build_original(parts, face_mat):
	objs = []
	for p in parts:
		front = face_mat if any(f["face"] == "Front" for f in p["faces"]) else None
		objs.append(box(p["mesh"], p["size"], p["cframe"], material(p["color"], p["name"]), front))
	return objs


def build_fat(parts, face_mat):
	by = {p["name"]: p for p in parts}
	head = by["Head"]
	centre = (0, FAT_RADIUS, 0)
	lift = (2 * FAT_RADIUS - HEAD_SINK + head["size"][1] / 2) - head["cframe"][1]
	objs = [
		ball_part("Belly", centre, FAT_RADIUS, True, PANTS_LINE, material(by["Torso"]["color"], "Torso")),
		ball_part("Pants", centre, FAT_RADIUS, False, PANTS_LINE, material(by["LeftLeg"]["color"], "LeftLeg")),
	]
	# The head and every hair piece exactly as on the original, lifted onto the ball.
	for p in parts:
		if p["name"] in ("Head", "HairCap", "HairBack", "HairSide", "BaconStrip", "Fringe"):
			cf = list(p["cframe"])
			cf[1] += lift
			front = face_mat if any(f["face"] == "Front" for f in p["faces"]) else None
			objs.append(box(p["mesh"], p["size"], cf, material(p["color"], p["name"]), front))
	# Arms: sleeve and hand leave the ball ARM_FROM up its side and point ARM_RAISE up.
	for side, label in ((1, "Right"), (-1, "Left")):
		up = math.radians(ARM_FROM)
		shoulder = (side * FAT_RADIUS * math.cos(up), FAT_RADIUS + FAT_RADIUS * math.sin(up), 0)
		raise_ = math.radians(ARM_RAISE)
		d = (side * math.cos(raise_), math.sin(raise_), 0)
		turn = -side * (90 - ARM_RAISE)  # local +Y onto d
		sleeve_at = tuple(shoulder[i] + d[i] * (SLEEVE[1] / 2 - ARM_SINK) for i in range(3))
		hand_at = tuple(sleeve_at[i] + d[i] * (SLEEVE[1] / 2 + HAND[1] / 2) for i in range(3))
		objs.append(box(f"{label}Sleeve", SLEEVE, rot_z(turn, sleeve_at), material(by[f"{label}Sleeve"]["color"], f"{label}Sleeve")))
		objs.append(box(f"{label}Hand", HAND, rot_z(turn, hand_at), material(by[f"{label}Hand"]["color"], f"{label}Hand")))
		objs.append(box(f"{label}Leg", FOOT, rot_z(0, (side * FOOT_X, FOOT[1] / 2, FOOT_Z)), material(by[f"{label}Leg"]["color"], f"{label}Leg")))
	return objs


def export(objs, path):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, use_selection=True, export_apply=True)


def render(objs, path, eye, target):
	s = bpy.context.scene
	for o in s.objects:
		if o.type == "MESH":
			o.hide_render = o not in objs
	cd = bpy.data.cameras.new("ReviewCam")
	cd.lens = 40
	cd.clip_end = 5000
	cam = bpy.data.objects.new("ReviewCam", cd)
	s.collection.objects.link(cam)
	s.camera = cam
	cam.location = rb2bl(eye)
	cam.rotation_euler = (rb2bl(target) - rb2bl(eye)).to_track_quat("-Z", "Y").to_euler()
	s.render.engine = "BLENDER_WORKBENCH"
	s.render.resolution_x, s.render.resolution_y = 900, 900
	s.view_settings.view_transform = "Standard"
	sh = s.display.shading
	sh.light = "STUDIO"
	sh.color_type = "TEXTURE"
	sh.show_shadows = True
	sh.shadow_intensity = 0.3
	if s.world is None:
		s.world = bpy.data.worlds.new("Review")
	s.world.color = (0.75, 0.85, 0.95)
	s.render.filepath = path
	bpy.ops.render.render(write_still=True)
	bpy.data.objects.remove(cam, do_unlink=True)


def main():
	out_dir, face_png = sys.argv[sys.argv.index("--") + 1 :][:2]
	os.makedirs(os.path.join(out_dir, "renders"), exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	data = json.load(open(PARTS))
	parts = unique_names(data["parts"])
	skin = next(p for p in parts if p["name"] == "Head")["color"]
	face_mat = face_material(face_png, skin, out_dir)

	original = build_original(parts, face_mat)
	export(original, os.path.join(out_dir, "BaconHair.glb"))
	render(original, os.path.join(out_dir, "renders", "BaconHair_front.png"), (150, 120, -330), (0, 85, 0))
	count = len(original)
	for o in original:  # the fat one reuses the part names
		mesh = o.data
		bpy.data.objects.remove(o, do_unlink=True)
		bpy.data.meshes.remove(mesh)

	fat = build_fat(parts, face_mat)
	export(fat, os.path.join(out_dir, "BaconHairFat.glb"))
	render(fat, os.path.join(out_dir, "renders", "BaconHairFat_front.png"), (190, 130, -360), (0, 90, 0))
	render(fat, os.path.join(out_dir, "renders", "BaconHairFat_side.png"), (380, 110, 0), (0, 90, 0))
	render(fat, os.path.join(out_dir, "renders", "BaconHairFat_back.png"), (-170, 140, 330), (0, 90, 0))
	print("BACON DONE", count, "parts,", len(fat), "fat parts:", ", ".join(o.name for o in fat))


if __name__ == "__main__":
	main()
