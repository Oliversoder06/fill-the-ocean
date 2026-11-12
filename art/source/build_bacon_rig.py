"""The bacon-hair (story villain) from the real rig: Studio's OBJ export of Workspace.bacon rig
(art/models/story/bacon_rig.obj + Handle1_diff.png, its one texture with the face, hair, shirt and
pants), and the fat one that drank the ocean, made from those same meshes.

Run headless (Blender 5.2):
    blender -b --factory-startup --python art/source/build_bacon.py -- <story_dir>
Writes <story_dir>/BaconHair.glb (the rig as exported, set up as a model), BaconHairFat.glb and
renders/*.png.

The OBJ is in Roblox world space (studs, +Y up) where the rig stood, facing -X. Both models are
moved to the origin (feet on the ground, centred) and turned to face -Z, Roblox's front; the GLB
comes out in Roblox coordinates (Blender (x, -z, y) <-> Roblox (x, y, z)). Parts, matched to the rig
by position (art/models/story/bacon_rig.parts.json): Handle1 hair, BaconRig6 head, BaconRig5 torso,
BaconRig3 right arm, BaconRig4 left arm, BaconRig1 right leg, BaconRig2 left leg.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

NAMES = {
	"Handle1": "Hair",
	"BaconRig6": "Head",
	"BaconRig5": "Torso",
	"BaconRig3": "RightArm",
	"BaconRig4": "LeftArm",
	"BaconRig1": "RightLeg",
	"BaconRig2": "LeftLeg",
}

# The fat one, in studs (the rig is 5.25 tall, its torso 2 wide).
BALL_RADIUS = 2.3
BALL_SUBDIVISIONS = 2  # 14k triangles; 3 makes 56k, past Roblox's ~20k per mesh
BALL_DEPTH_STRETCH = 2.0  # the torso is made deeper before rounding: its shirt print is magnified less
HEAD_SINK = 0.35  # how far the head sits into the ball
ARM_OUT = 145  # degrees an arm swings out from hanging down (flailing up as he rolls)
ARM_TWIST = 90  # degrees each arm turns about its own length first, so the hands show as fists
ARM_TILT = 18  # degrees the arms lean forward
ARM_SINK = 0.35  # studs of the arm's shoulder inside the ball
ARM_FROM = 0.35  # how high on the ball the shoulders sit (0 = equator, 1 = top)
LEG_SQUASH = 1.0  # legs keep this much of their height (their top half is inside the ball)
LEG_SPREAD = 0.55  # studs each foot sits off the middle
LEG_FORWARD = 1.2  # studs the feet poke out in front
PAD_STEPS = 24  # texels each texture island's edge colour is grown into the gaps around it


def padded_texture(src, dst):
	"""The rig's texture with its transparent gaps (between the texture islands) filled by growing
	each island's edge colours outward, made opaque. Filtering near an island edge (much more of it
	on the stretched ball) then samples the island's own colour, not the grey gap: no dark streaks."""
	img = bpy.data.images.load(src)
	w, h = img.size
	px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
	filled = px[:, :, 3] > 0.5
	col = np.where(filled[:, :, None], px[:, :, :3], 0)
	for _ in range(PAD_STEPS):
		total = np.zeros_like(col)
		count = np.zeros((h, w), dtype=np.float32)
		for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			shifted = np.roll(np.roll(filled, dy, 0), dx, 1)
			total += np.where(shifted[:, :, None], np.roll(np.roll(col, dy, 0), dx, 1), 0)
			count += shifted
		grow = (~filled) & (count > 0)
		col[grow] = total[grow] / count[grow][:, None]
		filled = filled | grow
	out = np.ones((h, w, 4), dtype=np.float32)
	out[:, :, :3] = col
	padded = bpy.data.images.new("BaconHairTexture", w, h, alpha=False)
	padded.pixels = out.ravel().tolist()
	padded.filepath_raw = dst
	padded.file_format = "PNG"
	padded.save()
	bpy.data.images.remove(img)
	return padded


def use_texture(obs, image):
	"""Every part's material shows `image`, opaque (the rig's alpha only marked the unused gaps)."""
	for ob in obs.values():
		for m in ob.data.materials:
			nodes = m.node_tree.nodes
			for node in nodes:
				if node.type == "TEX_IMAGE":
					node.image = image
			bsdf = nodes.get("Principled BSDF")
			if bsdf:
				for link in list(bsdf.inputs["Alpha"].links):
					m.node_tree.links.remove(link)
				bsdf.inputs["Alpha"].default_value = 1.0
			m.surface_render_method = "DITHERED"


def objects():
	return {ob.name: ob for ob in bpy.context.scene.objects if ob.type == "MESH"}


def bounds(obs):
	pts = [ob.matrix_world @ v.co for ob in obs for v in ob.data.vertices]
	lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	return lo, hi


def apply(ob):
	"""Bakes an object's transform into its mesh (GLB parts with no transforms, like the place's)."""
	bpy.context.view_layer.update()  # location / rotation / scale reach matrix_world only on update
	ob.data.transform(ob.matrix_world)
	ob.matrix_world = Matrix.Identity(4)


def set_origin(ob, point):
	"""Moves an object's origin to `point` (world) without moving its mesh."""
	ob.data.transform(Matrix.Translation(-(ob.matrix_world.inverted() @ point)))
	ob.matrix_world = ob.matrix_world @ Matrix.Translation(ob.matrix_world.inverted() @ point)


def import_rig(obj_path):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.wm.obj_import(filepath=obj_path, forward_axis="NEGATIVE_Z", up_axis="Y", use_split_objects=True, use_split_groups=True)
	obs = objects()
	missing = set(NAMES) - set(obs)
	assert not missing, f"OBJ is missing groups {missing} (got {sorted(obs)})"
	for old, new in NAMES.items():
		obs[old].name = new
		obs[old].data.name = new
	obs = objects()
	# To the origin, facing -Z: the rig looks along Roblox -X = Blender -X; Roblox -Z = Blender +Y.
	lo, hi = bounds(obs.values())
	foot = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
	turn = Matrix.Rotation(math.radians(-90), 4, "Z") @ Matrix.Translation(-foot)
	for ob in obs.values():
		ob.matrix_world = turn @ ob.matrix_world
		apply(ob)
	return objects()


def check_front(obs):
	"""The face (dark eyes and mouth in the texture) must be on the head's +Y side, Roblox -Z: the
	head's polygons are grouped by the side they face, and the side whose UV area holds the dark
	face pixels is the front."""
	head = obs["Head"]
	img = head.data.materials[0].node_tree.nodes["Image Texture"].image
	w, h = img.size
	px = img.pixels[:]
	uv = head.data.uv_layers.active.data
	dark = {}
	steps = 12
	for poly in head.data.polygons:
		n = poly.normal
		side = max(("+x", n.x), ("-x", -n.x), ("+y", n.y), ("-y", -n.y), ("+z", n.z), ("-z", -n.z), key=lambda t: t[1])[0]
		corners = [uv[i].uv.copy() for i in poly.loop_indices]
		# Sample each fan triangle of the polygon on a barycentric grid: a polygon's own texels only.
		for k in range(1, len(corners) - 1):
			a, b, c = corners[0], corners[k], corners[k + 1]
			for i in range(steps + 1):
				for j in range(steps + 1 - i):
					p = a + (b - a) * (i / steps) + (c - a) * (j / steps)
					x, y = min(w - 1, max(0, int(p.x * w))), min(h - 1, max(0, int(p.y * h)))
					r, g, bl, al = px[(y * w + x) * 4 : (y * w + x) * 4 + 4]
					if al > 0.5 and 0.3 * r + 0.59 * g + 0.11 * bl < 0.2:
						dark[side] = dark.get(side, 0) + 1
	front = max(dark, key=dark.get) if dark else None
	assert front == "+y", f"dark face samples by side: {dark}; the rig isn't facing -Z"
	print(f"FRONT OK: the face is on Roblox -Z (dark samples by side {dark})")


def check_ball(ball, centre):
	"""Every ball face points out and every normal is radial, or Roblox shows see-through slits and
	shading ripples as it rolls."""
	me = ball.data
	inward = sum(1 for p in me.polygons if p.normal.dot(p.center - centre) <= 0)
	worst = 0.0
	for loop in me.loops:
		radial = (me.vertices[loop.vertex_index].co - centre).normalized()
		worst = max(worst, math.degrees(loop.normal.angle(radial)))
	assert inward == 0, f"{inward} ball faces point inward"
	assert worst < 2, f"a ball normal is {worst:.1f} degrees off radial"
	print(f"BALL OK: {len(me.polygons)} faces all point out, normals within {worst:.2f} degrees of radial")


def fatten(obs):
	torso, head, hair = obs["Torso"], obs["Head"], obs["Hair"]
	# Weld the torso's box faces (smooth normals across the old edges, no seam lines on the ball).
	bm = bmesh.new()
	bm.from_mesh(torso.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(torso.data)
	bm.free()
	tlo, thi = bounds([torso])
	torso.scale = (1, BALL_DEPTH_STRETCH, 1)
	torso.location = (0, -(tlo.y + thi.y) / 2 * (BALL_DEPTH_STRETCH - 1), 0)
	apply(torso)
	tlo, thi = bounds([torso])
	# The ball: the real torso, subdivided (UVs follow) and cast round, so the shirt wraps it.
	sub = torso.modifiers.new("Sub", "SUBSURF")
	sub.subdivision_type = "SIMPLE"
	sub.levels = sub.render_levels = BALL_SUBDIVISIONS
	set_origin(torso, (tlo + thi) / 2)
	cast = torso.modifiers.new("Cast", "CAST")
	cast.cast_type = "SPHERE"
	cast.factor = 1.0
	bpy.context.view_layer.objects.active = torso
	torso.select_set(True)
	for m in ("Sub", "Cast"):
		bpy.ops.object.modifier_apply(modifier=m)
	blo, bhi = bounds([torso])
	size = bhi - blo
	torso.scale = (2 * BALL_RADIUS / size.x, 2 * BALL_RADIUS / size.y, 2 * BALL_RADIUS / size.z)
	torso.location = (0, 0, BALL_RADIUS)
	apply(torso)
	for poly in torso.data.polygons:
		poly.use_smooth = True
	# The imported normals don't survive rounding (ripples, inward patches): use the sphere's own.
	centre = Vector((0, 0, BALL_RADIUS))
	bm = bmesh.new()
	bm.from_mesh(torso.data)
	bm.faces.ensure_lookup_table()
	inward = [f for f in bm.faces if f.normal.dot(f.calc_center_median() - centre) < 0]
	bmesh.ops.reverse_faces(bm, faces=inward, flip_multires=False)
	bm.to_mesh(torso.data)
	bm.free()
	torso.data.normals_split_custom_set_from_vertices([(v.co - centre).normalized() for v in torso.data.vertices])
	check_ball(torso, centre)
	torso.name = torso.data.name = "Belly"

	# Head and hair as they were, sitting on top of the ball.
	hlo, _ = bounds([head])
	lift = 2 * BALL_RADIUS - HEAD_SINK - hlo.z
	for ob in (head, hair):
		ob.location.z += lift
		apply(ob)

	# Arms: hinge at the shoulder (top of the arm), swing out and up, set on the ball's sides.
	for name, side in (("RightArm", 1), ("LeftArm", -1)):
		arm = obs[name]
		alo, ahi = bounds([arm])
		x_side = 1 if (alo.x + ahi.x) > 0 else -1  # which side the arm is on now
		shoulder = Vector(((alo.x + ahi.x) / 2, (alo.y + ahi.y) / 2, ahi.z))
		set_origin(arm, shoulder)
		up = math.asin(ARM_FROM)
		arm.location = (x_side * (BALL_RADIUS * math.cos(up) - ARM_SINK), 0, BALL_RADIUS + BALL_RADIUS * math.sin(up))
		# Twist about its length first, then swing out, then lean forward (Blender's ZYX order).
		arm.rotation_mode = "ZYX"
		arm.rotation_euler = (math.radians(ARM_TILT), math.radians(-x_side * ARM_OUT), math.radians(x_side * ARM_TWIST))
		apply(arm)
		arm.name = arm.data.name = name

	# Legs: squashed to stubs, poking out at the front of the ball's bottom.
	for name in ("RightLeg", "LeftLeg"):
		leg = obs[name]
		llo, lhi = bounds([leg])
		x_side = 1 if (llo.x + lhi.x) > 0 else -1
		set_origin(leg, Vector(((llo.x + lhi.x) / 2, (llo.y + lhi.y) / 2, llo.z)))
		leg.scale = (1, 1, LEG_SQUASH)
		leg.location = (x_side * LEG_SPREAD, LEG_FORWARD, 0)
		apply(leg)
	return objects()


def export(path):
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, use_selection=True, export_apply=True)


def render(path, eye, target, lens=50):
	s = bpy.context.scene
	cd = bpy.data.cameras.new("ReviewCam")
	cd.lens = lens
	cam = bpy.data.objects.new("ReviewCam", cd)
	s.collection.objects.link(cam)
	s.camera = cam
	cam.location = eye
	cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
	s.render.engine = "BLENDER_WORKBENCH"
	s.render.resolution_x, s.render.resolution_y = 800, 800
	s.view_settings.view_transform = "Standard"
	sh = s.display.shading
	sh.light = "STUDIO"
	sh.color_type = "TEXTURE"
	sh.show_shadows = False
	sh.show_cavity = False  # its edge darkening reads as ripples on the ball that aren't in the mesh
	if s.world is None:
		s.world = bpy.data.worlds.new("Review")
	s.world.color = (0.75, 0.85, 0.95)
	s.render.filepath = path
	bpy.ops.render.render(write_still=True)
	bpy.data.objects.remove(cam, do_unlink=True)


def views(prefix, out, height):
	"""Front (Roblox -Z = Blender +Y), front three-quarter, side and back, framed on `height`."""
	c = (0, 0, height * 0.5)
	d = height * 2.6
	render(os.path.join(out, f"{prefix}_front.png"), (0, d, height * 0.55), c)
	render(os.path.join(out, f"{prefix}_threequarter.png"), (d * 0.7, d * 0.75, height * 0.75), c)
	render(os.path.join(out, f"{prefix}_side.png"), (d, 0, height * 0.55), c)
	render(os.path.join(out, f"{prefix}_back.png"), (0, -d, height * 0.6), c)


def report(label, obs):
	lo, hi = bounds(obs.values())
	tris = {n: sum(len(p.vertices) - 2 for p in ob.data.polygons) for n, ob in obs.items()}
	print(f"{label}: size {tuple(round(v, 2) for v in hi - lo)} min {tuple(round(v, 2) for v in lo)} tris {tris}")


def main():
	story = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
	out = os.path.join(story, "renders")
	os.makedirs(out, exist_ok=True)
	obj_path = os.path.join(story, "bacon_rig.obj")

	obs = import_rig(obj_path)
	check_front(obs)
	texture = padded_texture(os.path.join(story, "Handle1_diff.png"), os.path.join(story, "BaconHairTexture.png"))
	use_texture(obs, texture)
	report("BaconHair", obs)
	export(os.path.join(story, "BaconHair.glb"))
	views("BaconHair", out, bounds(obs.values())[1].z)

	obs = fatten(import_rig(obj_path))
	texture = padded_texture(os.path.join(story, "Handle1_diff.png"), os.path.join(story, "BaconHairTexture.png"))
	use_texture(obs, texture)
	report("BaconHairFat", obs)
	export(os.path.join(story, "BaconHairFat.glb"))
	views("BaconHairFat", out, bounds(obs.values())[1].z)
	print("BACON DONE")


if __name__ == "__main__":
	main()
