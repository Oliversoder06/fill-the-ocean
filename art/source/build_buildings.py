"""Save the Ocean buildings with real walls, openings, interiors and a lift-off roof.

Run headless (Blender 5.2):
    blender -b --factory-startup --python art/source/build_buildings.py -- <out_dir>
    (BUILD_ONLY=ToolShack,FireStation limits the run)

Each building is exported as modules that share one origin (base centre, front faces -Y):
    <Name>_Walls     foundation, floor, wall cores, siding / brick courses, parapet   (faceted)
    <Name>_Detail    frames, doors, porch, awning, trims, signs, rooftop prop          (soft bevel)
    <Name>_Interior  shelves, counters, furniture: where shop items will sit later    (soft bevel)
    <Name>_Roof      roof, gable, ceiling, lamps hanging from it (hide it to look inside)
    <Name>_Glass     window panes (give them a Glass material / transparency in Studio)
Writes <out_dir>/<Module>.glb, <out_dir>/renders/<Name>_<view>.png and <out_dir>/buildings_report.json.
"""
import json
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from build_map_kit import H, INK, OUT, bx, bxr, lf, lh, reset_scene, ring, rotx, roty, shade, text_mesh  # noqa: E402

RNG = random.Random(42)


# ---------------------------------------------------------------- colour helpers
def jit(hexc, amount=0.06):
    """A shade function whose base colour varies a little: boards, bricks and planks never look copy-pasted."""
    c = H(hexc)
    k = 1 + RNG.uniform(-amount, amount)
    base = tuple(max(0.0, min(1.0, v * k)) for v in c)
    return lh.by_normal(tuple(min(1.0, v * 1.1) for v in base), base, tuple(v * 0.68 for v in base))


def flat(hexc):
    c = H(hexc)
    return lambda cc, n, co: c


# ---------------------------------------------------------------- faces and walls
class WF:
    """One wall face. along: the axis the wall runs on ("x" or "y"); plane: coordinate of its OUTER surface;
    out: +1 / -1, the outward direction on the other axis. d = distance outward from that surface (negative = into the
    wall or the room), u = position along the wall, z = height."""

    def __init__(self, along, plane, out):
        self.along, self.plane, self.out = along, plane, out

    def box(self, b, u0, u1, z0, z1, d0, d1, col):
        a, c = self.plane + self.out * d0, self.plane + self.out * d1
        if self.along == "x":
            bxr(b, u0, u1, a, c, z0, z1, col)
        else:
            bxr(b, a, c, u0, u1, z0, z1, col)

    def p(self, u, z, d):
        n = self.plane + self.out * d
        return Vector((u, n, z)) if self.along == "x" else Vector((n, u, z))

    @property
    def normal(self):
        return Vector((0, self.out, 0)) if self.along == "x" else Vector((self.out, 0, 0))

    def inner(self, t):
        """The room-side face of a wall t thick; its d points into the room."""
        return WF(self.along, self.plane - self.out * t, -self.out)


def faces(hw, hd):
    return {"front": WF("x", -hd, -1), "back": WF("x", hd, 1), "left": WF("y", -hw, -1), "right": WF("y", hw, 1)}


def spans(u0, u1, holes, z0, z1, margin=0.0):
    """Parts of [u0, u1] not covered by any opening (a, b, zb, zt) that overlaps the height band [z0, z1]."""
    cut = sorted((a - margin, b + margin) for (a, b, zb, zt) in holes if zb - margin < z1 and zt + margin > z0)
    out, cur = [], u0
    for a, b in cut:
        if a > cur:
            out.append((cur, min(a, u1)))
        cur = max(cur, b)
    if cur < u1:
        out.append((cur, u1))
    return [(a, b) for a, b in out if b - a > 0.12]


def wall_colour(f, out_hex, in_hex, edge_hex):
    o, i, e = H(out_hex), H(in_hex), H(edge_hex)
    nrm = f.normal

    def col(c, n, co):
        dot = n.dot(nrm)
        return o if dot > 0.5 else (i if dot < -0.5 else e)
    return col


def wall_core(b, f, u0, u1, z0, z1, t, holes, col):
    """A wall with real openings: full-height strips between openings, plus the pieces under and over each one."""
    cur = u0
    for a, c, zb, zt in sorted(holes):
        if a > cur:
            f.box(b, cur, a, z0, z1, -t, 0, col)
        if zb > z0:
            f.box(b, a, c, z0, zb, -t, 0, col)
        if zt < z1:
            f.box(b, a, c, zt, z1, -t, 0, col)
        cur = c
    if cur < u1:
        f.box(b, cur, u1, z0, z1, -t, 0, col)


def courses(b, f, u0, u1, z0, z1, holes, hexc, board=1.0, gap=0.1, proud=0.16, margin=0.45, gable=None, amount=0.06):
    """Horizontal boards (siding) or brick courses on a face, cut around openings (and their frames).
    gable=(z_base, z_peak) narrows the rows to a triangle."""
    z = z0
    while z < z1 - 0.15:
        zt = min(z + board - gap, z1)
        a0, a1 = u0, u1
        if gable:
            zb, zp = gable
            frac = max(0.0, 1 - (zt - zb) / (zp - zb))
            half, c = (u1 - u0) / 2 * frac, (u0 + u1) / 2
            a0, a1 = c - half, c + half
            if a1 - a0 < 0.8:
                break
        for s, e in spans(a0, a1, holes, z, zt, margin):
            f.box(b, s, e, z, zt, -0.05, proud, jit(hexc, amount))
        z += board


def window(bd, bg, f, uc, zb, w, h, t, trim, itrim, glass="#9AD8F5", mullions=True, flowers=None):
    u0, u1, zt = uc - w / 2, uc + w / 2, zb + h
    fw, P = 0.45, 0.32
    tr = shade(trim)
    f.box(bd, u0 - fw, u0, zb - fw, zt + fw, -0.1, P, tr)
    f.box(bd, u1, u1 + fw, zb - fw, zt + fw, -0.1, P, tr)
    f.box(bd, u0, u1, zt, zt + fw, -0.1, P, tr)
    f.box(bd, u0 - fw - 0.25, u1 + fw + 0.25, zb - 0.42, zb + 0.02, -0.1, P + 0.45, tr)       # sill
    it = shade(itrim)
    fi = f.inner(t)
    fi.box(bd, u0 - 0.35, u0, zb - 0.35, zt + 0.35, -0.05, 0.14, it)                          # inside casing
    fi.box(bd, u1, u1 + 0.35, zb - 0.35, zt + 0.35, -0.05, 0.14, it)
    fi.box(bd, u0, u1, zt, zt + 0.35, -0.05, 0.14, it)
    fi.box(bd, u0 - 0.5, u1 + 0.5, zb - 0.3, zb + 0.02, -0.05, 0.55, it)                     # inside sill
    f.box(bg, u0, u1, zb, zt, -t / 2 - 0.06, -t / 2 + 0.06, shade(glass, 1.05, 0.9))
    if mullions:
        f.box(bd, uc - 0.12, uc + 0.12, zb, zt, -t / 2 - 0.16, -t / 2 + 0.16, tr)
        f.box(bd, u0, u1, zb + h * 0.58 - 0.12, zb + h * 0.58 + 0.12, -t / 2 - 0.16, -t / 2 + 0.16, tr)
    if flowers:
        box_hex, petals = flowers
        f.box(bd, u0 - 0.2, u1 + 0.2, zb - 1.55, zb - 0.4, -0.05, 0.95, shade(box_hex))
        for i in range(int(w / 0.9)):
            u = u0 + 0.3 + i * 0.9
            c = f.p(u, zb - 0.32, 0.48)
            bd.ico(tuple(c), (0.42, 0.42, 0.38), shade("#5FA04A"), subdiv=1)
            if i % 2 == 0:
                bd.ico(tuple(f.p(u + 0.2, zb + 0.02, 0.5)), (0.22, 0.22, 0.2), shade(petals[i // 2 % len(petals)]), subdiv=1)
    return (u0, u1, zb, zt)


def door(bd, f, uc, zf, w, h, t, trim, itrim, leaf_hex, knob="#FFD36B"):
    """Framed doorway; the leaf stands open, swung into the room against the wall, held by two hinges."""
    u0, u1, zt = uc - w / 2, uc + w / 2, zf + h
    fw, P = 0.5, 0.36
    tr, it = shade(trim), shade(itrim)
    f.box(bd, u0 - fw, u0, zf - 0.6, zt + fw, -0.1, P, tr)
    f.box(bd, u1, u1 + fw, zf - 0.6, zt + fw, -0.1, P, tr)
    f.box(bd, u0 - fw - 0.2, u1 + fw + 0.2, zt, zt + fw + 0.3, -0.1, P + 0.15, tr)
    f.box(bd, u0, u1, zf - 0.1, zf + 0.06, -t - 0.02, 0.35, shade("#8A6A48"))                 # threshold
    fi = f.inner(t)
    fi.box(bd, u0 - 0.38, u0, zf, zt + 0.38, -0.05, 0.16, it)
    fi.box(bd, u1, u1 + 0.38, zf, zt + 0.38, -0.05, 0.16, it)
    fi.box(bd, u0, u1, zt, zt + 0.38, -0.05, 0.16, it)
    # open leaf: hinged at u0, lies along the room-side direction
    lw = w - 0.25
    fi.box(bd, u0 + 0.05, u0 + 0.3, zf + 0.1, zt - 0.08, 0.05, 0.05 + lw, shade(leaf_hex))
    for zc in (zf + 1.6, zt - 1.6):
        fi.box(bd, u0 - 0.06, u0 + 0.12, zc - 0.3, zc + 0.3, -0.04, 0.24, shade("#5B4A3A"))    # hinges
    for z0, z1 in ((zf + 0.8, zf + h * 0.45), (zf + h * 0.52, zt - 0.8)):
        fi.box(bd, u0 + 0.26, u0 + 0.46, z0, z1, 0.5, lw - 0.4, shade(leaf_hex, 1.15, 0.8))   # panels
    fi.box(bd, u0 + 0.26, u0 + 0.62, zf + h * 0.48 - 0.2, zf + h * 0.48 + 0.2, lw - 0.55, lw - 0.15, shade(knob))
    return (u0, u1, zf - 0.2, zt)


# ---------------------------------------------------------------- interior pieces
def shelf_unit(bi, fi, u0, u1, z0, depth, levels, top, wood, accent, back):
    """Wall shelving: uprights at the ends and at most every 4.5 studs, boards with a front lip (items sit between the
    lips), a back panel against the wall, a kick plate and a crown. fi is the wall's room-side face."""
    n = max(1, math.ceil((u1 - u0) / 4.5))
    for i in range(n + 1):
        u = u0 + (u1 - u0) * i / n
        a = min(max(u - 0.2, u0), u1 - 0.4)
        fi.box(bi, a, a + 0.4, z0, top, -0.05, depth, shade(wood, 1.05, 0.75))
    fi.box(bi, u0, u1, z0, top, -0.06, 0.12, shade(back))
    fi.box(bi, u0, u1, z0, z0 + 0.6, 0.0, depth - 0.15, shade(wood, 1.0, 0.6))
    for z in levels:
        fi.box(bi, u0, u1, z, z + 0.24, 0.0, depth, jit(wood, 0.04))
        fi.box(bi, u0, u1, z + 0.24, z + 0.42, depth - 0.14, depth, shade(accent))
    fi.box(bi, u0 - 0.1, u1 + 0.1, top, top + 0.32, -0.05, depth + 0.18, shade(wood, 1.05, 0.75))


def counter(bi, x0, x1, y0, y1, z0, h, body, top, accent, face="-x"):
    bxr(bi, x0, x1, y0, y1, z0, z0 + 0.4, shade(body, 1.0, 0.55))                         # recessed kick
    k = 0.25
    bxr(bi, x0 + (0 if face != "-x" else k), x1 - (0 if face != "+x" else k), y0, y1, z0 + 0.35, z0 + h - 0.3, shade(body))
    bxr(bi, x0 - 0.3, x1 + 0.3, y0 - 0.3, y1 + 0.3, z0 + h - 0.32, z0 + h, jit(top, 0.03))
    if face == "-x":
        bxr(bi, x0 + 0.12, x0 + 0.3, y0 + 0.2, y1 - 0.2, z0 + h - 1.2, z0 + h - 0.8, shade(accent))
        bxr(bi, x0 + 0.12, x0 + 0.3, y0 + 0.2, y1 - 0.2, z0 + 0.8, z0 + 1.0, shade(accent))
    return z0 + h


def register(bi, x, y, ztop, facing=-1):
    bxr(bi, x - 0.9, x + 0.9, y - 0.7, y + 0.7, ztop - 0.02, ztop + 0.9, shade("#4A5560"))
    bxr(bi, x - 0.7, x + 0.7, y - 0.55, y + 0.55, ztop + 0.88, ztop + 1.0, shade("#C9D3DB"))
    bi.obox((x + 0.2 * -facing, y, ztop + 1.45), (0.12, 1.1, 0.8), roty(20 * facing), shade("#9AD8F5", 1.1, 0.9))
    bxr(bi, x + 0.2 * -facing - 0.08, x + 0.2 * -facing + 0.08, y - 0.1, y + 0.1, ztop + 0.98, ztop + 1.1, shade("#4A5560"))


def bell(bi, x, y, ztop):
    bi.cyl((x, y, ztop - 0.02), (x, y, ztop + 0.12), 0.45, 10, shade("#5B4A3A"))
    bi.ico((x, y, ztop + 0.3), (0.38, 0.38, 0.3), shade("#FFD36B", 1.15, 0.8), subdiv=1)


def stool(bi, x, y, z0, seat="#FF5A4E"):
    for dx, dy in ((-0.45, -0.45), (0.45, -0.45), (-0.45, 0.45), (0.45, 0.45)):
        bi.cyl((x + dx, y + dy, z0), (x + dx * 0.6, y + dy * 0.6, z0 + 2.4), 0.14, 6, shade("#4A5560"))
    bi.cyl((x, y, z0 + 2.35), (x, y, z0 + 2.75), 0.8, 12, shade(seat))


def pendant(br, x, y, zc, drop, shade_hex, n=12):
    """Lamp hanging from the ceiling (zc = ceiling underside): cord, cap, shade, bulb."""
    zl = zc - drop
    br.cyl((x, y, zc + 0.15), (x, y, zl + 0.6), 0.13, 6, flat("#2B2B2E"))
    br.cyl((x, y, zl + 0.45), (x, y, zl + 0.8), 0.3, 8, shade("#2B2B2E"))
    br.cone((x, y, zl - 0.6), (x, y, zl + 0.62), 1.25, n, shade(shade_hex))
    br.ico((x, y, zl - 0.55), (0.42, 0.42, 0.42), flat("#FFF3C0"), subdiv=1)


def rug(bi, x0, x1, y0, y1, z, c1, c2, stripes=5):
    bxr(bi, x0, x1, y0, y1, z - 0.02, z + 0.06, shade(c1))
    w = (y1 - y0) / (stripes * 2 + 1)
    for i in range(stripes):
        ya = y0 + w * (2 * i + 1)
        bxr(bi, x0 + 0.3, x1 - 0.3, ya, ya + w, z + 0.04, z + 0.14, shade(c2))


def poster(bi, fi, uc, zc, w, h, frame, art):
    fi.box(bi, uc - w / 2 - 0.25, uc + w / 2 + 0.25, zc - h / 2 - 0.25, zc + h / 2 + 0.25, -0.04, 0.16, shade(frame))
    fi.box(bi, uc - w / 2, uc + w / 2, zc - h / 2, zc + h / 2, 0.1, 0.2, shade(art[0]))
    fi.box(bi, uc - w / 2 + w * 0.2, uc + w / 2 - w * 0.2, zc - h * 0.25, zc + h * 0.25, 0.18, 0.26, shade(art[1]))


def barrel(bi, x, y, z0, r=1.0, h=2.6, wood="#A8743F", hoop="#4A5560"):
    bi.cyl((x, y, z0), (x, y, z0 + h), r, 14, jit(wood, 0.03))
    for z in (z0 + 0.4, z0 + h - 0.6):
        bi.cyl((x, y, z), (x, y, z + 0.2), r + 0.05, 14, shade(hoop))


def broom(bi, x, y, z0, lean=(0.25, 0.1)):
    top = Vector((x + lean[0] * 4, y + lean[1] * 4, z0 + 5.6))
    bi.cyl((x, y, z0 + 1.0), tuple(top), 0.14, 6, shade("#B8834E"))
    bi.cone((x, y, z0 - 0.02), (x, y, z0 + 1.2), 0.55, 8, shade("#D9B45A"))


def plank_floor(bw, x0, x1, y0, y1, z0, z1, hexc, width=1.0):
    y = y0
    while y < y1 - 0.1:
        bxr(bw, x0, x1, y, min(y + width - 0.06, y1), z0, z1, jit(hexc, 0.07))
        y += width


def foundation(bw, hw, hd, z1, stone, block=(1.8, 2.8)):
    bxr(bw, -hw + 0.1, hw - 0.1, -hd + 0.1, hd - 0.1, 0, z1 - 0.2, shade(stone, 1.0, 0.6))
    for f in faces(hw, hd).values():
        L = hw if f.along == "x" else hd
        u = -L - 0.25
        while u < L + 0.25:
            e = min(u + RNG.uniform(*block), L + 0.3)
            f.box(bw, u + 0.05, e - 0.05, 0, z1, -0.6, 0.3, jit(stone, 0.08))
            u = e


def pyramid(b, cx, cy, z0, half, height, col):
    v = [(cx - half, cy - half, z0), (cx + half, cy - half, z0), (cx + half, cy + half, z0), (cx - half, cy + half, z0), (cx, cy, z0 + height)]
    b.add(v, [(0, 3, 2, 1), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], col)


def gable_roof(br, hw, y0, y1, H, pitch, ov, deck_hex, shingle_hexes, trim_hex):
    """Ridge along Y (front to back). Deck + overlapping shingle rows + ridge cap + fascia and rake boards.
    The deck underside passes through (+-hw, H): it sits exactly on the eave walls."""
    p = math.radians(pitch)
    T = math.tan(p)
    Ly = y1 - y0
    yc = (y0 + y1) / 2
    for s in (-1, 1):
        d = Vector((-s * math.cos(p), 0, math.sin(p)))
        n = Vector((s * math.sin(p), 0, math.cos(p)))
        M = roty(math.degrees(p) if s > 0 else -math.degrees(p))
        Q = Vector((s * hw, yc, H))
        L = (hw + ov) / math.cos(p)
        mid = (hw - ov) / (2 * math.cos(p))
        br.obox(Q + d * mid + n * 0.2, (L + 0.1, Ly, 0.4), M, shade(deck_hex, 1.0, 0.7))
        m = -ov / math.cos(p) + 0.95
        i = 0
        while m < hw / math.cos(p) - 0.4:
            c = Q + d * m + n * (0.55 + 0.07 * (i % 2))
            br.obox(c, (1.95, Ly + 0.25, 0.32), M, jit(shingle_hexes[i % len(shingle_hexes)], 0.04))
            m += 1.5
            i += 1
        e = Q + d * (-ov / math.cos(p)) + n * 0.1
        br.obox(e + Vector((s * 0.15, 0, -0.25)), (0.4, Ly + 0.3, 1.0), M, shade(trim_hex))   # fascia
    R = H + hw * T
    br.obox((0, yc, R + 0.75), (1.4, Ly + 0.4, 1.4), Matrix.Rotation(math.radians(45), 3, "Y"), shade(trim_hex))
    return R


# ---------------------------------------------------------------- modules
class Building:
    def __init__(self, name):
        self.name = name
        self.parts = {k: lh.MeshBuilder(f"{name}_{k}", random.Random(hash(k) % 1000)) for k in ("Walls", "Detail", "Interior", "Roof", "Glass", "Sign")}
        self.signs = []
        self.meta = {}

    def __getattr__(self, k):
        parts = self.__dict__.get("parts", {})
        if k in parts:
            return parts[k]
        raise AttributeError(k)


# ---------------------------------------------------------------- shops (false-front beach shops)
def shop(name, w, d, H, pal, sign_text, interior, prop):
    """A clapboard shop with a false front, porch, striped awning, gable roof (ridge front to back) and a real room."""
    B = Building(name)
    hw, hd, t, FL = w / 2, d / 2, 0.8, 1.0
    FF = H + 7.0          # false front top
    OV = 1.2
    fc = faces(hw, hd)
    # ---- openings
    door_hole = (-2.8, 2.8, FL - 0.2, FL + 8.4)
    win_front = [(-hw * 0.6, 4.6, 5.0, 4.6), (hw * 0.6, 4.6, 5.0, 4.6)]   # (uc, zb, w, h)
    holes = {"front": [door_hole] + [(u - ww / 2, u + ww / 2, zb, zb + hh) for u, zb, ww, hh in win_front],
             "back": [], "left": [], "right": [(1.0 - 2.2, 1.0 + 2.2, 5.6, 9.6)]}
    # ---- walls module
    W = B.Walls
    foundation(W, hw + 0.3, hd + 0.3, 0.8, pal["stone"])
    plank_floor(W, -hw + t - 0.05, hw - t + 0.05, -hd + t - 0.05, hd - t + 0.05, 0.75, FL, pal["floor"])
    for k, f in fc.items():
        col = wall_colour(f, pal["gap"], pal["inside"], pal["reveal"])
        if f.along == "x":
            wall_core(W, f, -hw, hw, 0.8, H, t, holes[k], col)
        else:
            wall_core(W, f, -hd + t - 0.05, hd - t + 0.05, 0.8, H, t, holes[k], col)
        L = hw if f.along == "x" else hd
        courses(W, f, -L, L, 0.85, H, holes[k], pal["siding"])
    # false front above the eave line, wider than the building, with a raised centre
    ffw = WF("x", -hd, -1)
    colf = wall_colour(ffw, pal["gap"], pal["gap"], pal["reveal"])
    ffw.box(W, -hw - OV, hw + OV, H, FF, -t, 0, colf)
    ffw.box(W, -hw * 0.45, hw * 0.45, FF, FF + 1.6, -t, 0, colf)
    courses(W, ffw, -hw - OV, hw + OV, H, FF, [], pal["siding"])
    courses(W, ffw, -hw * 0.45, hw * 0.45, FF, FF + 1.6, [], pal["siding"])
    ffb = WF("x", -hd + t, 1)   # its back, seen above the roof from behind
    courses(W, ffb, -hw - OV, hw + OV, H, FF, [], pal["siding"])
    courses(W, ffb, -hw * 0.45, hw * 0.45, FF, FF + 1.6, [], pal["siding"])
    # ---- detail module: corners, frames, caps, porch, awning, sign
    D = B.Detail
    trim = pal["trim"]
    for sx in (-1, 1):
        for sy in (-1, 1):
            top = FF if sy < 0 else H
            bxr(D, sx * hw - 0.5, sx * hw + 0.5, sy * hd - 0.5, sy * hd + 0.5, 0.8, top, shade(trim))
        bxr(D, sx * hw - 0.05, sx * (hw + OV), -hd - 0.05, -hd + t, H - 1.4, H + 0.02, shade(trim))   # corbel under the overhang
        bxr(D, sx * (hw + OV) - 0.5 * sx - 0.5, sx * (hw + OV) - 0.5 * sx + 0.5, -hd - 0.4, -hd + 0.2, H, FF, shade(trim))
    bxr(D, -hw - OV - 0.3, hw + OV + 0.3, -hd - 0.6, -hd + t + 0.3, FF - 0.05, FF + 0.55, shade(trim))      # caps
    bxr(D, -hw * 0.45 - 0.3, hw * 0.45 + 0.3, -hd - 0.6, -hd + t + 0.3, FF + 1.55, FF + 2.15, shade(trim))
    bxr(D, -hw - 0.6, hw + 0.6, -hd - 0.5, -hd + 0.2, H - 0.3, H + 0.4, shade(trim))                       # belt course
    door(D, fc["front"], 0, FL, 5.6, 8.4, t, trim, pal["itrim"], pal["door"])
    for uc, zb, ww, hh in win_front:
        window(D, B.Glass, fc["front"], uc, zb, ww, hh, t, trim, pal["itrim"], flowers=(pal["flowerbox"], pal["petals"]))
    window(D, B.Glass, fc["right"], 1.0, 5.6, 4.4, 4.0, t, trim, pal["itrim"])
    # porch: stone skirt, plank deck, a step, posts, beam and the striped awning
    py0, py1 = -hd - 4.8, -hd + 0.1
    bxr(D, -hw - 0.6, hw + 0.6, py0, py1, 0, 0.8, shade(pal["stone"], 1.0, 0.7))
    plank_floor(D, -hw - 0.6, hw + 0.6, py0, py1 - 0.1, 0.78, 1.0, pal["porch"], width=0.9)
    bxr(D, -3.4, 3.4, py0 - 1.1, py0 + 0.05, 0, 0.5, jit(pal["porch"]))
    za = 11.0
    a = math.radians(16)
    ze = za - 4.8 * math.tan(a)
    beam_z = ze - 0.75
    for u in (-hw + 0.1, -3.7, 3.7, hw - 0.1):
        bxr(D, u - 0.35, u + 0.35, py0 + 0.25, py0 + 0.95, 1.0, beam_z, shade(trim))
        bxr(D, u - 0.5, u + 0.5, py0 + 0.1, py0 + 1.1, 1.0, 1.4, shade(trim, 1.0, 0.75))
    bxr(D, -hw - 0.6, hw + 0.6, py0 + 0.2, py0 + 1.0, beam_z, ze - 0.02, shade(trim))
    bxr(D, -hw - 0.3, hw + 0.3, -hd - 0.55, -hd - 0.1, za - 0.7, za + 0.1, shade(trim))                    # ledger
    stripes = 10
    sw = (2 * hw + 1.2) / stripes
    M = rotx(math.degrees(a))
    nrm = M @ Vector((0, 0, 1))
    for i in range(stripes):
        x = -hw - 0.6 + sw * (i + 0.5)
        Wp, Ep = Vector((x, -hd - 0.3, za)), Vector((x, py0 + 0.2, ze))
        L = (Wp - Ep).length + 0.3
        D.obox((Wp + Ep) / 2 + nrm * 0.2, (sw + 0.01, L, 0.32), M, shade(pal["awning"][i % 2]))
        for k in (0.25, 0.75):
            bxr(D, x - sw / 2 + sw * k - 0.42, x - sw / 2 + sw * k + 0.42, py0 + 0.02, py0 + 0.32, ze - 1.0, ze + 0.25, shade(pal["awning"][i % 2]))
    # sign on the false front
    sz0, sz1, sw2 = H + 1.6, H + 5.6, hw * 0.62
    bxr(D, -sw2 - 0.45, sw2 + 0.45, -hd - 0.42, -hd + 0.1, sz0 - 0.45, sz1 + 0.45, shade("#1B2A3A"))
    bxr(D, -sw2, sw2, -hd - 0.62, -hd - 0.3, sz0, sz1, shade(pal["sign"]))
    text_mesh(B.Sign, sign_text, (0, -hd - 0.62, (sz0 + sz1) / 2), 2 * sw2 - 0.4, sz1 - sz0 - 0.4, "#FFFFFF")
    # side wall lantern
    for sx in (-1, 1):
        x = sx * (hw + 0.16)
        bxr(D, x - 0.05 * sx, x + 0.8 * sx, -hd + 3.0, -hd + 3.4, 8.0, 8.4, shade("#2B2B2E"))
        bxr(D, x + 0.4 * sx, x + 0.8 * sx, -hd + 3.0, -hd + 3.4, 7.2, 8.05, shade("#2B2B2E"))
        D.cyl((x + 0.6 * sx, -hd + 3.2, 6.3), (x + 0.6 * sx, -hd + 3.2, 7.25), 0.38, 8, flat("#FFF3C0"))
        D.cone((x + 0.6 * sx, -hd + 3.2, 7.2), (x + 0.6 * sx, -hd + 3.2, 7.9), 0.5, 8, shade("#2B2B2E"))
    prop(B, hw, hd, FF)
    # ---- roof module
    R = gable_roof(B.Roof, hw, -hd + t - 0.05, hd + OV, H, 28, OV, pal["deck"], pal["shingles"], trim)
    bk = WF("x", hd, 1)
    tri_col = wall_colour(bk, pal["gap"], pal["inside"], pal["reveal"])
    B.Roof.prism(Vector((-hw, hd - t, H)), Vector((-hw, hd, H)), Vector((hw, hd - t, H)), Vector((hw, hd, H)),
                 Vector((0, hd - t, R)), Vector((0, hd, R)), tri_col)
    courses(B.Roof, bk, -hw, hw, H, R, [], pal["siding"], gable=(H, R))
    p = math.radians(28)
    for s in (-1, 1):   # rake boards hide the stepped board ends under the roof edge
        L = (hw + 0.6) / math.cos(p)
        c = Vector((s * (hw - 0.6) / 2, hd + 0.2, H + (hw - abs(s * (hw - 0.6) / 2)) * math.tan(p) - 0.42))
        B.Roof.obox(c, (L, 0.65, 0.9), roty(math.degrees(p) * s), shade(trim))
    B.Roof.cyl((0, hd + 0.1, R - 2.6), (0, hd + 0.5, R - 2.6), 1.0, 12, shade(trim))              # round vent
    bxr(B.Roof, -hw + t - 0.05, hw - t + 0.05, -hd + t - 0.05, hd - t + 0.05, H - 0.02, H + 0.3, shade(pal["ceiling"], 1.0, 0.85))
    y = -hd + t + 1.5
    while y < hd - t - 0.5:
        bxr(B.Roof, -hw + t - 0.05, hw - t + 0.05, y, y + 0.6, H - 0.6, H + 0.02, shade(pal["beam"]))
        y += 3.2
    # ---- interior
    interior(B, hw, hd, t, FL, H)
    B.meta = {"hw": hw, "hd": hd, "t": t, "floor": FL, "H": H, "FF": FF, "door": (0, -hd)}
    return B


def wainscot(bi, hw, hd, t, z0, z1, holes, hexc, cap):
    for k, f in faces(hw, hd).items():
        fi = f.inner(t)
        L = (hw if f.along == "x" else hd) - t
        for s, e in spans(-L, L, holes.get(k, []), z0, z1 + 0.4, 0.4):
            fi.box(bi, s, e, z0, z1, -0.05, 0.14, jit(hexc, 0.03))
            fi.box(bi, s, e, z1, z1 + 0.3, -0.05, 0.3, shade(cap))


# ---------------------------------------------------------------- Tool Shack
TOOL_PAL = {
    "stone": "#B9A48A", "floor": "#B98A57", "gap": "#6E4E33", "inside": "#F6E7C8", "reveal": "#D9BE92",
    "siding": "#F2D6A2", "trim": "#8A5A34", "itrim": "#A8743F", "door": "#9C5B33", "flowerbox": "#8A5A34",
    "petals": ["#FF5A4E", "#FFB23F", "#FFFFFF"], "porch": "#C18F5A", "awning": ["#FFB23F", "#FFF1C9"], "sign": "#FFB23F",
    "deck": "#6B4428", "shingles": ["#B5532F", "#A84A2A", "#C25E36"], "ceiling": "#E8D3AE", "beam": "#8A5A34",
}


def tool_interior(B, hw, hd, t, FL, H):
    I = B.Interior
    fc = faces(hw, hd)
    back, left, right, front = (fc[k].inner(t) for k in ("back", "left", "right", "front"))
    lv = [FL + 0.7, FL + 2.9, FL + 5.1, FL + 7.3]
    shelf_unit(I, back, -hw + t + 0.4, -1.4, FL, 1.7, lv, FL + 9.2, "#A8743F", "#FFB23F", "#E9D2A6")
    shelf_unit(I, back, 1.4, hw - t - 0.4, FL, 1.7, lv, FL + 9.2, "#A8743F", "#FFB23F", "#E9D2A6")
    shelf_unit(I, left, -hd + t + 1.0, hd - t - 2.2, FL, 1.7, lv, FL + 9.2, "#A8743F", "#FFB23F", "#E9D2A6")
    poster(I, back, 0, FL + 6.5, 1.8, 2.6, "#8A5A34", ("#3FA9E0", "#FFF1C9"))
    # counter on the right with register and bell, stool behind it, pegboard on the wall
    x0, x1 = hw - t - 4.6, hw - t - 2.6
    ztop = counter(I, x0, x1, -1.6, 4.6, FL, 3.6, "#9C5B33", "#D9B48A", "#FFB23F", face="-x")
    register(I, x0 + 0.9, 3.0, ztop, facing=-1)
    bell(I, x0 + 0.7, 0.2, ztop)
    stool(I, hw - t - 1.3, 1.5, FL)
    right.box(I, -hd + t + 1.0, -2.6, FL + 3.6, FL + 8.6, -0.05, 0.2, shade("#D9B48A"))
    for zz in (FL + 4.2, FL + 5.6, FL + 7.0):
        u = -hd + t + 1.8
        while u < -3.0:
            p0 = right.p(u, zz, 0.15)
            p1 = right.p(u, zz + 0.25, 0.9)
            I.cyl(tuple(p0), tuple(p1), 0.13, 6, shade("#4A5560"))
            u += 1.2
    # display island in the middle
    bxr(I, -6.4, -1.6, -1.4, 2.6, FL, FL + 0.4, shade("#6B4428"))
    bxr(I, -6.2, -1.8, -1.2, 2.4, FL + 0.35, FL + 2.7, shade("#A8743F"))
    bxr(I, -6.7, -1.3, -1.7, 2.9, FL + 2.7, FL + 3.0, jit("#D9B48A", 0.03))
    bxr(I, -6.4, -1.6, -1.4, 2.6, FL + 2.98, FL + 3.18, shade("#FFB23F"))
    rug(I, -2.6, 2.6, -hd + t + 0.6, -hd + t + 3.8, FL, "#3FA9E0", "#FFF1C9")
    barrel(I, hw - t - 1.4, hd - t - 3.4, FL)
    broom(I, hw - t - 1.6, hd - t - 3.5, FL + 2.6, lean=(-0.05, 0.02))
    broom(I, hw - t - 1.1, hd - t - 3.2, FL + 2.6, lean=(0.03, -0.04))
    wainscot(B.Walls, hw, hd, t, FL, FL + 3.0, {"front": [(-3.4, 3.4, 0, 9)], "back": [(-hw, -1.4, 0, 20), (1.4, hw, 0, 20)],
                                       "left": [(-hd + t + 1.0, hd - t - 2.2, 0, 20)]}, "#C18F5A", "#8A5A34")
    pendant(B.Roof, -4.0, 0.6, H, 3.2, "#FFB23F")
    pendant(B.Roof, 4.0, 2.0, H, 3.2, "#FFB23F")


def tool_prop(B, hw, hd, FF):
    """A giant spoon lying on top of the raised false front, held down by two clamps."""
    D = B.Detail
    top = FF + 2.15
    steel = shade("#C9D3DB", 1.12, 0.72)
    y = -hd + 0.1
    D.cyl((-6.5, y, top + 0.85), (2.6, y, top + 0.85), 0.85, 12, steel)
    tbm = bmesh.new()
    bmesh.ops.create_icosphere(tbm, subdivisions=2, radius=1.0)
    D.add_bm(tbm, Matrix.Translation((5.4, y, top + 1.1)) @ Matrix.Diagonal((3.2, 2.0, 1.15, 1)), steel)
    for x in (-4.6, 0.4):
        bxr(D, x - 0.4, x + 0.4, y - 1.05, y + 1.05, top - 0.05, top + 1.95, shade("#1B2A3A"))


# ---------------------------------------------------------------- Gadget Store
GADGET_PAL = {
    "stone": "#AFB6BD", "floor": "#D9E4EC", "gap": "#2A4A66", "inside": "#F4FAFF", "reveal": "#C9DCEA",
    "siding": "#BFE0F4", "trim": "#FFFFFF", "itrim": "#2A4A66", "door": "#2A4A66", "flowerbox": "#2A4A66",
    "petals": ["#FFB23F", "#FF5A4E", "#2FC7B0"], "porch": "#9FB3C2", "awning": ["#3FA9E0", "#FFFFFF"], "sign": "#3FA9E0",
    "deck": "#1F3A52", "shingles": ["#2FA39A", "#2A938B", "#35B2A8"], "ceiling": "#F4FAFF", "beam": "#9FB3C2",
}


def gadget_interior(B, hw, hd, t, FL, H):
    I = B.Interior
    fc = faces(hw, hd)
    back, left, right = (fc[k].inner(t) for k in ("back", "left", "right"))
    # pegboard wall over a low cabinet: gadgets hang on the hooks or stand on the cabinet
    u0, u1 = -hw + t + 0.6, hw - t - 0.6
    back.box(I, u0, u1, FL, FL + 2.6, -0.05, 1.9, shade("#2A4A66"))
    back.box(I, u0 - 0.1, u1 + 0.1, FL + 2.6, FL + 2.9, -0.05, 2.1, jit("#FFFFFF", 0.02))
    back.box(I, u0, u1, FL, FL + 0.4, 0.0, 1.75, shade("#1F3A52"))
    back.box(I, u0, u1, FL + 3.2, FL + 9.4, -0.05, 0.22, shade("#E7EEF4"))
    back.box(I, u0 - 0.2, u1 + 0.2, FL + 9.4, FL + 9.7, -0.05, 0.3, shade("#3FA9E0"))
    for zz in (FL + 4.3, FL + 6.1, FL + 7.9):
        u = u0 + 1.0
        while u < u1 - 0.6:
            I.cyl(tuple(back.p(u, zz, 0.18)), tuple(back.p(u, zz + 0.3, 1.0)), 0.13, 6, shade("#4A5560"))
            u += 2.2
    lv = [FL + 0.7, FL + 2.9, FL + 5.1, FL + 7.3]
    shelf_unit(I, left, -hd + t + 1.0, hd - t - 2.6, FL, 1.7, lv, FL + 9.2, "#FFFFFF", "#3FA9E0", "#DCEEFB")
    for i, u in enumerate((-hd + t + 2.6, 2.0)):
        poster(I, left, u, FL + 10.5, 2.4, 1.2, "#2A4A66", (["#FFB23F", "#FF5A4E"][i], "#FFFFFF"))
    # glass display counter on the right
    x0, x1 = hw - t - 4.8, hw - t - 2.8
    bxr(I, x0, x1, -3.6, 3.6, FL, FL + 0.4, shade("#1F3A52"))
    bxr(I, x0 + 0.2, x1, -3.6, 3.6, FL + 0.35, FL + 2.2, shade("#2A4A66"))
    bxr(I, x0 - 0.2, x1 + 0.2, -3.8, 3.8, FL + 2.2, FL + 2.45, jit("#FFFFFF", 0.02))
    for yy in (-3.6, 0.0, 3.6):
        for xx in (x0 - 0.1, x1 + 0.1):
            bxr(I, xx - 0.12, xx + 0.12, yy - 0.12, yy + 0.12, FL + 2.4, FL + 4.0, shade("#C9D3DB"))
    bxr(I, x0 - 0.2, x1 + 0.2, -3.8, 3.8, FL + 3.95, FL + 4.15, shade("#C9D3DB"))
    bxr(B.Glass, x0 - 0.08, x1 + 0.08, -3.6, 3.6, FL + 2.42, FL + 3.98, shade("#BFE6FF", 1.05, 0.9))
    register(I, x0 + 1.0, -2.2, FL + 4.15, facing=-1)
    stool(I, hw - t - 1.4, 0.5, FL, seat="#3FA9E0")
    # two round display pedestals
    for cx, cy in ((-5.5, -0.5), (0.5, 2.2)):
        I.cyl((cx, cy, FL - 0.02), (cx, cy, FL + 0.35), 1.7, 16, shade("#1F3A52"))
        I.cyl((cx, cy, FL + 0.3), (cx, cy, FL + 2.9), 1.15, 16, shade("#FFFFFF"))
        I.cyl((cx, cy, FL + 2.85), (cx, cy, FL + 3.2), 1.75, 16, shade("#3FA9E0"))
    rug(I, -2.6, 2.6, -hd + t + 0.6, -hd + t + 3.8, FL, "#2A4A66", "#3FA9E0")
    wainscot(B.Walls, hw, hd, t, FL, FL + 3.0, {"front": [(-3.4, 3.4, 0, 9)], "back": [(-hw, hw, 0, 20)],
                                       "left": [(-hd + t + 1.0, hd - t - 2.6, 0, 20)]}, "#3FA9E0", "#FFFFFF")
    pendant(B.Roof, -5.5, -0.5, H, 3.6, "#2FC7B0")
    pendant(B.Roof, 0.5, 2.2, H, 3.6, "#2FC7B0")
    pendant(B.Roof, 6.5, 0.0, H, 3.6, "#2FC7B0")


def gadget_prop(B, hw, hd, FF):
    """A giant water gun standing on the raised false front, plus a hose reel on the right wall."""
    D = B.Detail
    top = FF + 2.15
    y = -hd + 0.1
    red, tank, cream = shade("#FF5A4E"), shade("#3FA9E0"), shade("#FFF1C9")
    # chunky toy water gun lying on the cap: body, barrel with a nozzle, tank on top, grip and trigger hanging back
    bxr(D, -2.0, 5.0, y - 0.9, y + 0.9, top - 0.05, top + 2.4, red)
    bxr(D, -2.4, 0.4, y - 0.95, y + 0.95, top + 0.5, top + 2.0, shade("#FFB23F"))
    D.cyl((-2.3, y, top + 1.3), (-6.4, y, top + 1.3), 0.6, 12, cream)
    D.cyl((-6.3, y, top + 1.3), (-7.1, y, top + 1.3), 0.85, 12, red)
    D.cyl((2.2, y, top + 2.35), (2.2, y, top + 4.9), 1.35, 14, tank)
    D.cyl((2.2, y, top + 4.85), (2.2, y, top + 5.4), 0.55, 10, cream)
    D.obox((3.9, y + 1.6, top + 0.6), (1.6, 1.3, 3.2), rotx(-38), red)
    D.obox((2.4, y + 1.0, top + 0.25), (0.45, 1.0, 1.4), rotx(-25), shade("#1B2A3A"))
    # hose reel on the right wall: bracket, drum, coiled hose and a hanging nozzle
    x = hw + 0.16
    bxr(D, x - 0.05, x + 0.9, -4.5, -3.5, 5.5, 6.5, shade("#9AA7B2"))
    D.cyl((x + 0.8, -4.0, 6.0), (x + 2.0, -4.0, 6.0), 0.85, 12, shade("#1F3A52"))
    for k in (1.05, 1.45, 1.85):
        ring(D, (x + k, -4.0, 6.0), (1, 0, 0), 1.05, 0.26, 12, shade("#2FC7B0"))
    D.cyl((x + 1.4, -4.0, 4.9), (x + 1.4, -4.0, 3.4), 0.24, 8, shade("#2FC7B0"))
    D.cyl((x + 1.4, -4.0, 3.5), (x + 1.4, -4.0, 2.6), 0.36, 8, shade("#FFB23F"))


# ---------------------------------------------------------------- Fire Station
FIRE = {"brick": "#C8443A", "cream": "#F4E2B8", "stone": "#B9BEC4", "gap": "#7A2A24", "inside": "#F4E9D6",
        "reveal": "#E6D2B0", "lower": "#B83A30", "floor": "#B9BEC4"}


def fire_station():
    B = Building("FireStation")
    w, d, H, t, FL = 48, 32, 18, 1.0, 0.6
    hw, hd = w / 2, d / 2
    PAR = H + 2.6
    fc = faces(hw, hd)
    bays = [-12.0, 4.0]
    BW, BH = 13.0, 14.0
    holes = {
        "front": [(u - BW / 2, u + BW / 2, FL - 0.2, FL + BH) for u in bays] + [(12.6, 16.6, FL - 0.2, FL + 8.4), (18.4, 22.0, 5.0, 9.4)],
        "back": [(4.0, 8.4, FL - 0.2, FL + 8.4), (-6.0, -2.0, 9.6, 13.6), (12.0, 16.0, 9.6, 13.6)],
        "left": [(u - 2.0, u + 2.0, 9.6, 13.6) for u in (-8.0, 0.0, 8.0)],
        "right": [(u - 2.0, u + 2.0, 5.0, 10.0) for u in (-9.0, -1.0, 7.0)],
    }
    W, D, I, Rf = B.Walls, B.Detail, B.Interior, B.Roof
    # ---- floor slab and walls with brick courses
    bxr(W, -hw - 0.2, hw + 0.2, -hd - 0.2, hd + 0.2, 0, FL, shade(FIRE["floor"], 1.0, 0.7))
    for k, f in fc.items():
        col = wall_colour(f, FIRE["gap"], FIRE["inside"], FIRE["reveal"])
        if f.along == "x":
            wall_core(W, f, -hw, hw, FL - 0.05, PAR, t, holes[k], col)
        else:
            wall_core(W, f, -hd + t - 0.05, hd - t + 0.05, FL - 0.05, PAR, t, holes[k], col)
        L = hw if f.along == "x" else hd
        # concrete base band, then brick courses up to the cornice, then courses on the parapet
        for s, e in spans(-L, L, holes[k], 0, 2.4, 0.5):
            f.box(W, s, e, 0, 2.4, -0.05, 0.32, jit(FIRE["stone"], 0.03))
        courses(W, f, -L, L, 2.4, H - 1.5, holes[k], FIRE["brick"], board=0.9, gap=0.09, proud=0.16, margin=0.6, amount=0.08)
        courses(W, f, -L, L, H - 0.4, PAR - 0.5, [], FIRE["brick"], board=0.9, gap=0.09, proud=0.16, amount=0.08)
        # pilasters between openings
        u = -L + 0.9
        while u <= L - 0.8:
            if not spans(u - 0.9, u + 0.9, holes[k], 2.4, H - 1.5, 0.7) == [(u - 0.9, u + 0.9)]:
                u += 2.0
                continue
            f.box(D, u - 0.8, u + 0.8, 2.3, H - 1.4, -0.05, 0.5, jit(FIRE["brick"], 0.05))
            f.box(D, u - 1.0, u + 1.0, 2.3, 2.9, -0.05, 0.62, shade(FIRE["cream"]))
            u += 8.0
        # cornice band and parapet cap
        f.box(D, -L - 0.7, L + 0.7, H - 1.5, H - 0.4, -0.05, 0.75, shade(FIRE["cream"]))
        f.box(D, -L - 0.8, L + 0.8, PAR - 0.55, PAR + 0.1, -0.05 - t, 0.6, shade(FIRE["cream"]))
    # ---- openings: bay frames with open roll-up doors, side door, windows
    front, back = fc["front"], fc["back"]
    fi = front.inner(t)
    for u in bays:
        u0, u1 = u - BW / 2, u + BW / 2
        front.box(D, u0 - 0.9, u0, FL - 0.1, FL + BH + 0.9, -0.1, 0.7, shade(FIRE["cream"]))
        front.box(D, u1, u1 + 0.9, FL - 0.1, FL + BH + 0.9, -0.1, 0.7, shade(FIRE["cream"]))
        front.box(D, u0 - 0.9, u1 + 0.9, FL + BH, FL + BH + 1.2, -0.1, 0.85, shade(FIRE["cream"]))
        front.box(D, u0, u1, FL - 0.15, FL + 0.08, -t - 0.02, 0.4, shade("#9AA3AD"))                # threshold
        # rolled-up door drum and guide rails inside
        D.cyl(tuple(fi.p(u0 + 0.2, FL + BH + 0.95, 0.85)), tuple(fi.p(u1 - 0.2, FL + BH + 0.95, 0.85)), 0.9, 14, shade("#C9B98F"))
        for uu in (u0 + 0.05, u1 - 0.35):
            fi.box(D, uu, uu + 0.3, FL, FL + BH + 0.9, -0.05, 0.5, shade("#8A939C"))
        for uu in (u0 - 0.05, u1 + 0.05):
            fi.box(D, uu - 0.35, uu + 0.35, FL + BH + 0.1, FL + BH + 1.9, -0.05, 0.9, shade("#8A939C"))  # drum brackets
        # gooseneck lamp over the bay
        p0 = front.p(u, FL + BH + 2.6, 0.7)
        p1 = front.p(u, FL + BH + 2.6, 2.0)
        D.cyl(tuple(front.p(u, FL + BH + 2.0, 0.7)), tuple(front.p(u, FL + BH + 2.7, 0.7)), 0.18, 6, shade("#2B2B2E"))
        D.cyl(tuple(p0), tuple(p1), 0.15, 6, shade("#2B2B2E"))
        D.cone(tuple(front.p(u, FL + BH + 1.85, 2.0)), tuple(front.p(u, FL + BH + 2.75, 2.0)), 0.75, 10, shade("#2B2B2E"))
        D.ico(tuple(front.p(u, FL + BH + 1.9, 2.0)), (0.3, 0.3, 0.3), flat("#FFF3C0"))
        # bollards
        for uu in (u0 - 1.6, u1 + 1.6):
            c = front.p(uu, 0, 1.6)
            D.cyl((c.x, c.y, 0), (c.x, c.y, 2.8), 0.45, 10, shade("#FFB23F"))
            D.cyl((c.x, c.y, 2.0), (c.x, c.y, 2.35), 0.5, 10, shade("#1B2A3A"))
    door(D, front, 14.6, FL, 4.0, 8.4, t, FIRE["cream"], "#8A5A34", "#7A2A24")
    window(D, B.Glass, front, 20.2, 5.0, 3.6, 4.4, t, FIRE["cream"], "#8A5A34")
    door(D, back, 6.2, FL, 4.0, 8.4, t, FIRE["cream"], "#8A5A34", "#7A2A24")
    for u in (-4.0, 14.0):
        window(D, B.Glass, back, u, 9.6, 4.0, 4.0, t, FIRE["cream"], "#8A5A34")
    for u in (-8.0, 0.0, 8.0):
        window(D, B.Glass, fc["left"], u, 9.6, 4.0, 4.0, t, FIRE["cream"], "#8A5A34")
    for u in (-9.0, -1.0, 7.0):
        window(D, B.Glass, fc["right"], u, 5.0, 4.0, 5.0, t, FIRE["cream"], "#8A5A34")
    # badge between the bays, sign board on the parapet
    bc = front.p(-4.0, FL + BH + 1.6, 0.85)
    D.cyl(tuple(bc), tuple(front.p(-4.0, FL + BH + 1.6, 1.25)), 1.9, 18, shade("#1B2A3A"))
    D.cyl(tuple(front.p(-4.0, FL + BH + 1.6, 1.2)), tuple(front.p(-4.0, FL + BH + 1.6, 1.45)), 1.55, 18, shade("#FFB23F"))
    front.box(D, -11.5, 11.5, H + 0.15, PAR - 0.75, -0.05, 0.42, shade("#1B2A3A"))
    front.box(D, -11.1, 11.1, H + 0.4, PAR - 1.0, 0.3, 0.55, shade(FIRE["cream"]))
    text_mesh(B.Sign, "FIRE STATION", tuple(front.p(0, (H + 0.4 + PAR - 1.0) / 2, 0.55)), 21.4, PAR - 1.0 - H - 0.4, "#C8443A", depth=0.16, shadow=False)
    # hose drying tower behind the back-left corner, joined to the back wall
    tx, ty, ts, th = -hw + 5.5, hd + 4.6, 9.0, 32.0
    bxr(W, tx - ts / 2, tx + ts / 2, hd - 0.3, hd + 9.2, 0, th, wall_colour(WF("x", hd + 9.2, 1), FIRE["gap"], FIRE["gap"], FIRE["reveal"]))
    tf = {"back": WF("x", hd + 9.2, 1), "left": WF("y", tx - ts / 2, -1), "right": WF("y", tx + ts / 2, 1)}
    for k, f in tf.items():
        a, b_ = (tx - ts / 2, tx + ts / 2) if f.along == "x" else (hd, hd + 9.2)
        hole = [((a + b_) / 2 - 1.0, (a + b_) / 2 + 1.0, 24.0, 27.5)]
        courses(W, f, a, b_, 2.4, th - 0.6, hole, FIRE["brick"], board=0.9, gap=0.09, proud=0.16, margin=0.0, amount=0.08)
        f.box(W, (a + b_) / 2 - 1.0, (a + b_) / 2 + 1.0, 24.0, 27.5, -0.2, 0.1, shade("#1B2A3A"))
        f.box(D, (a + b_) / 2 - 1.3, (a + b_) / 2 + 1.3, 23.6, 24.0, -0.1, 0.5, shade(FIRE["cream"]))
        for z in (H - 1.5, th - 0.6):
            f.box(D, a - 0.6, b_ + 0.6, z, z + 1.0, -0.05, 0.6, shade(FIRE["cream"]))
    pyramid(D, tx, ty, th + 0.35, ts / 2 + 1.0, 6.0, shade("#5A2C26"))
    # ---- roof: slab inside the parapet, steel beams under it, hanging lamps, rooftop kit
    ix, iy = hw - t + 0.05, hd - t + 0.05
    bxr(Rf, -ix, ix, -iy, iy, H - 0.02, H + 0.6, shade("#6E5644", 1.0, 0.85))
    bxr(Rf, -ix, ix, -iy, iy, H + 0.58, H + 0.8, shade("#8A939C"))
    for x in range(-18, 19, 6):
        bxr(Rf, x - 0.35, x + 0.35, -iy, iy, H - 1.4, H + 0.02, shade("#7A848D"))
        bxr(Rf, x - 0.8, x + 0.8, -iy, iy, H - 1.6, H - 1.35, shade("#7A848D"))
    for x in (-18.0, -6.0, 12.0, 18.0):
        for y in (-7.0, 5.0):
            pendant(Rf, x, y, H - 1.55, 1.6, "#3A4A5C")
    bxr(Rf, 8, 14, -6, -1, H + 0.78, H + 3.6, shade("#C9D3DB"))
    for k in range(5):
        bxr(Rf, 8.4 + k * 1.1, 8.8 + k * 1.1, -6.2, -5.9, H + 1.2, H + 3.2, shade("#7A848D"))
    Rf.cyl((11, -3.5, H + 3.55), (11, -3.5, H + 3.85), 1.6, 14, shade("#4A5560"))
    for x, y in ((-12, 6), (-5, -8), (18, 9)):
        Rf.cyl((x, y, H + 0.78), (x, y, H + 2.6), 0.45, 10, shade("#9AA3AD"))
        Rf.cyl((x, y, H + 2.55), (x, y, H + 2.85), 0.75, 10, shade("#9AA3AD"))
    bxr(Rf, -20, -16, 8, 12, H + 0.78, H + 1.8, shade("#8A939C"))
    Rf.cyl((16, 12, H + 0.78), (16, 12, H + 6.5), 0.25, 8, shade("#C9D3DB"))
    Rf.cyl((16, 12, H + 6.4), (16, 12, H + 7.4), 0.7, 10, shade("#FF5A4E", 1.2, 0.9))
    # ---- interior
    fire_interior(B, hw, hd, t, FL, H, bays, BW)
    B.meta = {"hw": hw, "hd": hd, "t": t, "floor": FL, "H": H, "bays": bays, "door": (14.6, -hd)}
    return B


def fire_interior(B, hw, hd, t, FL, H, bays, BW):
    I = B.Interior
    fc = faces(hw, hd)
    back, left, right = (fc[k].inner(t) for k in ("back", "left", "right"))
    iy = hd - t
    # bay markings: yellow lines and a stop bar per bay
    for u in bays:
        for uu in (u - 5.6, u + 5.6):
            bxr(B.Walls, uu - 0.18, uu + 0.18, -iy + 0.3, 9.0, FL - 0.02, FL + 0.1, flat("#FFC93C"))
        bxr(B.Walls, u - 5.6, u + 5.6, 9.0, 9.4, FL - 0.02, FL + 0.1, flat("#FFC93C"))
        bxr(B.Walls, u - 0.6, u + 0.6, -2.0, -0.8, FL - 0.02, FL + 0.1, flat("#5A646E"))          # floor drain
    # red lower wall band all round (cream above comes from the wall core)
    wainscot(B.Walls, hw, hd, t, FL, FL + 4.0, {"front": [(u - BW / 2, u + BW / 2, 0, 20) for u in bays] + [(12.6, 16.6, 0, 9)],
                                          "back": [(4.2, 8.2, 0, 9), (9.0, hw, 0, 20), (-hw, -hw + t + 6.7, 0, 20)],
                                          "left": [(-iy + 1.5, -2.5, 0, 20), (0.5, 11.5, 0, 20)],
                                          "right": [(3.6, 12.2, 0, 20)]}, FIRE["lower"], FIRE["cream"])
    # lockers along the back wall (right of the back door), bench in front, helmets and coats on a rail above
    u0 = 9.0
    for i in range(6):
        a = u0 + i * 2.3
        back.box(I, a, a + 2.25, FL, FL + 7.2, -0.05, 1.9, jit("#C0392B", 0.04))
        back.box(I, a + 0.2, a + 2.05, FL + 0.5, FL + 6.8, 1.85, 2.0, shade("#D9534A"))
        for z in (FL + 5.7, FL + 6.2):
            back.box(I, a + 0.6, a + 1.65, z, z + 0.14, 1.95, 2.05, flat("#5A1E1A"))
        back.box(I, a + 1.6, a + 1.8, FL + 3.2, FL + 4.0, 1.95, 2.15, shade("#C9D3DB"))
    back.box(I, u0, u0 + 6 * 2.3, FL + 7.2, FL + 7.45, -0.05, 2.0, shade("#8A939C"))
    bxr(I, u0 + 1.0, u0 + 12.6, iy - 4.1, iy - 3.0, FL + 1.8, FL + 2.2, jit("#A8743F", 0.03))
    for x in (u0 + 1.4, u0 + 12.2):
        bxr(I, x - 0.2, x + 0.2, iy - 3.9, iy - 3.2, FL, FL + 1.85, shade("#4A5560"))
    back.box(I, u0, u0 + 13.8, FL + 9.2, FL + 9.6, -0.05, 0.3, shade("#8A5A34"))
    for i in range(5):
        u = u0 + 1.4 + i * 2.75
        I.cyl(tuple(back.p(u, FL + 9.4, 0.25)), tuple(back.p(u, FL + 9.55, 0.9)), 0.1, 6, shade("#4A5560"))
        back.box(I, u - 0.75, u + 0.75, FL + 7.6, FL + 9.5, 0.45, 0.95, shade("#FFC93C" if i % 2 else "#2B2B2E"))
        I.ico(tuple(back.p(u, FL + 10.1, 0.75)), (0.85, 0.85, 0.6), shade("#E8352B"), subdiv=1)
    # hose rack on the back wall, left of the back door
    back.box(I, -12.0, 1.5, FL + 6.0, FL + 6.6, -0.05, 0.4, shade("#8A5A34"))
    for i, u in enumerate((-10.0, -5.6, -1.2)):
        I.cyl(tuple(back.p(u, FL + 6.3, 0.35)), tuple(back.p(u, FL + 6.3, 1.4)), 0.15, 6, shade("#4A5560"))
        ring(I, tuple(back.p(u, FL + 4.6, 0.85)), tuple(back.normal), 1.6, 0.42, 12, shade(["#E8C77A", "#D9B45A", "#E8C77A"][i]))
    # workbench + pegboard by the hose tower corner
    back.box(I, -hw + t + 0.3, -hw + t + 6.5, FL + 1.0, FL + 3.4, -0.05, 2.4, shade("#7A848D"))
    back.box(I, -hw + t + 0.2, -hw + t + 6.6, FL + 3.4, FL + 3.7, -0.05, 2.6, jit("#A8743F", 0.03))
    back.box(I, -hw + t + 0.3, -hw + t + 6.5, FL, FL + 1.0, 0.0, 2.2, shade("#4A5560"))
    back.box(I, -hw + t + 0.3, -hw + t + 6.5, FL + 4.2, FL + 8.2, -0.05, 0.2, shade("#D9B48A"))
    for z in (FL + 5.2, FL + 6.6):
        u = -hw + t + 1.2
        while u < -hw + t + 6.2:
            I.cyl(tuple(back.p(u, z, 0.15)), tuple(back.p(u, z + 0.25, 0.85)), 0.13, 6, shade("#4A5560"))
            u += 1.6
    # heavy shelving on the left wall: vehicle parts and upgrades sit here
    lv = [FL + 0.8, FL + 3.2, FL + 5.6, FL + 8.0]
    for a, b_ in ((-iy + 1.5, -2.5), (0.5, 11.5)):
        shelf_unit(I, left, a, b_, FL, 2.4, lv, FL + 9.6, "#5A646E", "#FFB23F", "#8A939C")
    # vehicle sales counter + office corner at the front right
    ztop = counter(I, 10.0, 12.0, -10.5, -3.5, FL, 3.6, "#7A2A24", "#D9B48A", "#FFB23F", face="-x")
    register(I, 10.9, -5.5, ztop, facing=-1)
    bell(I, 10.7, -8.6, ztop)
    bxr(I, hw - t - 4.0, hw - t - 0.2, 4.0, 8.0, FL, FL + 3.0, shade("#8A5A34"))                 # desk
    bxr(I, hw - t - 4.2, hw - t - 0.1, 3.8, 8.2, FL + 3.0, FL + 3.3, jit("#D9B48A", 0.03))
    bxr(I, hw - t - 2.4, hw - t - 1.0, 5.2, 6.8, FL + 3.28, FL + 3.4, shade("#4A5560"))
    bxr(I, hw - t - 1.9, hw - t - 1.6, 5.4, 6.6, FL + 3.38, FL + 5.0, shade("#2B2B2E"))           # monitor
    stool(I, hw - t - 5.6, 6.0, FL, seat="#2B2B2E")
    bxr(I, hw - t - 2.4, hw - t - 0.1, 9.8, 12.0, FL, FL + 5.0, shade("#8A939C"))                # filing cabinet
    for z in (FL + 1.2, FL + 2.5, FL + 3.8):
        bxr(I, hw - t - 2.5, hw - t - 2.35, 10.4, 11.4, z, z + 0.25, shade("#C9D3DB"))
    # fire pole from floor to ceiling with a floor pad
    I.cyl((-4.0, 11.0, FL - 0.02), (-4.0, 11.0, FL + 0.25), 1.6, 18, shade("#2B2B2E"))
    I.cyl((-4.0, 11.0, FL + 0.2), (-4.0, 11.0, H + 0.02), 0.32, 10, shade("#E6C25A", 1.2, 0.8))
    # notice board and a safety poster between the right-hand windows
    poster(I, right, -5.0, FL + 6.5, 1.8, 2.4, "#8A5A34", ("#E8352B", "#FFF1C9"))
    right.box(I, 1.9, 4.1, FL + 5.0, FL + 8.4, -0.05, 0.2, shade("#8A5A34"))
    right.box(I, 2.1, 3.9, FL + 5.2, FL + 8.2, 0.1, 0.3, shade("#C9925A"))
    for i, (u, z) in enumerate(((2.5, 7.2), (3.4, 7.6), (2.7, 6.0), (3.5, 6.3))):
        right.box(I, u - 0.3, u + 0.3, FL + z - 0.4, FL + z + 0.4, 0.25, 0.38, shade(["#FFFFFF", "#FFF1C9", "#BFE6FF", "#FFFFFF"][i]))
    # alarm bell on the right wall
    I.cyl(tuple(right.p(-13.0, FL + 9.0, -0.05)), tuple(right.p(-13.0, FL + 9.0, 0.3)), 0.4, 10, shade("#4A5560"))
    I.ico(tuple(right.p(-13.0, FL + 9.0, 0.8)), (0.9, 0.9, 0.9), shade("#E8352B"), subdiv=1)


# ---------------------------------------------------------------- review renders
def shot(objs, path, loc, target, lens=35, size=(960, 680)):
    s = bpy.context.scene
    others = [o for o in s.objects if o not in objs and o.type == "MESH"]
    for o in others:
        o.hide_render = True
    for o in objs:
        o.hide_render = False
    cd = bpy.data.cameras.new("ReviewCam")
    cd.lens = lens
    cd.clip_start = 0.1
    cam = bpy.data.objects.new("ReviewCam", cd)
    s.collection.objects.link(cam)
    s.camera = cam
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    s.render.engine = "BLENDER_WORKBENCH"
    s.render.resolution_x, s.render.resolution_y = size
    s.view_settings.view_transform = "Standard"
    sh = s.display.shading
    sh.light = "STUDIO"
    sh.color_type = "VERTEX"
    sh.show_cavity = True
    sh.show_shadows = True
    sh.shadow_intensity = 0.35
    sh.show_object_outline = False
    if s.world is None:
        s.world = bpy.data.worlds.new("Review")
    s.world.color = (0.75, 0.85, 0.95)
    s.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    for o in others:
        o.hide_render = False


def review(name, mods, meta, out):
    hw, hd, Hh, FL, t = meta["hw"], meta["hd"], meta["H"], meta["floor"], meta["t"]
    allm = list(mods.values())
    noroof = [m for k, m in mods.items() if k != "Roof"]
    r = os.path.join(out, "renders")
    big = max(hw, hd)
    views = {
        "front": (allm, (hw * 1.7, -hd * 4.6, Hh * 1.2), (0, 0, Hh * 0.75), 35),
        "back": (allm, (-hw * 1.6, hd * 3.4, Hh * 1.4), (0, 0, Hh * 0.5), 35),
        "cutaway": (noroof, (hw * 0.9, -hd * 1.6, Hh * 3.0), (0, 0, FL), 30),
        "inside_a": (allm, (meta["door"][0], -hd + t + 1.0, FL + 5.0), (meta["door"][0], hd, FL + 3.0), 14),
        "inside_b": (allm, (meta["door"][0] * 0.5, hd - t - 3.2, FL + 5.5), (-hw * 0.2, -hd, FL + 2.5), 14),
        "side": (allm, (big * 3.0, hd * 0.3, Hh * 0.7), (0, 0, Hh * 0.5), 35),
    }
    for v, (objs, loc, tgt, lens) in views.items():
        shot(objs, os.path.join(r, f"{name}_{v}.png"), loc, tgt, lens)


# ---------------------------------------------------------------- main
BUILDINGS = {
    "ToolShack": lambda: shop("ToolShack", 24, 18, 12, TOOL_PAL, "TOOLS", tool_interior, tool_prop),
    "GadgetStore": lambda: shop("GadgetStore", 26, 18, 13, GADGET_PAL, "GADGETS", gadget_interior, gadget_prop),
    "FireStation": fire_station,
}
STYLE = {"Walls": {"style": "faceted"}, "Glass": {"style": "faceted"}, "Sign": {"style": "faceted"},
         "Detail": {"style": "soft", "bevel_width": 0.05, "smooth_angle": 50},
         "Interior": {"style": "soft", "bevel_width": 0.035, "smooth_angle": 50},
         "Roof": {"style": "soft", "bevel_width": 0.05, "smooth_angle": 50}}


def main():
    reset_scene()
    os.makedirs(os.path.join(OUT, "renders"), exist_ok=True)
    only = set(os.environ.get("BUILD_ONLY", "").split(",")) - {""}
    path = os.path.join(OUT, "buildings_report.json")
    report = json.load(open(path)) if os.path.exists(path) else {}
    for name, fn in BUILDINGS.items():
        if only and name not in only:
            continue
        B = fn()
        mods = {}
        for k, mb in B.parts.items():
            ob = mb.to_object()
            ob.name = f"{name}_{k}"
            mods[k] = ob
        lh.finish_modules(list(mods.values()), {ob.name: STYLE[k] for k, ob in mods.items()})
        entry = {"modules": {}, "signs": B.signs, "meta": B.meta}
        for k, ob in mods.items():
            passed, fails, r = lf.gate(ob, "building")
            entry["modules"][k] = {"passed": passed, "fails": fails, "tris": r["tris"], "size": [round(v, 2) for v in r["dimensions"]]}
            print(f"BUILD {name}_{k}: tris {r['tris']} passed {passed} {fails}"
                  + ("" if passed else f" loose_v {r['loose_verts']} loose_e {r['loose_edges']} degenerate {r['degenerate_faces']}"))
        fl = lh.floating_shells(list(mods.values()), base_names=(f"{name}_Walls",))
        entry["floating"] = fl["floating"]
        entry["floating_examples"] = fl["examples"]
        print(f"BUILD {name}: shells {fl['shells']} floating {fl['floating']} {fl['examples']}")
        # one GLB per building (imports as one Model, one MeshPart per module, shared origin);
        # MODULE_GLBS=1 also writes each module on its own (the web preview loads those)
        lh.export_modules(list(mods.values()), OUT, combined=name)
        if os.environ.get("MODULE_GLBS") != "1":
            for k in mods:
                os.remove(os.path.join(OUT, f"{name}_{k}.glb"))
        if os.environ.get("NO_RENDER") != "1":
            review(name, mods, B.meta, OUT)
        for ob in mods.values():
            ob.hide_render = True
            ob.hide_viewport = True
        report[name] = entry
    with open(path, "w") as f:
        json.dump(report, f, indent=1)
    print("BUILD DONE")


if __name__ == "__main__":
    main()
