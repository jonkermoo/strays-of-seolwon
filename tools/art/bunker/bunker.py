"""M1 style test: bunker entrance (HQ style), built to 15-metrics, intact but weathered (STYLE-BIBLE §7).

blender -b --factory-startup --python bunker.py -- <out dir>
Writes <out>/bunker.fbx (one object per material: Portal, WingL, WingR, Apron, Lip, DoorL, DoorR,
Frame, Cage, Bulb, Vent, and Bag_* sandbags sharing one mesh), <out>/tex/<obj>_{col,nrm,rgh}.png
and preview renders.
Units: 1 Blender unit = 1 stud, Z up, the door faces -Y. Sizes from 15-metrics: double door
8 x 7.5, bunker walls 2 thick, crouch cover 3.5. Textures are painted in object space (cm), never
in UV space, so patterns run across UV seams (notes/traps/assets.md, backpack method), and they
stay flat, front-lit albedo with no baked light (STYLE-BIBLE §4).
"""
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]
TEX = os.path.join(OUT, "tex"); os.makedirs(TEX, exist_ok=True)
CM = 28.0                                      # cm per stud (0.28 m)
RNG = np.random.default_rng(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene


# ------------------------------------------------------------------ noise helpers (numpy)
def hash3(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 144665) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def vnoise(P, seed=0):
    p = np.floor(P).astype(np.int64); f = P - p; f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * hash3(p[..., 0] + dx, p[..., 1] + dy, p[..., 2] + dz, seed)
    return out


def fbm(P, octs=4, seed=0):
    a, s, t = 0.5, 1.0, 0
    for i in range(octs):
        t = t + a * vnoise(P * s, seed + i); a *= 0.5; s *= 2.0
    return t / (1 - 0.5 ** octs)


def H(h): return np.array([int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)], np.float32)


# ------------------------------------------------------------------ geometry helpers
def new_obj(name, bm):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me); scn.collection.objects.link(ob); return ob


def box(bm, lo, hi, bevel=0.0):
    r = bmesh.ops.create_cube(bm, size=1.0)
    vs = r["verts"]; c = (Vector(lo) + Vector(hi)) / 2; s = Vector(hi) - Vector(lo)
    for v in vs: v.co = Vector((v.co.x * s.x, v.co.y * s.y, v.co.z * s.z)) + c
    if bevel > 0:
        es = list({e for v in vs for e in v.link_edges})
        bmesh.ops.bevel(bm, geom=es, offset=bevel, segments=2, affect="EDGES", profile=0.5)
    return vs


def prism(bm, pts2d, y0, y1):
    """Extrude a 2D outline in XZ (list of (x, z)) between y0 and y1."""
    vs0 = [bm.verts.new((x, y0, z)) for x, z in pts2d]; vs1 = [bm.verts.new((x, y1, z)) for x, z in pts2d]
    n = len(pts2d)
    bm.faces.new(list(reversed(vs0))); bm.faces.new(vs1)
    for i in range(n):
        j = (i + 1) % n; bm.faces.new((vs0[i], vs0[j], vs1[j], vs1[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def bake_transform(ob):
    bpy.context.view_layer.update(); ob.data.transform(ob.matrix_world); ob.matrix_world.identity()


# ------------------------------------------------------------------ build (studs)
W, HGT, D, T = 16.0, 11.5, 9.0, 2.0          # portal outer width, height, depth into the hill, wall
DW, DH = 8.0, 7.5                             # double door opening (15-metrics)
FD = 1.5                                      # door set back from the front face
bm = bmesh.new()
box(bm, (-W / 2, 0, 0), (-DW / 2 - 0.5, D, HGT), 0.06)                 # left pier
box(bm, (DW / 2 + 0.5, 0, 0), (W / 2, D, HGT), 0.06)                   # right pier
box(bm, (-DW / 2 - 0.5, 0, DH + 0.5), (DW / 2 + 0.5, D, HGT), 0.06)    # lintel and roof mass
box(bm, (-DW / 2 - 0.5, FD + 0.6, 0), (DW / 2 + 0.5, D, DH + 0.5), 0.0)  # mass behind the door
new_obj("Portal", bm)
bm = bmesh.new(); box(bm, (-W / 2 - 0.4, -2.2, HGT - 1.0), (W / 2 + 0.4, 0.6, HGT), 0.08); new_obj("Lip", bm)
bm = bmesh.new()
box(bm, (-DW / 2 - 0.5, FD - 0.1, 0), (-DW / 2, FD + 0.6, DH + 0.5), 0.03)
box(bm, (DW / 2, FD - 0.1, 0), (DW / 2 + 0.5, FD + 0.6, DH + 0.5), 0.03)
box(bm, (-DW / 2, FD - 0.1, DH), (DW / 2, FD + 0.6, DH + 0.5), 0.03)
new_obj("Frame", bm)
for side, nm in ((-1, "DoorL"), (1, "DoorR")):
    bm = bmesh.new(); x0, x1 = (-DW / 2, -0.04) if side < 0 else (0.04, DW / 2)
    box(bm, (x0, FD + 0.15, 0.02), (x1, FD + 0.55, DH - 0.02), 0.03)
    box(bm, (x0 + 0.35, FD + 0.05, 0.35), (x1 - 0.35, FD + 0.16, DH - 0.35), 0.02)       # raised panel
    hx = x0 + 0.05 if side < 0 else x1 - 0.35
    for z in (1.2, DH - 1.8):
        box(bm, (hx, FD - 0.1, z), (hx + 0.3, FD + 0.16, z + 0.6), 0.02)                  # hinges
    if side < 0:
        # Dogging lever, not a hand wheel: a cross inside a ring can read as a sun-cross symbol, a
        # moderation risk (STYLE-BIBLE §4, no symbols). A plain lever on a round boss with a guard plate.
        cx, cz = x1 - 1.0, 3.9
        box(bm, (cx - 0.28, FD + 0.0, cz - 0.28), (cx + 0.28, FD + 0.16, cz + 0.28), 0.03)   # boss plate
        box(bm, (cx - 0.12, FD - 0.25, cz - 0.12), (cx + 0.12, FD + 0.05, cz + 0.12), 0.02)   # spindle
        box(bm, (cx - 1.3, FD - 0.32, cz - 0.08), (cx + 0.15, FD - 0.18, cz + 0.08), 0.03)    # lever arm
        box(bm, (cx - 1.42, FD - 0.42, cz - 0.11), (cx - 1.12, FD - 0.16, cz + 0.11), 0.03)   # grip
        box(bm, (cx - 1.6, FD + 0.0, cz - 0.6), (cx - 1.45, FD + 0.16, cz + 0.25), 0.02)       # stop bracket
    new_obj(nm, bm)
for side, nm in ((-1, "WingL"), (1, "WingR")):
    bm = bmesh.new(); L = 11.0
    prism(bm, [(0, 0), (L, 0), (L, 3.0), (0, HGT - 1.0)], 0, T)
    ob = new_obj(nm, bm)
    if side > 0:
        ob.rotation_euler.z = math.radians(-30); ob.location = (W / 2, T * math.sin(math.radians(30)) * 0, 0)
        ob.location = (W / 2 - 0.0, 0.0, 0)
    else:
        ob.scale.x = -1; ob.rotation_euler.z = math.radians(30); ob.location = (-W / 2, 0.0, 0)
    bake_transform(ob)
    if side < 0:                                                                        # mirrored: fix winding
        bm = bmesh.new(); bm.from_mesh(ob.data); bmesh.ops.reverse_faces(bm, faces=bm.faces); bm.to_mesh(ob.data); bm.free()
bm = bmesh.new(); box(bm, (-W / 2 - 5, -12, -0.6), (W / 2 + 5, FD + 0.2, 0.0), 0.04); new_obj("Apron", bm)
bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=1.0)
for v in bm.verts:                                                                      # a filled sack: 2 long, 1 wide, 0.6 tall
    x, y, z = v.co
    squash = 1 - 0.25 * max(0.0, abs(x) - 0.6) / 0.4                                     # gathered, tied ends
    v.co = Vector((x * 1.0, y * 0.5 * squash, math.copysign(abs(z) ** 0.75, z) * 0.3 * squash))
bag_mesh = bpy.data.meshes.new("Bag"); bm.to_mesh(bag_mesh); bm.free()
for side in (-1, 1):
    d = Vector((side * math.cos(math.radians(32)), -math.sin(math.radians(32)), 0))      # each wall splays out and away from the door
    start = Vector((side * (DW / 2 + 2.6), -6.0, 0))
    for row in range(6):                                                                # 6 rows x 0.55 = 3.3 + base: crouch cover 3.5
        n, off = (3, 0.0) if row % 2 == 0 else (2, 1.02)                                 # running bond
        for i in range(n):
            p = start + d * (off + i * 2.04)
            ob = bpy.data.objects.new(f"Bag_{'L' if side < 0 else 'R'}{row}{i}", bag_mesh); scn.collection.objects.link(ob)
            ob.location = (p.x, p.y, 0.3 + row * 0.55)
            ob.rotation_euler.z = math.atan2(d.y, d.x) + RNG.normal(0, 0.05)
            ob.rotation_euler.x = RNG.normal(0, 0.03); s = 1 + RNG.normal(0, 0.03); ob.scale = (s, s, s)
bm = bmesh.new()
box(bm, (-0.35, -0.5, DH + 1.1), (0.35, 0.0, DH + 1.3), 0.02)
for k in range(6):
    a = k / 6 * math.tau; x, y = 0.28 * math.cos(a), -0.3 + 0.22 * math.sin(a)
    box(bm, (x - 0.03, y - 0.03, DH + 0.45), (x + 0.03, y + 0.03, DH + 1.1))
box(bm, (-0.3, -0.52, DH + 0.42), (0.3, -0.08, DH + 0.48))
new_obj("Cage", bm)
bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=8, radius=0.2)
for v in bm.verts: v.co += Vector((0, -0.3, DH + 0.78))
new_obj("Bulb", bm)
bm = bmesh.new()
r = bmesh.ops.create_cone(bm, cap_ends=True, segments=14, radius1=0.45, radius2=0.45, depth=2.5)
for v in r["verts"]: v.co += Vector((W / 2 - 3, 5.0, HGT + 1.25))
r = bmesh.ops.create_cone(bm, cap_ends=True, segments=14, radius1=0.75, radius2=0.2, depth=0.6)
for v in r["verts"]: v.co += Vector((W / 2 - 3, 5.0, HGT + 2.7))
new_obj("Vent", bm)

# ------------------------------------------------------------------ UVs (one painted sheet per object)
objs = [o for o in scn.objects if o.type == "MESH" and not o.name.startswith("Bag_")]
bag_holder = bpy.data.objects.new("Bag", bag_mesh); scn.collection.objects.link(bag_holder); bag_holder.location = (0, -40, 0)
objs.append(bag_holder)
for o in objs:
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.select_all(action="DESELECT")

RES = {"Portal": 1024, "WingL": 1024, "WingR": 1024, "Apron": 1024, "Lip": 512, "DoorL": 1024, "DoorR": 1024,
       "Frame": 512, "Bag": 512, "Cage": 256, "Bulb": 128, "Vent": 256}


def buffers(o, res):
    me = o.data; me.calc_loop_triangles(); uv = me.uv_layers.active.data
    P = np.zeros((res, res, 3), np.float32); N = np.zeros((res, res, 3), np.float32); M = np.zeros((res, res), bool)
    for tri in me.loop_triangles:
        uvs = np.array([uv[l].uv[:] for l in tri.loops], np.float32) * res
        ps = np.array([me.vertices[v].co[:] for v in tri.vertices], np.float32)
        n = np.array(tri.normal[:], np.float32)
        x0, y0 = np.floor(uvs.min(0)).astype(int) - 1; x1, y1 = np.ceil(uvs.max(0)).astype(int) + 1
        x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, res - 1), min(y1, res - 1)
        if x1 < x0 or y1 < y0: continue
        yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1].astype(np.float32) + 0.5
        (ax, ay), (bx, by), (cx, cy) = uvs; den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9: continue
        l1 = ((by - cy) * (xx - cx) + (cx - bx) * (yy - cy)) / den; l2 = ((cy - ay) * (xx - cx) + (ax - cx) * (yy - cy)) / den
        l3 = 1 - l1 - l2; ins = (l1 >= -0.03) & (l2 >= -0.03) & (l3 >= -0.03)
        X = l1[..., None] * ps[0] + l2[..., None] * ps[1] + l3[..., None] * ps[2]
        Ps, Ns, Ms = P[y0:y1 + 1, x0:x1 + 1], N[y0:y1 + 1, x0:x1 + 1], M[y0:y1 + 1, x0:x1 + 1]
        Ps[ins] = X[ins]; Ns[ins] = n; Ms[ins] = True
    return P, N, M


def save(name, arr):
    """Write through Blender (its Python has no PIL). Row 0 of arr is UV v=0 (Blender's bottom row)."""
    # Non-colour maps are created as data images: switching colour space AFTER writing pixels
    # reloads the image and wiped normal/roughness maps to black (2026-11-20).
    h, w = arr.shape[:2]; img = bpy.data.images.new(name, w, h, alpha=False, is_data=not name.endswith("_col.png"))
    px = np.ones((h, w, 4), np.float32); px[..., :3] = np.clip(arr, 0, 1)
    img.pixels.foreach_set(px.ravel()); img.filepath_raw = os.path.join(TEX, name); img.file_format = "PNG"
    img.save(); bpy.data.images.remove(img)


def bleed(M, *arrs, steps=12):
    """Push painted texels outward into empty texels so mipmaps don't bleed in black."""
    M = M.copy(); arrs = [a.copy() for a in arrs]
    for _ in range(steps):
        acc = [np.zeros_like(a, dtype=np.float32) for a in arrs]; cnt = np.zeros(M.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            m = np.roll(np.roll(M, dy, 0), dx, 1)
            cnt += m
            for k, a in enumerate(arrs):
                sh = np.roll(np.roll(a, dy, 0), dx, 1)
                acc[k] += sh * (m[..., None] if a.ndim == 3 else m)
        new = (~M) & (cnt > 0)
        for k, a in enumerate(arrs):
            c = cnt[..., None] if a.ndim == 3 else cnt
            a[new] = (acc[k] / np.maximum(c, 1))[new]
        M = M | new
    return arrs


def height_to_normal(h, strength):
    gy, gx = np.gradient(h)
    n = np.dstack([-gx * strength, -gy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=-1, keepdims=True); return n * 0.5 + 0.5


CONC, MOSS, RUST = H("#7c7b75"), H("#454b35"), H("#6e4a36")


def paint_concrete(P, N, top_z, seed):
    C = P * CM; up = N[..., 2]; vert = np.abs(up) < 0.5
    base = CONC * (0.9 + 0.12 * fbm(C / 60.0, 4, seed)[..., None]) * (0.96 + 0.05 * vnoise(C / 3.0, seed + 9)[..., None])
    board = np.abs(((C[..., 2] / 15.0) % 1.0) - 0.5) > 0.47                          # formwork boards, 15 cm
    tieu = np.where(np.abs(N[..., 0]) > np.abs(N[..., 1]), C[..., 1], C[..., 0])
    tie = (np.hypot(((tieu / 60.0) % 1 - 0.5) * 60, ((C[..., 2] / 45.0) % 1 - 0.5) * 45) < 1.4) & vert
    h = 0.05 * fbm(C / 4.0, 3, seed + 3) - 0.06 * (board & vert) - 0.35 * tie
    col = base * np.where((board & vert)[..., None], 0.97, 1.0) * np.where(tie[..., None], 0.6, 1.0)
    sP = np.stack([C[..., 0] / 9 + C[..., 1] / 9, C[..., 2] / 260, np.full_like(C[..., 0], float(seed))], -1)
    streak = np.clip(vnoise(sP, seed + 4) * 1.6 - 0.75, 0, 1)                         # water streaks
    nearTop = np.clip(1 - (top_z * CM - C[..., 2]) / 220.0, 0, 1)
    col = col * (1 - 0.5 * (streak * nearTop * vert)[..., None])                     # 2x wear (backpack lesson)
    low = np.clip(1 - C[..., 2] / 70.0, 0, 1)
    col = col * (1 - 0.4 * low[..., None])
    blot = np.clip(fbm(C / 90.0, 3, seed + 11) * 2.0 - 0.9, 0, 1)                    # large damp patches
    col = col * (1 - 0.18 * blot[..., None])
    moss = np.clip(fbm(C / 25.0, 4, seed + 6) * 2.2 - 1.1, 0, 1) * np.maximum(low * vert, (up > 0.7) * 0.6)
    col = col * (1 - moss[..., None]) + MOSS * (0.85 + 0.2 * vnoise(C / 2.0, seed + 7)[..., None]) * moss[..., None]
    col = np.where((up > 0.7)[..., None], col * 0.92 + 0.03, col)
    col = np.where((up < -0.7)[..., None], col * 0.8, col)
    return col, h, 0.9 - 0.05 * moss


def paint_steel(P, N, seed, paint="#4d534c"):
    C = P * CM; PAINT = H(paint)
    col = PAINT * (0.93 + 0.08 * fbm(C / 30.0, 3, seed)[..., None])
    chip = np.clip(fbm(C / 6.0, 4, seed + 2) * 2.4 - 1.55, 0, 1)
    rP = np.stack([C[..., 0] / 5, C[..., 2] / 120, np.full_like(C[..., 0], 3.0)], -1)
    run = np.clip(vnoise(rP, seed + 5) * 1.8 - 1.2, 0, 1)
    low = np.clip(1 - C[..., 2] / 50.0, 0, 1)
    r = np.clip(chip + 0.3 * run + 0.5 * low * fbm(C / 8.0, 3, seed + 8), 0, 1)
    col = col * (1 - r[..., None]) + RUST * (0.8 + 0.3 * vnoise(C / 1.5, seed + 1)[..., None]) * r[..., None]
    return col, -0.3 * chip + 0.05 * fbm(C / 2.0, 2, seed + 4), 0.65 + 0.25 * r


def paint_bag(P, N, seed):
    C = P * CM; B = H("#6d6857")
    weave = 0.94 + 0.06 * np.sin(C[..., 0] * 2.0) * np.sin(C[..., 1] * 2.0 + C[..., 2] * 2.0)
    col = B * (0.85 + 0.2 * fbm(C / 10.0, 4, seed)[..., None]) * weave[..., None]
    col = col * (1 - 0.3 * np.clip(fbm(C / 14.0, 3, seed + 3) * 1.8 - 0.8, 0, 1)[..., None])
    return col, 0.08 * weave + 0.05 * fbm(C / 3.0, 2, seed), np.full(P.shape[:2], 0.95, np.float32)


def stencil(P, N):
    """Stencil "07" in plain paint on the lintel front (05 §3: plain stencil, not poster style).
    Digits drawn from bars with stencil bridges, in a 2 x 1.44 stud box per digit pair."""
    u = (P[..., 0] + 1.6) / 3.2; v = (P[..., 2] - (DH + 1.6)) / 1.3            # 0..1 over the box
    on = (N[..., 1] < -0.9) & (u >= 0) & (u <= 1) & (v >= 0) & (v <= 1) & (P[..., 1] < 0.05)
    def rect(x0, y0, x1, y1): return (u >= x0) & (u <= x1) & (v >= y0) & (v <= y1)
    t = 0.07
    zero = (rect(0.04, 0.0, 0.42, t * 1.4) | rect(0.04, 1 - t * 1.4, 0.42, 1.0) |
            rect(0.04, 0.12, 0.04 + t * 1.4, 0.88) | rect(0.42 - t * 1.4, 0.12, 0.42, 0.88))
    zero &= ~rect(0.0, 0.46, 0.5, 0.54)                                             # stencil bridges
    seven = rect(0.56, 1 - t * 1.4, 0.96, 1.0) | ((np.abs((u - 0.96) + (1 - v) * 0.30) < t * 0.7) & (v < 0.9) & (u > 0.6))
    seven &= ~rect(0.5, 0.86, 1.0, 0.88)
    a = (zero | seven) & on
    return a.astype(np.float32) * (0.7 + 0.3 * fbm(P * CM / 3, 2, 77))


for i, o in enumerate(objs):
    res = RES[o.name]; P, N, M = buffers(o, res); top = max(v.co.z for v in o.data.vertices)
    if o.name in ("Portal", "WingL", "WingR", "Apron", "Lip", "Vent"):
        col, h, rough = paint_concrete(P, N, top, 10 + i)
        if o.name == "Portal":
            a = stencil(P, N)[..., None]; col = col * (1 - a) + H("#d7d4c6") * a
        if o.name == "Apron":
            dr = (P[..., 1] > -1.2) & (P[..., 1] < -0.6) & (np.abs(P[..., 0]) < DW / 2) & (N[..., 2] > 0.7)
            grate = dr & ((((P[..., 0] * CM) / 4) % 1) < 0.35)
            col = np.where(dr[..., None], H("#2a2b2a"), col); col = np.where(grate[..., None], H("#141514"), col)
    elif o.name in ("DoorL", "DoorR", "Frame"):
        col, h, rough = paint_steel(P, N, 20 + i)
    elif o.name == "Cage":
        col, h, rough = paint_steel(P, N, 30, "#2f3130")
    elif o.name == "Bulb":
        col = np.ones(P.shape, np.float32) * H("#fff1cf"); h = np.zeros(P.shape[:2], np.float32); rough = np.full(P.shape[:2], 0.2, np.float32)
    else:
        col, h, rough = paint_bag(P, N, 40)
    col, h, rough = bleed(M, col.astype(np.float32), np.asarray(h, np.float32), np.asarray(rough, np.float32))
    save(f"{o.name}_col.png", col); save(f"{o.name}_nrm.png", height_to_normal(h * 4, 3.0)); save(f"{o.name}_rgh.png", np.dstack([rough] * 3))
    mt = bpy.data.materials.new(o.name); mt.use_nodes = True; nt = mt.node_tree; bs = nt.nodes["Principled BSDF"]
    ti = nt.nodes.new("ShaderNodeTexImage"); ti.image = bpy.data.images.load(os.path.join(TEX, f"{o.name}_col.png"))
    nt.links.new(ti.outputs["Color"], bs.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = bpy.data.images.load(os.path.join(TEX, f"{o.name}_nrm.png")); tn.image.colorspace_settings.name = "Non-Color"
    nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(tn.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
    bs.inputs["Roughness"].default_value = float(np.mean(rough))
    if o.name == "Bulb": bs.inputs["Emission Color"].default_value = (1, 0.85, 0.6, 1); bs.inputs["Emission Strength"].default_value = 8
    o.data.materials.clear(); o.data.materials.append(mt)
    print("painted", o.name, res, int(M.sum()), "texels", flush=True)

for o in scn.objects: o.select_set(o.type == "MESH" and o is not bag_holder)
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "bunker.fbx"), use_selection=True, object_types={"MESH"},
                         mesh_smooth_type="FACE", path_mode="STRIP")
tris = 0
for o in scn.objects:
    if o.type == "MESH" and o is not bag_holder:
        o.data.calc_loop_triangles(); tris += len(o.data.loop_triangles)
print("triangles total", tris)

bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=200); g = new_obj("Ground", bm); g.location.z = -0.6
gm = bpy.data.materials.new("G"); gm.use_nodes = True; gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.14, 0.11, 1)
g.data.materials.append(gm)
bm = bmesh.new(); box(bm, (-60, D, -1), (60, 40, HGT + 1.5)); hill = new_obj("Hill", bm); hill.data.materials.append(gm)
world = bpy.data.worlds.new("W"); world.use_nodes = True; scn.world = world
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.58, 0.6, 1)
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN")); sun.data.energy = 2.5
sun.rotation_euler = (math.radians(55), 0, math.radians(-35)); scn.collection.objects.link(sun)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); scn.collection.objects.link(cam); scn.camera = cam
tg = bpy.data.objects.new("T", None); scn.collection.objects.link(tg); cam.constraints.new("TRACK_TO").target = tg
scn.render.engine = "CYCLES"; scn.cycles.device = "CPU"; scn.cycles.samples = 48; scn.view_settings.view_transform = "Standard"
scn.render.resolution_x, scn.render.resolution_y = 1280, 800
for nm, loc, look in (("front34", (-14, -30, 7), (0, 0, 4.5)), ("door", (-2, -11, 5.5), (0, 1.5, 4))):
    cam.location = loc; tg.location = look; cam.data.lens = 35
    scn.render.filepath = os.path.join(OUT, f"preview_{nm}.png"); bpy.ops.render.render(write_still=True)
print("done")
