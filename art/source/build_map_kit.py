"""Save the Ocean map kit: buildings, vehicles and terrain pieces that the old stage art does not cover.

Run headless (Blender 5.2):
    blender -b --factory-startup --python art/source/build_map_kit.py -- <out_dir>

Writes <out_dir>/<Name>.glb, <out_dir>/renders/<Name>.png and <out_dir>/kit_report.json.
Conventions match art/manifest.json: 1 unit = 1 stud, front faces -Y, +Z up, origin at the base centre.
Colour is vertex colour (one material per model), shaded by face direction so forms read under flat light.
"""
import json
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

SKILL = os.environ.get(
    "LIHFOLK_BLENDER_SCRIPTS",
    r"C:\Users\lexru\.claude\plugins\cache\lihfolk\lihfolk\2.5.0\skills\roblox-blender-modeling\scripts",
)
sys.path.append(SKILL)
import lihfolk_bpy as lf  # noqa: E402
import lihfolk_curves as lc  # noqa: E402
import lihfolk_house as lh  # noqa: E402

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(os.path.dirname(__file__), "..", "models", "map")


def reset_scene():
    lf.setup_scene()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


H = lc.hex_rgb
INK = H("#1B2A3A")

_GROW = random.Random(7)
_cyl = lh.MeshBuilder.cyl


def _cyl_with_caps(self, p0, p1, r, n, side, cap_in=None, cap_out=None, **kw):
    """lh cylinders need plain colours for their caps; a shade function lends its 'facing up' colour."""
    if cap_in is None and callable(side):
        cap_in = side(Vector(), Vector((0, 0, 1)), Vector())
    # stretch each end a few thousandths along the axis: stacked cylinders overlap instead of sharing cap centres
    p0, p1 = Vector(p0), Vector(p1)
    ax = (p1 - p0).normalized()
    p0, p1 = p0 - ax * _GROW.uniform(0.002, 0.006), p1 + ax * _GROW.uniform(0.002, 0.006)
    return _cyl(self, p0, p1, r, n, side, cap_in=cap_in, cap_out=cap_out, **kw)


lh.MeshBuilder.cyl = _cyl_with_caps
BLACK = (0.0, 0.0, 0.0)


def shade(hexc, top=1.1, bottom=0.68):
    c = H(hexc)
    up = tuple(min(1.0, v * top) for v in c)
    dn = tuple(v * bottom for v in c)
    return lh.by_normal(up, c, dn)


def bxr(b, x0, x1, y0, y1, z0, z1, col):
    """Box by its ranges. Every face grows outward by a few thousandths of a stud, so parts that touch overlap a
    hair instead of sharing vertices (shared vertices get welded on export and leave non-manifold seams)."""
    g = lambda: _GROW.uniform(0.002, 0.006)  # noqa: E731
    b.box((min(x0, x1) - g(), min(y0, y1) - g(), min(z0, z1) - g()), (max(x0, x1) + g(), max(y0, y1) + g(), max(z0, z1) + g()), col)


def bx(b, cx, cy, z0, sx, sy, sz, col):
    """Box by centre x/y, bottom z and size."""
    bxr(b, cx - sx / 2, cx + sx / 2, cy - sy / 2, cy + sy / 2, z0, z0 + sz, col)


FONT = r"C:\Windows\Fonts\ariblk.ttf"


def text_mesh(b, text, front, w, h, fg, depth=0.2, shadow=True):
    """Solid 3D lettering standing on a sign whose front surface is the plane y = front[1], facing -Y.
    front = (x, y, z) centre of the sign face; the text is fitted inside w x h and sunk 0.03 into the board.
    A dark copy just behind and below gives the outlined, cartoon look without textures."""
    cu = bpy.data.curves.new("_txt", "FONT")
    cu.body = text
    cu.font = bpy.data.fonts.load(FONT, check_existing=True)
    cu.align_x, cu.align_y = "CENTER", "CENTER"
    cu.extrude = depth / 2
    cu.resolution_u = 2
    ob = bpy.data.objects.new("_txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(dg).to_mesh()
    src = bmesh.new()
    src.from_mesh(me)
    ob.evaluated_get(dg).to_mesh_clear()
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.curves.remove(cu)
    bmesh.ops.remove_doubles(src, verts=src.verts, dist=1e-5)
    bmesh.ops.triangulate(src, faces=src.faces)
    lo = Vector([min(v.co[i] for v in src.verts) for i in range(3)])
    hi = Vector([max(v.co[i] for v in src.verts) for i in range(3)])
    s = min(w * 0.88 / (hi.x - lo.x), h * 0.72 / (hi.y - lo.y))
    ctr = (lo + hi) / 2
    # text lies in XY facing +Z; rotate +90 deg about X so it reads on an XZ face looking toward -Y
    base = Matrix.Rotation(math.radians(90), 4, "X") @ Matrix.Diagonal((s, s, 1.0, 1)) @ Matrix.Translation(-ctr)
    fx, fy, fz = front
    layers = [((0, 0, 0), fg)]
    if shadow:
        layers.insert(0, ((0.08 * h, 0.06, -0.08 * h), "#1B2A3A"))
    for (dx, dy, dz), hexc in layers:
        tbm = src.copy()
        M = Matrix.Translation((fx + dx, fy - depth / 2 + 0.03 + dy, fz + dz)) @ base
        b.add_bm(tbm, M, shade(hexc, 1.05, 0.8))
    src.free()


def rotx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def roty(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rotz(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def ring(b, centre, axis, R, r, n, col, seg=6):
    """Torus made of n short cylinders (hose coils, wheels' tyres, rims)."""
    centre = Vector(centre)
    ax = Vector(axis).normalized()
    u = ax.orthogonal().normalized()
    w = ax.cross(u)
    pts = [centre + (u * math.cos(2 * math.pi * i / n) + w * math.sin(2 * math.pi * i / n)) * R for i in range(n)]
    for i in range(n):
        p0, p1 = pts[i], pts[(i + 1) % n]
        d = (p1 - p0)
        b.cyl(p0 - d * 0.08, p1 + d * 0.08, r, seg, col, phase=0)


def rock_blob(b, centre, scale, col, rng, subdiv=1, amp=0.18):
    """Jittered icosphere: one faceted rock chunk."""
    tbm = bmesh.new()
    bmesh.ops.create_icosphere(tbm, subdivisions=subdiv, radius=1.0)
    for v in tbm.verts:
        v.co *= 1.0 + rng.uniform(-amp, amp)
    M = Matrix.Translation(Vector(centre)) @ Matrix.Diagonal((*scale, 1))
    b.add_bm(tbm, M, col)


def arch_outline(half_w, wall_h, n=14):
    pts = [(-half_w, 0.0), (-half_w, wall_h)]
    for i in range(1, n):
        a = math.pi - math.pi * i / n
        pts.append((half_w * math.cos(a), wall_h + half_w * math.sin(a)))
    pts += [(half_w, wall_h), (half_w, 0.0)]
    return pts


SIGNS = {}  # model -> list of sign faces (for the preview's text decals): centre (x, y, z) and size (w, h)


# ---------------------------------------------------------------- models
def fire_truck():
    b = lh.MeshBuilder("FireTruck", random.Random(4))
    red, chrome, dark = shade("#E8352B"), shade("#D7DEE4", 1.1, 0.8), shade("#2B2B2E")
    glass = shade("#9AD8F5", 1.05, 0.9)
    bx(b, 0, 0, 1.6, 8.0, 25.0, 1.6, dark)                       # chassis
    bx(b, 0, 4.5, 3.2, 9.0, 16.0, 6.0, red)                       # body
    bx(b, 0, -8.6, 3.2, 9.0, 7.6, 6.8, red)                       # cab
    bx(b, 0, -8.0, 10.0, 8.6, 6.4, 0.6, red)                      # cab roof lip
    bx(b, 0, -12.45, 6.6, 7.8, 0.3, 3.0, glass)                   # windscreen
    for sx in (-1, 1):
        bx(b, sx * 4.55, -9.3, 6.6, 0.3, 4.0, 2.6, glass)         # side windows
        for k in range(3):                                        # lockers
            bx(b, sx * 4.55, -0.5 + k * 5.2, 4.0, 0.3, 4.6, 4.2, shade("#D93028"))
            bx(b, sx * 4.75, -0.5 + k * 5.2, 6.0, 0.2, 2.0, 0.4, chrome)
        bx(b, sx * 4.6, 4.5, 8.3, 0.3, 16.0, 0.6, shade("#FFF1C9"))  # stripe
    bx(b, 0, -12.9, 1.8, 9.2, 0.8, 1.6, chrome)                   # bumper
    for sx in (-1, 1):
        bx(b, sx * 3.0, -12.6, 4.2, 1.6, 0.4, 1.0, shade("#FFF6CC", 1.2, 1.0))  # headlights
    bx(b, -1.6, -8.2, 10.6, 2.4, 1.4, 0.9, shade("#FF5A4E", 1.2, 1.0))  # light bar
    bx(b, 1.6, -8.2, 10.6, 2.4, 1.4, 0.9, shade("#3FA9E0", 1.2, 1.0))
    bx(b, 0, 5.5, 9.2, 6.0, 9.0, 1.6, shade("#3FA9E0"))           # water tank on top
    for sx in (-1, 1):                                            # ladder rails
        bx(b, sx * 1.4, 3.0, 11.0, 0.5, 18.0, 0.5, chrome)
    for k in range(9):
        bx(b, 0, -5.0 + k * 2.0, 11.0, 2.4, 0.35, 0.4, chrome)
    for sx in (-1, 1):
        bx(b, sx * 1.4, 10.5, 9.2, 0.5, 0.5, 1.8, chrome)         # ladder posts
        bx(b, sx * 1.4, -4.5, 10.0, 0.5, 0.5, 1.0, chrome)
    for y in (-8.6, 4.0, 9.5):                                    # wheels
        for sx in (-1, 1):
            b.cyl((sx * 3.6, y, 2.2), (sx * 5.0, y, 2.2), 2.2, 14, dark, cap_in=H("#C9D3DB"), cap_out=H("#2B2B2E"))
    return b


def hydrant():
    b = lh.MeshBuilder("Hydrant", random.Random(5))
    red, yellow = shade("#E8352B"), shade("#FFB23F")
    b.cyl((0, 0, 0), (0, 0, 0.5), 1.45, 12, shade("#B9BEC4"))
    b.cyl((0, 0, 0.5), (0, 0, 3.4), 1.05, 12, red)
    b.cyl((0, 0, 3.4), (0, 0, 3.75), 1.3, 12, yellow)
    b.ico((0, 0, 3.95), (1.05, 1.05, 0.75), yellow, subdiv=2)
    b.cyl((0, 0, 4.5), (0, 0, 5.05), 0.35, 6, yellow)
    for sx in (-1, 1):
        b.cyl((sx * 0.9, 0, 2.5), (sx * 1.7, 0, 2.5), 0.42, 10, red)
        b.cyl((sx * 1.7, 0, 2.5), (sx * 1.9, 0, 2.5), 0.5, 6, yellow)
    b.cyl((0, -0.9, 2.2), (0, -1.75, 2.2), 0.6, 10, red)
    b.cyl((0, -1.75, 2.2), (0, -2.0, 2.2), 0.68, 6, yellow)
    return b


def rock_col(seed_low="#8E6E54", mid="#A8876A", high="#C9AE8E", ledge="#B89A5B", z_hi=200.0):
    lo, mi, hi_, le = H(seed_low), H(mid), H(high), H(ledge)

    def f(c, n, co):
        t = max(0.0, min(1.0, c.z / z_hi))
        base = lh.mix(lo, mi, min(1.0, t * 2)) if t < 0.5 else lh.mix(mi, hi_, (t - 0.5) * 2)
        if n.z > 0.62:
            return le
        if n.z < -0.2:
            return tuple(v * 0.7 for v in base)
        return base
    return f


def spire(b, rng, cx, cy, height, radius, col, rings=7, n=8):
    """Steep faceted peak: jittered rings narrowing to an off-centre summit."""
    lean = Vector((rng.uniform(-0.12, 0.12) * radius, rng.uniform(-0.12, 0.12) * radius, 0))
    verts, faces = [], []
    phase = rng.uniform(0, math.pi)
    for k in range(rings):
        t = k / rings
        r = radius * (1 - t) ** 0.8
        z = height * t - (2.0 if k == 0 else 0.0)
        for j in range(n):
            a = phase + 2 * math.pi * (j + rng.uniform(-0.25, 0.25)) / n
            rr = r * rng.uniform(0.78, 1.12)
            verts.append(Vector((cx + math.cos(a) * rr, cy + math.sin(a) * rr, z + rng.uniform(-0.04, 0.04) * height * (k > 0))) + lean * t)
    base_i = len(verts); verts.append(Vector((cx, cy, -2.0)))
    apex_i = len(verts); verts.append(Vector((cx, cy, height)) + lean)
    for k in range(rings - 1):
        for j in range(n):
            a0, a1 = k * n + j, k * n + (j + 1) % n
            faces += [(a0, a1, a1 + n), (a0, a1 + n, a0 + n)]
    for j in range(n):
        faces.append((base_i, (j + 1) % n, j))
        top = (rings - 1) * n
        faces.append((top + j, top + (j + 1) % n, apex_i))
    b.add(verts, faces, col)


def mountain(name, seed, height, radius):
    rng = random.Random(seed)
    b = lh.MeshBuilder(name, rng)
    col = rock_col(z_hi=height)
    spire(b, rng, 0, 0, height, radius, col)
    for k in range(2):
        a = rng.uniform(0, 2 * math.pi) + k * math.pi
        spire(b, rng, math.cos(a) * radius * 0.55, math.sin(a) * radius * 0.55, height * rng.uniform(0.45, 0.62), radius * 0.62, col, rings=5)
    return b


def tunnel_cliff():
    rng = random.Random(9)
    b = lh.MeshBuilder("TunnelCliff", rng)
    col = rock_col(z_hi=110)
    w, depth, h = 120, 60, 90
    # flat sheer face at y = 0 (front, -Y), body behind it
    tbm = bmesh.new()
    bmesh.ops.create_cube(tbm, size=1.0)
    for v in tbm.verts:
        if v.co.y > 0:   # jitter only the back so the face stays flat
            v.co.x *= 1 + rng.uniform(-0.08, 0.08)
            v.co.z *= 1 + rng.uniform(-0.1, 0.1)
    M = Matrix.Translation((0, depth / 2, h / 2)) @ Matrix.Diagonal((w, depth, h, 1))
    b.add_bm(tbm, M, col)
    # rock chunks on top and sides break the box silhouette
    for k in range(7):
        x = -w / 2 + 8 + k * (w - 16) / 6
        rock_blob(b, (x, depth * 0.45, h - 4 + rng.uniform(0, 8)), (rng.uniform(14, 22), rng.uniform(16, 26), rng.uniform(12, 22)), col, rng, subdiv=1, amp=0.2)
    for sx in (-1, 1):
        rock_blob(b, (sx * (w / 2 + 2), depth * 0.5, h * 0.45), (14, 26, h * 0.5), col, rng, subdiv=1, amp=0.2)
    # stone rim, then the pitch-black opening painted flat on the face
    stone = shade("#6E5644")
    b.outline_xz(arch_outline(17.5, 18.0), -1.4, 0.2, 0.4, stone)
    b.outline_xz(arch_outline(13.0, 16.0), -1.9, -1.2, 0.0, BLACK)
    # keystone and side blocks
    bx(b, 0, -1.5, 18.0 + 15.8, 4.0, 1.4, 4.4, shade("#7E6450"))
    return b


def dam():
    b = lh.MeshBuilder("Dam", random.Random(10))
    conc = shade("#B9BEC4", 1.08, 0.72)
    L, hgt = 100, 16
    # sloped wall: stacked slabs getting thinner, water side at +Y, dry side at -Y
    for k in range(4):
        t = 12 - k * 2.2
        bx(b, 0, 1.5 + k * 0.6, k * 4, L, t, 4.0, conc)
    bx(b, 0, 3.2, hgt, L + 2, 6.5, 1.0, shade("#9AA3AD"))
    for i in range(21):
        bx(b, -L / 2 + i * 5, 0.4, hgt + 1.0, 0.5, 0.5, 2.6, shade("#FF5A4E"))
    bx(b, 0, 0.4, hgt + 3.1, L, 0.4, 0.4, shade("#FF5A4E"))
    # spillway notch with steps
    for k in range(4):
        bx(b, 0, -5.5 - k * 2.2, 0, 14, 2.4, 12 - k * 3.2, shade("#9AA3AD"))
    # control hut
    bx(b, 30, 3.2, hgt + 1.0, 8, 6, 6, shade("#FFF1C9"))
    bx(b, 30, 3.2, hgt + 7.0, 9, 7, 0.8, shade("#2A4A66"))
    bx(b, 30, -0.05, hgt + 1.0, 2.4, 0.3, 4.6, shade("#6B4428"))
    return b


def pump():
    b = lh.MeshBuilder("Pump", random.Random(11))
    bx(b, 0, 0, 0, 14, 14, 0.8, shade("#B9BEC4"))
    b.cyl((0, 3, 0.8), (0, 3, 10.0), 3.6, 16, shade("#3FA9E0"))
    for z in (2.6, 6.2, 9.4):
        b.cyl((0, 3, z), (0, 3, z + 0.6), 3.8, 16, INK)
    b.cyl((0, 3, 10.0), (0, 3, 11.0), 2.0, 12, shade("#9AA7B2"))
    bx(b, -3.6, -3.0, 0.8, 4.4, 4.0, 3.6, shade("#FFB23F"))            # motor
    b.cyl((-1.3, -3.0, 2.6), (1.4, -3.0, 2.6), 1.6, 14, shade("#2B2B2E"))  # flywheel
    b.cyl((0, -0.4, 5.0), (0, -7.0, 5.0), 0.9, 10, shade("#9AA7B2"))  # outlet toward the sea
    b.cyl((0, -6.4, 5.0), (0, -7.4, 5.0), 1.25, 10, INK)
    b.cyl((0, -7.0, 0.8), (0, -7.0, 5.9), 0.9, 10, shade("#9AA7B2"))
    return b


def water_tower():
    b = lh.MeshBuilder("WaterTower", random.Random(12))
    wood, cream, red = shade("#9A6B3F"), shade("#FFF1C9"), shade("#FF5A4E")
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.cyl((sx * 6.5, sy * 6.5, 0), (sx * 4.8, sy * 4.8, 30), 0.7, 8, wood)
    for z in (9, 20):
        f = 1 - z / 30 * (1.7 / 6.5)
        e = 6.5 * f
        for sy in (-1, 1):
            bx(b, 0, sy * e, z, 2 * e, 0.5, 0.6, wood)
        for sx in (-1, 1):
            bx(b, sx * e, 0, z, 0.5, 2 * e, 0.6, wood)
    bx(b, 0, 0, 30, 16, 16, 1.0, wood)
    b.cyl((0, 0, 31), (0, 0, 43), 7.0, 18, cream)
    b.cyl((0, 0, 36), (0, 0, 37.6), 7.15, 18, red)
    b.cone((0, 0, 43), (0, 0, 49.5), 7.8, 18, red)
    for sx in (-1, 1):                                                # ladder on the front
        b.cyl((sx * 1.0, -7.0, 0), (sx * 1.0, -6.0, 31), 0.22, 6, shade("#5B3A22"))
    for k in range(14):
        z = 1.5 + k * 2.1
        y = -7.0 + z / 31
        bx(b, 0, y, z, 2.0, 0.3, 0.3, shade("#5B3A22"))
    return b


def fence():
    b = lh.MeshBuilder("Fence", random.Random(13))
    wood = shade("#9A6B3F")
    for x in (-5, 5):
        bx(b, x, 0, 0, 0.8, 0.8, 4.6, shade("#7A5432"))
        b.cone((x, 0, 4.6), (x, 0, 5.3), 0.56, 4, shade("#7A5432"))
    for z in (1.4, 3.4):
        bx(b, 0, -0.5, z, 10.6, 0.3, 0.9, wood)
    return b


def plot_sign():
    b = lh.MeshBuilder("PlotSign", random.Random(14))
    bx(b, 0, 0, 0, 0.7, 0.7, 6.0, shade("#7A5432"))
    bx(b, 0, -0.45, 3.6, 6.4, 0.3, 2.8, shade("#FFF1C9"))
    bx(b, 0, -0.3, 3.4, 6.8, 0.25, 3.2, INK)
    text_mesh(b, "PLOT", (0, -0.6, 5.0), 6.0, 2.4, "#1B2A3A", depth=0.14, shadow=False)
    return b


BUILDERS = {
    "FireTruck": (fire_truck, "medium"),
    "Hydrant": (hydrant, "small"),
    "Mountain_A": (lambda: mountain("Mountain_A", 21, 260, 95), "medium"),
    "Mountain_B": (lambda: mountain("Mountain_B", 22, 320, 110), "medium"),
    "Mountain_C": (lambda: mountain("Mountain_C", 23, 210, 80), "medium"),
    "TunnelCliff": (tunnel_cliff, "medium"),
    "Dam": (dam, "medium"),
    "Pump": (pump, "small"),
    "WaterTower": (water_tower, "medium"),
    "Fence": (fence, "small"),
    "PlotSign": (plot_sign, "small"),
}

def load_report(out):
    path = os.path.join(out, "kit_report.json")
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {}


def save_report(out, report):
    with open(os.path.join(out, "kit_report.json"), "w") as f:
        json.dump(report, f, indent=1)


def main():
    reset_scene()
    os.makedirs(os.path.join(OUT, "renders"), exist_ok=True)
    only = set(os.environ.get("KIT_ONLY", "").split(",")) - {""}
    report = load_report(OUT)
    report.pop("ToolShack", None), report.pop("GadgetStore", None), report.pop("FireStation", None)
    for name, (fn, cls) in BUILDERS.items():
        if only and name not in only:
            continue
        ob = fn().to_object()
        ob.name = name
        style = "faceted" if name.startswith(("Mountain", "TunnelCliff", "PlotSign")) else "soft"
        lh.finish_modules([ob], {name: {"style": style} if style == "faceted" else {"style": "soft", "bevel_width": 0.06, "smooth_angle": 50}})
        passed, fails, r = lf.gate(ob, cls)
        report[name] = {"class": cls, "passed": passed, "fails": fails, "tris": r["tris"],
                        "size_studs": [round(v, 2) for v in r["dimensions"]], "signs": SIGNS.get(name, [])}
        lf.export_glb(ob, os.path.join(OUT, name + ".glb"))
        if os.environ.get("NO_RENDER") != "1":
            lh.render_preview([ob], os.path.join(OUT, "renders", name + ".png"), size=(720, 520))
        ob.hide_render = True
        ob.hide_viewport = True
        print(f"KIT {name}: tris {r['tris']} passed {passed} {fails}")
    save_report(OUT, report)
    print("KIT DONE", len(report))


if __name__ == "__main__":
    main()
