"""Lanternfall Blender model builder (Phase 1).

Run inside Blender:  exec(open(r"<repo>/art/tools/lanternfall_models.py").read())
then call build_all(), render_sheet(path) and export_all(out_dir).

Builds Pip, the Snuffers (Scamper, Shellback, Flutter), the heroes (Bramble,
Glint) and Gumdrop Glade props in the lantern style, then bakes textured
materials into one albedo image per model and exports .glb files for Godot.
Facing: Snuffers look toward +Y, heroes toward -Y (matches the game code).
"""
import bpy, bmesh, math, os
from mathutils import Vector

C = bpy.context


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [(x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1]


def _new_mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m, None, None
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m, m.node_tree, m.node_tree.nodes["Principled BSDF"]


def flat(name, col, rough=0.5, metal=0.0, emit=0.0, alpha=1.0):
    m, nt, b = _new_mat(name)
    if nt is None:
        return m
    b.inputs["Base Color"].default_value = srgb(col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = srgb(col)
        b.inputs["Emission Strength"].default_value = emit
    m["textured"] = 0
    return m


def textured(name, c1, c2, kind="noise", scale=6.0, rough=0.6, bump=0.25):
    m, nt, b = _new_mat(name)
    if nt is None:
        return m
    N, L = nt.nodes, nt.links
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    L.new(tc.outputs["Object"], mp.inputs["Vector"])
    if kind == "brick":
        t = N.new("ShaderNodeTexBrick")
        t.inputs["Color1"].default_value = srgb(c1)
        t.inputs["Color2"].default_value = srgb(c2)
        t.inputs["Mortar"].default_value = srgb("#4A3A2E")
        t.inputs["Mortar Size"].default_value = 0.03
        L.new(mp.outputs["Vector"], t.inputs["Vector"])
        L.new(t.outputs["Color"], b.inputs["Base Color"])
        fac = t.outputs["Fac"]
    else:
        if kind == "voronoi":
            t = N.new("ShaderNodeTexVoronoi")
            t.inputs["Scale"].default_value = 3.0
            fac_out = "Distance"
        elif kind == "wave":
            t = N.new("ShaderNodeTexWave")
            t.inputs["Scale"].default_value = 2.0
            t.inputs["Distortion"].default_value = 5.0
            fac_out = "Fac"
        else:
            t = N.new("ShaderNodeTexNoise")
            t.inputs["Scale"].default_value = 1.0
            t.inputs["Detail"].default_value = 6.0
            fac_out = "Fac"
        L.new(mp.outputs["Vector"], t.inputs["Vector"])
        ramp = N.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = srgb(c1)
        ramp.color_ramp.elements[1].color = srgb(c2)
        fac = t.outputs[fac_out]
        L.new(fac, ramp.inputs["Fac"])
        L.new(ramp.outputs["Color"], b.inputs["Base Color"])
    bp = N.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = bump
    L.new(fac, bp.inputs["Height"])
    L.new(bp.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = rough
    m["textured"] = 1
    return m


def M():
    return {
        "brass": textured("Brass", "#E0B04A", "#A8782A", "noise", 5.0, 0.32, 0.08),
        "glow": flat("Lantern Glow", "#FFC44D", 0.2, emit=4.0),
        "pip": flat("Pip Glow", "#FFC86A", 0.35, emit=3.0),
        "ink": flat("Ink", "#2A1E2E", 0.4),
        "eye": flat("Eye White", "#FFF8EC", 0.3),
        "blush": flat("Blush", "#FF8FB0", 0.6),
        "scamper": textured("Scamper Fur", "#8B6BE6", "#6646BF", "noise", 9.0, 0.8, 0.35),
        "shell_skin": textured("Shellback Skin", "#6E8FB6", "#4E6A93", "noise", 7.0, 0.7, 0.2),
        "shell": textured("Shell", "#8A6236", "#5E3F22", "voronoi", 6.0, 0.6, 0.5),
        "bone": flat("Spike", "#F2E6C8", 0.5),
        "flutter": textured("Flutter Fur", "#F07FC0", "#C9579C", "noise", 9.0, 0.7, 0.3),
        "wing": flat("Wing", "#F9C6E4", 0.3, emit=0.4),
        "skin": textured("Skin", "#F3CBA5", "#E5B48C", "noise", 4.0, 0.6, 0.05),
        "green": textured("Bramble Tunic", "#4FA44F", "#3B8240", "noise", 7.0, 0.8, 0.2),
        "leather": textured("Leather", "#8A5A34", "#6B4226", "noise", 6.0, 0.7, 0.2),
        "wood": textured("Warm Wood", "#C98B4E", "#8A5426", "wave", 3.0, 0.7, 0.2),
        "iron": flat("Iron", "#4A5068", 0.4, metal=0.6),
        "robe": textured("Glint Robe", "#F5B83D", "#E08A28", "noise", 6.0, 0.7, 0.15),
        "purple": textured("Glint Hat", "#7A4DC9", "#5B34A3", "noise", 6.0, 0.7, 0.15),
        "star": flat("Star Glow", "#FFE680", 0.2, emit=5.0),
        "stone": textured("Gate Stone", "#B9A6C9", "#8D7AA3", "brick", 3.0, 0.85, 0.3),
        "swirl": flat("Waygate Swirl", "#A77BF0", 0.2, emit=3.0),
        "licorice": textured("Licorice", "#3A2430", "#1E121A", "wave", 4.0, 0.35, 0.3),
        "licorice_red": textured("Red Licorice", "#E0465A", "#B02F42", "wave", 4.0, 0.35, 0.3),
        "stick": flat("Candy Stick", "#FAF4EA", 0.5),
        "gum_pink": textured("Gumdrop Pink", "#F58AB8", "#E06A9E", "noise", 12.0, 0.25, 0.4),
        "gum_yellow": textured("Gumdrop Yellow", "#FFD85A", "#F2B93A", "noise", 12.0, 0.25, 0.4),
        "gum_blue": textured("Gumdrop Blue", "#86CFF5", "#5FB2E6", "noise", 12.0, 0.25, 0.4),
        "candy_a": flat("Candy A", "#FF7AB6", 0.3),
        "candy_b": flat("Candy B", "#FFF4E6", 0.3),
        "candy_c": flat("Candy C", "#7FE3C8", 0.3),
    }


# ------------------------------------------------------------------ primitives

def _link(name, bm, mat, parent, loc, rot=(0, 0, 0), smooth=True, bevel=0.0):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    C.scene.collection.objects.link(o)
    o.parent = parent
    o.location = loc
    o.rotation_euler = rot
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = smooth
    if bevel:
        md = o.modifiers.new("Bevel", "BEVEL")
        md.width = bevel
        md.segments = 3
        md.limit_method = "ANGLE"
        o.modifiers.new("WN", "WEIGHTED_NORMAL")
    return o


def sph(n, r, m, p, loc, sc=(1, 1, 1), segs=24, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(8, segs // 2), radius=r)
    bmesh.ops.scale(bm, vec=Vector(sc), verts=bm.verts)
    return _link(n, bm, m, p, loc, rot)


def cyl(n, r1, r2, d, m, p, loc, rot=(0, 0, 0), segs=24, bevel=0.01, smooth=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=d)
    return _link(n, bm, m, p, loc, rot, smooth, bevel)


def box(n, s, m, p, loc, rot=(0, 0, 0), bevel=0.02):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=Vector(s), verts=bm.verts)
    return _link(n, bm, m, p, loc, rot, False, bevel)


def cone(n, r, d, m, p, loc, rot=(0, 0, 0), segs=12):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=0, depth=d)
    return _link(n, bm, m, p, loc, rot, True)


def torus(n, R, r, m, p, loc, rot=(0, 0, 0), seg=32, ring=10, arc=1.0):
    bm = bmesh.new()
    grid = []
    steps = seg if arc >= 1.0 else seg + 1
    for i in range(steps):
        a = 2 * math.pi * arc * i / seg
        row = []
        for j in range(ring):
            b = 2 * math.pi * j / ring
            row.append(bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b))))
        grid.append(row)
    for i in range(seg if arc >= 1.0 else seg):
        i2 = (i + 1) % steps if arc >= 1.0 else i + 1
        for j in range(ring):
            bm.faces.new((grid[i][j], grid[i2][j], grid[i2][(j + 1) % ring], grid[i][(j + 1) % ring]))
    return _link(n, bm, m, p, loc, rot)


def root(name, x=0.0, y=0.0):
    e = bpy.data.objects.new(name, None)
    C.scene.collection.objects.link(e)
    e.location = (x, y, 0)
    e.empty_display_size = 0.4
    return e


def eyes(prefix, p, mat, z, spread, r, fwd):
    d = 1 if fwd >= 0 else -1
    for side in (-1, 1):
        sph(f"{prefix}_Eye{side}", r, mat["eye"], p, (spread * side, fwd, z), sc=(1, 0.7, 1.15))
        sph(f"{prefix}_Pupil{side}", r * 0.55, mat["ink"], p, (spread * side * 1.05, fwd + d * r * 0.55, z + r * 0.1), sc=(1, 0.6, 1.1))
        sph(f"{prefix}_Shine{side}", r * 0.18, mat["eye"], p, (spread * side + r * 0.2, fwd + d * r * 0.85, z + r * 0.38), segs=8)


def lantern(prefix, p, base, s, mat):
    x, y, z = base
    S = lambda v: v * s
    cyl(f"{prefix}_LBottom", S(0.2), S(0.2), S(0.05), mat["brass"], p, (x, y, z + S(0.025)), segs=8)
    cyl(f"{prefix}_LGlass", S(0.15), S(0.15), S(0.32), mat["glow"], p, (x, y, z + S(0.21)), segs=8, bevel=0)
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        box(f"{prefix}_LPost{i}", (S(0.04), S(0.04), S(0.34)), mat["brass"], p,
            (x + S(0.17) * math.cos(a), y + S(0.17) * math.sin(a), z + S(0.21)), bevel=0.004)
    cyl(f"{prefix}_LRoof", S(0.24), S(0.06), S(0.16), mat["brass"], p, (x, y, z + S(0.45)), segs=8)
    sph(f"{prefix}_LFinial", S(0.05), mat["brass"], p, (x, y, z + S(0.56)), segs=10)


# ------------------------------------------------------------------ models

def build_pip(x, m):
    r = root("Pip", x)
    cyl("Pip_Base", 0.42, 0.38, 0.08, m["brass"], r, (0, 0, 0.04), segs=8)
    for i in range(6):
        a = i * math.pi / 3
        box(f"Pip_Bar{i}", (0.035, 0.035, 0.78), m["brass"], r, (0.38 * math.cos(a), 0.38 * math.sin(a), 0.47), bevel=0.004)
    cyl("Pip_Roof", 0.46, 0.08, 0.22, m["brass"], r, (0, 0, 0.94), segs=8)
    torus("Pip_Ring", 0.08, 0.018, m["brass"], r, (0, 0, 1.12), rot=(math.pi / 2, 0, 0), seg=16, ring=6)
    sph("Pip_Body", 0.27, m["pip"], r, (0, 0, 0.38), sc=(1.05, 1, 0.92))
    for side in (-1, 1):
        cone(f"Pip_Ear{side}", 0.07, 0.14, m["pip"], r, (0.15 * side, -0.02, 0.62), rot=(0, 0.35 * side, 0))
        torus(f"Pip_Eye{side}", 0.045, 0.012, m["ink"], r, (0.09 * side, -0.25, 0.42), rot=(math.pi / 2, 0, 0), seg=12, ring=6, arc=0.5)
        sph(f"Pip_Cheek{side}", 0.04, m["blush"], r, (0.16 * side, -0.22, 0.34), sc=(1, 0.5, 0.7))
    sph("Pip_Tuft", 0.06, m["pip"], r, (0.02, 0, 0.66), sc=(1, 1, 1.4))
    return r


def build_scamper(x, m):
    r = root("Scamper", x)
    sph("Sc_Body", 0.26, m["scamper"], r, (0, 0, 0.3), sc=(1, 0.95, 1.0))
    eyes("Sc", r, m, 0.36, 0.1, 0.075, 0.21)
    box("Sc_Grin", (0.12, 0.02, 0.025), m["ink"], r, (0, 0.25, 0.23), rot=(0.3, 0, 0), bevel=0.01)
    for side in (-1, 1):
        sph(f"Sc_Foot{side}", 0.08, m["scamper"], r, (0.12 * side, 0.05, 0.06), sc=(1, 1.4, 0.7))
        cone(f"Sc_Ear{side}", 0.06, 0.16, m["scamper"], r, (0.15 * side, 0, 0.55), rot=(0, 0.5 * side, 0))
    cyl("Sc_Antenna", 0.012, 0.012, 0.16, m["ink"], r, (0.02, -0.02, 0.62), rot=(0.25, 0, 0), segs=8)
    sph("Sc_AntennaBall", 0.04, m["blush"], r, (0.02, -0.04, 0.7), segs=10)
    return r


def build_shellback(x, m):
    r = root("Shellback", x)
    sph("Sb_Body", 0.3, m["shell_skin"], r, (0, 0.04, 0.26), sc=(1.05, 1.1, 0.8))
    sph("Sb_Shell", 0.33, m["shell"], r, (0, -0.06, 0.36), sc=(1.05, 1.0, 0.75))
    for i, (sx, sy, sz) in enumerate([(0, -0.06, 0.62), (0.18, -0.12, 0.52), (-0.18, -0.12, 0.52), (0.14, 0.1, 0.55), (-0.14, 0.1, 0.55), (0, -0.3, 0.42)]):
        cone(f"Sb_Spike{i}", 0.055, 0.16, m["bone"], r, (sx, sy, sz), rot=(-(sy * 1.6), sx * 1.6, 0), segs=8)
    sph("Sb_Head", 0.17, m["shell_skin"], r, (0, 0.3, 0.3))
    eyes("Sb", r, m, 0.36, 0.07, 0.055, 0.42)
    for side in (-1, 1):
        box(f"Sb_Brow{side}", (0.08, 0.02, 0.022), m["ink"], r, (0.07 * side, 0.45, 0.43), rot=(0, 0.35 * side, 0), bevel=0.006)
    for i, (fx, fy) in enumerate([(0.2, 0.18), (-0.2, 0.18), (0.2, -0.16), (-0.2, -0.16)]):
        sph(f"Sb_Foot{i}", 0.08, m["shell_skin"], r, (fx, fy, 0.07), sc=(1, 1.2, 0.8))
    return r


def build_flutter(x, m):
    r = root("Flutter", x)
    sph("Fl_Body", 0.2, m["flutter"], r, (0, 0, 0.3), sc=(1, 1, 1.05))
    eyes("Fl", r, m, 0.36, 0.08, 0.065, 0.16)
    torus("Fl_Smile", 0.04, 0.01, m["ink"], r, (0, 0.19, 0.25), rot=(math.pi / 2, math.pi, 0), seg=12, ring=6, arc=0.5)
    for side in (-1, 1):
        cyl(f"Fl_Antenna{side}", 0.01, 0.01, 0.16, m["ink"], r, (0.06 * side, -0.02, 0.55), rot=(0, 0.35 * side, 0), segs=6)
        sph(f"Fl_AntennaTip{side}", 0.03, m["star"], r, (0.09 * side, -0.02, 0.63), segs=8)
        hinge = bpy.data.objects.new("Wing_L" if side < 0 else "Wing_R", None)
        C.scene.collection.objects.link(hinge)
        hinge.parent = r
        hinge.location = (0.16 * side, -0.02, 0.36)
        sph(f"Fl_WingA{side}", 0.18, m["wing"], hinge, (0.17 * side, 0, 0.05), sc=(1, 0.12, 0.7), rot=(0, -0.3 * side, 0))
        sph(f"Fl_WingB{side}", 0.12, m["wing"], hinge, (0.13 * side, 0, -0.1), sc=(1, 0.12, 0.6), rot=(0, 0.4 * side, 0))
    return r


def build_bramble(x, m):
    r = root("Bramble", x)
    for side in (-1, 1):
        cyl(f"Br_Leg{side}", 0.07, 0.07, 0.2, m["leather"], r, (0.08 * side, 0, 0.1), segs=12)
        sph(f"Br_Boot{side}", 0.08, m["leather"], r, (0.08 * side, -0.03, 0.04), sc=(1, 1.3, 0.6))
    cyl("Br_Body", 0.2, 0.16, 0.38, m["green"], r, (0, 0, 0.38), segs=20)
    cyl("Br_Belt", 0.205, 0.205, 0.05, m["leather"], r, (0, 0, 0.28), segs=20)
    box("Br_Buckle", (0.06, 0.02, 0.045), m["brass"], r, (0, -0.2, 0.28), bevel=0.005)
    sph("Br_Head", 0.18, m["skin"], r, (0, 0, 0.72))
    eyes("Br", r, m, 0.74, 0.07, 0.05, -0.15)
    cone("Br_Hood", 0.21, 0.3, m["green"], r, (0, 0.03, 0.9), rot=(-0.25, 0, 0), segs=16)
    for side in (-1, 1):
        cyl(f"Br_Arm{side}", 0.05, 0.045, 0.26, m["green"], r, (0.23 * side, 0, 0.42), rot=(0, 0.3 * side, 0), segs=10)
        sph(f"Br_Hand{side}", 0.055, m["skin"], r, (0.28 * side, -0.02, 0.29))
    cyl("Br_HammerHandle", 0.022, 0.022, 0.38, m["wood"], r, (0.3, -0.08, 0.38), rot=(0.4, 0, 0), segs=8)
    box("Br_HammerHead", (0.16, 0.08, 0.08), m["iron"], r, (0.3, -0.15, 0.55), rot=(0.4, 0, 0), bevel=0.01)
    lantern("Br", r, (0, 0.2, 0.3), 0.55, m)
    return r


def build_glint(x, m):
    r = root("Glint", x)
    cyl("Gl_Robe", 0.24, 0.13, 0.55, m["robe"], r, (0, 0, 0.28), segs=20)
    cyl("Gl_Sash", 0.17, 0.165, 0.05, m["purple"], r, (0, 0, 0.42), segs=20)
    sph("Gl_Head", 0.17, m["skin"], r, (0, 0, 0.7))
    eyes("Gl", r, m, 0.72, 0.065, 0.048, -0.14)
    cyl("Gl_HatBrim", 0.24, 0.24, 0.03, m["purple"], r, (0, 0, 0.84), segs=20)
    cone("Gl_Hat", 0.15, 0.38, m["purple"], r, (0, 0.02, 1.02), rot=(0.12, 0, 0), segs=16)
    sph("Gl_HatStar", 0.04, m["star"], r, (0, 0.05, 1.2), segs=10)
    for side in (-1, 1):
        cyl(f"Gl_Sleeve{side}", 0.06, 0.08, 0.24, m["robe"], r, (0.2 * side, 0, 0.45), rot=(0, 0.35 * side, 0), segs=10)
        sph(f"Gl_Hand{side}", 0.05, m["skin"], r, (0.27 * side, -0.02, 0.33))
    cyl("Gl_Staff", 0.02, 0.02, 0.95, m["wood"], r, (-0.3, -0.04, 0.5), segs=8)
    torus("Gl_StaffRing", 0.07, 0.014, m["brass"], r, (-0.3, -0.04, 1.0), rot=(math.pi / 2, 0, 0), seg=16, ring=6)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.07)
    bmesh.ops.scale(bm, vec=Vector((1, 1, 1.6)), verts=bm.verts)
    _link("Gl_Crystal", bm, m["star"], r, (-0.3, -0.04, 1.02), smooth=False)
    return r


def build_gumdrop(x, m):
    r = root("Gumdrop", x)
    for i, (gx, gy, s, mat) in enumerate([(0, 0, 1.0, "gum_pink"), (0.26, 0.18, 0.7, "gum_yellow"), (-0.22, 0.2, 0.62, "gum_blue")]):
        sph(f"Gd_{i}", 0.3 * s, m[mat], r, (gx, gy, 0.0), sc=(1, 1, 1.15))
        for k in range(5):
            a = k * 1.26 + i
            sph(f"Gd_{i}_Sugar{k}", 0.025 * s, m["candy_b"], r, (gx + 0.22 * s * math.cos(a), gy + 0.22 * s * math.sin(a), 0.2 * s), segs=6)
    return r


def build_lollipop_tree(x, m):
    r = root("LollipopTree", x)
    cyl("Lp_Stick", 0.05, 0.05, 1.3, m["stick"], r, (0, 0, 0.65), segs=10)
    cyl("Lp_Disc", 0.45, 0.45, 0.12, m["candy_b"], r, (0, 0, 1.55), rot=(math.pi / 2, 0, 0), segs=32)
    for i, mat in enumerate(["candy_a", "candy_c", "candy_a", "candy_c"]):
        torus(f"Lp_Swirl{i}", 0.38 - i * 0.09, 0.035, m[mat], r, (0, -0.06, 1.55), rot=(math.pi / 2, 0, i * 0.8), seg=28, ring=6)
    sph("Lp_Center", 0.05, m["candy_a"], r, (0, -0.07, 1.55), segs=10)
    cyl("Lp_Mound", 0.3, 0.18, 0.12, m["gum_pink"], r, (0, 0, 0.06), segs=16)
    return r


def build_waygate(x, m):
    r = root("Waygate", x)
    box("Wg_Base", (1.0, 0.36, 0.14), m["stone"], r, (0, 0, 0.07), bevel=0.03)
    torus("Wg_Ring", 0.5, 0.1, m["stone"], r, (0, 0, 0.66), rot=(math.pi / 2, 0, 0), seg=32, ring=10)
    torus("Wg_Brass", 0.5, 0.03, m["brass"], r, (0, -0.1, 0.66), rot=(math.pi / 2, 0, 0), seg=32, ring=6)
    cyl("Wg_Swirl", 0.42, 0.42, 0.03, m["swirl"], r, (0, 0, 0.66), rot=(math.pi / 2, 0, 0), segs=32, bevel=0)
    for i in range(6):
        a = i * math.pi / 3
        sph(f"Wg_Gem{i}", 0.04, m["swirl"], r, (0.5 * math.cos(a), -0.12, 0.66 + 0.5 * math.sin(a)), segs=8)
    return r


def build_licorice_gate(x, m):
    r = root("LicoriceGate", x)
    for side in (-1, 1):
        cyl(f"Lg_Post{side}", 0.08, 0.08, 1.05, m["licorice"], r, (0.5 * side, 0, 0.52), segs=8)
        sph(f"Lg_Cap{side}", 0.11, m["gum_pink"], r, (0.5 * side, 0, 1.08))
    cyl("Lg_Top", 0.05, 0.05, 1.0, m["licorice"], r, (0, 0, 0.98), rot=(0, math.pi / 2, 0), segs=8)
    bars = bpy.data.objects.new("Bars", None)
    C.scene.collection.objects.link(bars)
    bars.parent = r
    for i in range(4):
        cyl(f"Lg_Bar{i}", 0.045, 0.045, 0.9, m["licorice_red"], bars, (-0.3 + i * 0.2, 0, 0.48), segs=8)
    return r


BUILDERS = [
    ("pip", "pip", build_pip), ("scamper", "snuffers", build_scamper), ("shellback", "snuffers", build_shellback),
    ("flutter", "snuffers", build_flutter), ("bramble", "heroes", build_bramble), ("glint", "heroes", build_glint),
    ("gumdrop", "props", build_gumdrop), ("lollipop_tree", "props", build_lollipop_tree),
    ("waygate", "props", build_waygate), ("licorice_gate", "props", build_licorice_gate),
]
KEEP_SEPARATE = {"Wing_L", "Wing_R", "Bars"}
ROOTS = {}


def build_all():
    bpy.ops.wm.read_homefile(use_empty=True)
    mats = M()
    for i, (fname, folder, fn) in enumerate(BUILDERS):
        ROOTS[fname] = fn(-6.75 + i * 1.5, mats)
    return ROOTS


def render_sheet(path):
    s = C.scene
    for o in [o for o in s.objects if o.type in ("LIGHT", "CAMERA") or o.name == "Ground"]:
        bpy.data.objects.remove(o, do_unlink=True)
    for name, rt in ROOTS.items():
        if name in ("waygate", "licorice_gate"):
            rt.location.y = 1.4
        elif name == "lollipop_tree":
            rt.location = (rt.location.x, 1.6, 0)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30)
    g = _link("Ground", bm, flat("Mint Ground", "#97D3AC", 0.9), None, (0, 0, 0), smooth=False)
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.4
    so = bpy.data.objects.new("Sun", sun)
    s.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), math.radians(8), math.radians(-30))
    fl = bpy.data.lights.new("Fill", "AREA")
    fl.energy = 400
    fl.size = 10
    fo = bpy.data.objects.new("Fill", fl)
    s.collection.objects.link(fo)
    fo.location = (0, -7, 6)
    fo.rotation_euler = (math.radians(45), 0, 0)
    cam = bpy.data.cameras.new("Camera")
    cam.lens = 30
    co = bpy.data.objects.new("Camera", cam)
    s.collection.objects.link(co)
    co.location = (0, -8.5, 3.6)
    co.rotation_euler = (Vector((0, 0.4, 0.6)) - co.location).to_track_quat("-Z", "Y").to_euler()
    s.camera = co
    w = bpy.data.worlds.new("World")
    s.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.08, 0.06, 0.16, 1)
    s.render.engine = "BLENDER_EEVEE"
    s.render.resolution_x = 1800
    s.render.resolution_y = 760
    s.view_settings.view_transform = "AgX"
    s.render.filepath = path
    bpy.ops.render.render(write_still=True)


def _metal_export(mat):
    if mat.name not in ("Brass",):
        return None
    m = bpy.data.materials.get("Brass_export") or bpy.data.materials.new("Brass_export")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb("#D9A441")
    b.inputs["Roughness"].default_value = 0.35
    b.inputs["Metallic"].default_value = 0.9
    return m


def export_all(out_root):
    s = C.scene
    prev = s.render.engine
    s.render.engine = "CYCLES"
    s.cycles.samples = 8
    done = {}
    for fname, folder, fn in BUILDERS:
        rt = ROOTS[fname]
        saved = rt.location.copy()
        rt.location = (0, 0, 0)
        C.view_layer.update()
        dg = C.evaluated_depsgraph_get()
        exp_root = bpy.data.objects.new(fname + "_export", None)
        s.collection.objects.link(exp_root)
        main_parts, separate = [], []
        for o in rt.children:
            if o.name.split(".")[0] in KEEP_SEPARATE:
                separate.append(o)
        sep_set = set()
        for o in separate:
            sep_set.update([o] + list(o.children_recursive))
        for o in rt.children_recursive:
            if o.type == "MESH" and o not in sep_set:
                main_parts.append(o)
        dups = []
        for o in main_parts:
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
            d = bpy.data.objects.new(o.name + "_x", me)
            s.collection.objects.link(d)
            d.matrix_world = o.matrix_world.copy()
            dups.append(d)
        bpy.ops.object.select_all(action="DESELECT")
        for d in dups:
            d.select_set(True)
        C.view_layer.objects.active = dups[0]
        bpy.ops.object.join()
        body = C.view_layer.objects.active
        body.name = fname + "_body"
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
        bpy.ops.object.mode_set(mode="OBJECT")
        img = bpy.data.images.new(fname + "_albedo", 1024, 1024)
        added = []
        for slot in body.material_slots:
            nt = slot.material.node_tree
            n = nt.nodes.new("ShaderNodeTexImage")
            n.image = img
            nt.nodes.active = n
            added.append((nt, n))
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=8, use_clear=True)
        for nt, n in added:
            nt.nodes.remove(n)
        bm_mat = bpy.data.materials.new(fname + "_baked")
        bm_mat.use_nodes = True
        b = bm_mat.node_tree.nodes["Principled BSDF"]
        t = bm_mat.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = img
        bm_mat.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = 0.6
        for i, slot in enumerate(body.material_slots):
            metal = _metal_export(slot.material)
            if metal:
                body.material_slots[i].material = metal
            elif slot.material.get("textured", 0):
                body.material_slots[i].material = bm_mat
        body.parent = exp_root
        export_objs = [exp_root, body]
        for o in separate:
            holder = bpy.data.objects.new(o.name.split(".")[0], None)
            s.collection.objects.link(holder)
            holder.matrix_world = o.matrix_world.copy()
            holder.parent = exp_root
            holder.matrix_world = o.matrix_world.copy()
            export_objs.append(holder)
            for ch in o.children_recursive:
                if ch.type != "MESH":
                    continue
                me = bpy.data.meshes.new_from_object(ch.evaluated_get(dg))
                d = bpy.data.objects.new(ch.name + "_x", me)
                s.collection.objects.link(d)
                d.matrix_world = ch.matrix_world.copy()
                d.parent = holder
                d.matrix_world = ch.matrix_world.copy()
                for i, slot in enumerate(d.material_slots):
                    metal = _metal_export(slot.material)
                    if metal:
                        d.material_slots[i].material = metal
                export_objs.append(d)
        bpy.ops.object.select_all(action="DESELECT")
        for o in export_objs:
            o.select_set(True)
        os.makedirs(os.path.join(out_root, folder), exist_ok=True)
        path = os.path.join(out_root, folder, fname + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB", export_apply=True)
        done[fname] = os.path.getsize(path)
        for o in export_objs:
            bpy.data.objects.remove(o, do_unlink=True)
        rt.location = saved
    s.render.engine = prev
    return done
