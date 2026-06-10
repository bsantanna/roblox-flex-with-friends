# Build script for CentralBuilding — 4-floor apartment block on the Home plaza's central square.
# Geometry interprets the reference floor plan (doc: Dutch apartment plan; rooms: autolift garage,
# entree/stair lobby, keuken, eetkamer, kast-lobby, badkamer, 2x slaapkamer + hal, woonkamer,
# top slaapkamer + badkamer, two terraces). Ground floor is walkable: real doorway openings,
# every wall its own box so Roblox box collision keeps doorways passable (no mesh join).
# Units: built directly in STUDS (1 Blender unit = 1 stud), plan meters * SCALE.
# Run inside Blender with blender_asset_helpers (bah) importable:
#   exec(open(".../assets/source/CentralBuilding/build.py").read())

import bpy
import math
import blender_asset_helpers as bah

SCALE = 2.5  # studs per plan-meter (walkable interior; doors widened to 1.8 m = 4.5 studs)
CX, CY = 8.5, 11.25  # plan-bbox center (m) -> model centered on origin
PITCH = 8.0  # storey pitch in studs (slab 0.5 + wall 7.5, embedded 0.1 both ends)
DOOR_H = 5.8  # doorway opening height (studs) above slab top
TH_EXT = 0.4  # exterior wall thickness (m)
TH_INT = 0.32  # interior wall thickness (m)
FLOORS = 4

n_part = [0]


def X(xm):
    return (xm - CX) * SCALE


def Y(ym):
    return (ym - CY) * SCALE


def nm(prefix):
    n_part[0] += 1
    return f"{prefix}_{n_part[0]:03d}"


def slab(tag, x0, x1, y0, y1, z0, z1):
    return bah.box(
        nm(f"Slab_{tag}"),
        ((X(x0) + X(x1)) / 2, (Y(y0) + Y(y1)) / 2, (z0 + z1) / 2),
        ((x1 - x0) * SCALE / 2, (y1 - y0) * SCALE / 2, (z1 - z0) / 2),
    )


def wall_run(tag, axis, c, a0, a1, z0, z1, th=TH_EXT, openings=(), door_h=DOOR_H):
    """Wall along `axis` ('x' or 'y') at fixed plan coord c, from a0..a1 (m), z0..z1 (studs).
    `openings`: [(o0, o1), ...] door spans in m — full opening from z0 up door_h, lintel above.
    Runs extend th/2 past each end so perpendicular walls overlap at corners."""
    ext = th / 2
    hth = th * SCALE / 2
    spans = []  # (m0, m1, zb, zt)
    cur = a0 - ext
    for o0, o1 in sorted(openings):
        if o0 > cur:
            spans.append((cur, o0, z0, z1))
        spans.append((o0, o1, z0 + door_h, z1))  # lintel
        cur = o1
    spans.append((cur, a1 + ext, z0, z1))
    parts = []
    for m0, m1, zb, zt in spans:
        if m1 - m0 < 1e-4 or zt - zb < 1e-4:
            continue
        mid = (m0 + m1) / 2
        half_run = (m1 - m0) * SCALE / 2
        zc, hz = (zb + zt) / 2, (zt - zb) / 2
        kind = "Lin" if zb > z0 else f"Wall_{tag}"
        if axis == "x":
            parts.append(bah.box(nm(kind), (X(mid), Y(c), zc), (half_run, hth, hz)))
        else:
            parts.append(bah.box(nm(kind), (X(c), Y(mid), zc), (hth, half_run, hz)))
    return parts


def panel(tag, axis, c, face, m0, m1, zc, hh, prot=0.55, hth=0.18):
    """Flat decor panel (window glass / garage door) on a wall face. `face` = outward sign."""
    mid = (m0 + m1) / 2
    half_run = (m1 - m0) * SCALE / 2
    if axis == "x":
        return bah.box(nm(tag), (X(mid), Y(c) + face * prot, zc), (half_run, hth, hh))
    return bah.box(nm(tag), (X(c) + face * prot, Y(mid), zc), (hth, half_run, hh))


# Facades of the enclosed outline: (axis, fixed coord, outward face sign, run a0, run a1)
FACADES = {
    "S1": ("x", 0.0, -1, 0.0, 8.9),  # south: garage + stair lobby
    "E1": ("y", 8.9, 1, 0.0, 12.5),  # east: dining column
    "S2": ("x", 12.5, -1, 8.9, 14.2),  # woonkamer south
    "E2": ("y", 14.2, 1, 12.5, 17.6),  # woonkamer east (faces terrace R)
    "N1": ("x", 17.6, 1, 10.8, 14.2),  # woonkamer north
    "E3": ("y", 10.8, 1, 17.6, 22.5),  # top badkamer east
    "N2": ("x", 22.5, 1, 5.7, 10.8),  # top north
    "W2": ("y", 5.7, -1, 17.6, 22.5),  # top bedroom west (faces terrace TL)
    "N3": ("x", 17.6, 1, 0.0, 5.7),  # hall north (faces terrace TL)
    "W1": ("y", 0.0, -1, 0.0, 17.6),  # west: MAIN facade (faces plaza after rotation)
}

# Slab regions covering the footprint (enclosed A/B/C + terraces D/E)
REGIONS = {
    "A": (0.0, 8.9, 0.0, 17.6),
    "B": (8.9, 14.2, 12.5, 17.6),
    "C": (5.7, 10.8, 17.6, 22.5),
    "D": (0.0, 5.7, 17.6, 22.5),  # terrace / balconies TL
    "E": (14.2, 17.0, 12.5, 17.6),  # terrace / balconies R
}

RAILS = [  # open edges of the terraces: (axis, c, a0, a1)
    ("x", 22.5, 0.0, 5.7),
    ("y", 0.0, 17.6, 22.5),
    ("y", 17.0, 12.5, 17.6),
    ("x", 12.5, 14.2, 17.0),
    ("x", 17.6, 14.2, 17.0),
]


def rails(z0):
    for axis, c, a0, a1 in RAILS:
        hth = 0.18 * SCALE / 2
        mid, half_run = (a0 + a1) / 2, (a1 - a0) * SCALE / 2 + hth
        if axis == "x":
            bah.box(nm("Rail"), (X(mid), Y(c), z0 + 1.25), (half_run, hth, 1.25))
        else:
            bah.box(nm("Rail"), (X(c), Y(mid), z0 + 1.25), (hth, half_run, 1.25))


def floor_slabs(n, regions="ABCDE"):
    z0 = n * PITCH
    for r in regions:
        x0, x1, y0, y1 = REGIONS[r]
        slab(r, x0, x1, y0, y1, z0, z0 + 0.5)


def build_ground():
    z0, z1 = 0.4, PITCH + 0.1
    floor_slabs(0)
    rails(0.5)
    # Exterior walls with ground-floor openings
    wall_run("S1", "x", 0.0, 0.0, 8.9, z0, z1, openings=[(5.9, 7.7)])  # side entree door
    wall_run("E1", "y", 8.9, 0.0, 12.5, z0, z1)
    wall_run("S2", "x", 12.5, 8.9, 14.2, z0, z1)
    wall_run("E2", "y", 14.2, 12.5, 17.6, z0, z1, openings=[(14.2, 16.0)])  # glass door to terrace R
    wall_run("N1", "x", 17.6, 10.8, 14.2, z0, z1)
    wall_run("E3", "y", 10.8, 17.6, 22.5, z0, z1)
    wall_run("N2", "x", 22.5, 5.7, 10.8, z0, z1)
    wall_run("W2", "y", 5.7, 17.6, 22.5, z0, z1)
    wall_run("N3", "x", 17.6, 0.0, 5.7, z0, z1, openings=[(1.9, 3.7)])  # hall -> terrace TL
    wall_run("W1", "y", 0.0, 0.0, 17.6, z0, z1, openings=[(8.1, 9.9)])  # MAIN ENTRANCE
    # Interior walls
    wall_run("Garage", "y", 3.6, 0.0, 6.7, z0, z1, th=TH_INT)
    wall_run("Kitchen", "x", 2.9, 3.6, 8.9, z0, z1, th=TH_INT, openings=[(5.9, 7.7)])
    wall_run("GarLobby", "x", 6.7, 0.0, 3.6, z0, z1, th=TH_INT, openings=[(0.9, 2.7)])
    wall_run("LobbyDine", "y", 3.6, 6.7, 11.3, z0, z1, th=TH_INT, openings=[(8.1, 9.9)])
    wall_run("Bath", "x", 11.3, 0.0, 5.7, z0, z1, th=TH_INT, openings=[(0.9, 2.7)])
    wall_run("BathDine", "y", 5.7, 11.3, 15.9, z0, z1, th=TH_INT)
    wall_run("BathBeds", "x", 13.3, 0.0, 5.7, z0, z1, th=TH_INT)
    wall_run("BedSplit", "y", 2.85, 13.3, 15.9, z0, z1, th=TH_INT)
    wall_run("BedsHall", "x", 15.9, 0.0, 5.7, z0, z1, th=TH_INT, openings=[(0.7, 2.5), (3.1, 4.9)])
    wall_run("TopBed", "x", 17.6, 5.7, 10.8, z0, z1, th=TH_INT, openings=[(6.6, 8.4)])
    wall_run("TopBath", "y", 9.3, 17.6, 22.5, z0, z1, th=TH_INT, openings=[(19.0, 20.8)])
    # Garage door: dark recessed panel on the south facade (garage not enterable from outside)
    panel("Door", "x", 0.0, -1, 0.5, 3.1, 0.5 + 2.9, 2.9)
    # Spiral stair (decor) in the entree: center column + steps rotated about Z only
    cz = 7.5  # column top
    bpy.ops.mesh.primitive_cylinder_add(radius=0.35, depth=cz, location=(X(7.7), Y(1.45), 0.5 + cz / 2))
    bpy.context.active_object.name = nm("Stair_Col")
    for i in range(10):
        ang = math.radians(i * 33)
        zc = 0.8 + i * 0.68
        # build at origin, bake scale+rotation only (transform_apply defaults ALL flags True —
        # leaving location baked here is the bug that scatters parts around the world origin),
        # then move into place via object location.
        bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 0))
        st = bpy.context.active_object
        st.name = nm("Stair_Step")
        st.scale = (1.45, 0.55, 0.12)
        st.rotation_euler = (0, 0, ang)  # rotation about Z only (safe single-axis)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        st.location = (X(7.7) + math.cos(ang) * 1.0, Y(1.45) + math.sin(ang) * 1.0, zc)
    # Ground-floor windows (glass panels proud of the facade)
    for tag, fac, m0, m1 in [
        ("Glass", "W1", 2.0, 4.5),  # garage
        ("Glass", "W1", 11.6, 13.0),  # bathroom (high sill handled by zc)
        ("Glass", "W1", 13.6, 15.6),  # bedroom W
        ("Glass", "S1", 4.2, 5.4),  # stair lobby
        ("Glass", "E1", 3.5, 6.0),
        ("Glass", "E1", 7.0, 9.5),
        ("Glass", "E1", 10.0, 12.0),  # dining column
        ("Glass", "S2", 9.4, 11.2),
        ("Glass", "S2", 11.8, 13.6),  # woonkamer
        ("Glass", "E2", 16.3, 17.3),
        ("Glass", "N1", 11.4, 13.6),
        ("Glass", "E3", 19.0, 20.5),
        ("Glass", "N2", 6.2, 7.6),
        ("Glass", "N2", 8.2, 9.6),
        ("Glass", "W2", 18.5, 21.5),
        ("Glass", "N3", 4.0, 5.2),
    ]:
        axis, c, face, _, _ = FACADES[fac]
        panel(tag, axis, c, face, m0, m1, 0.4 + 4.4, 1.7)


def build_upper():
    for n in range(1, FLOORS):
        z0, z1 = n * PITCH + 0.4, (n + 1) * PITCH + 0.1
        floor_slabs(n)
        rails(n * PITCH + 0.5)
        for fac, (axis, c, face, a0, a1) in FACADES.items():
            wall_run(f"F{n}{fac}", axis, c, a0, a1, z0, z1)
            # balcony glass doors on the walls facing the terraces, else window band
            if fac in ("W2", "N3", "E2"):
                mid = (a0 + a1) / 2
                panel("Glass", axis, c, face, mid - 1.4, mid + 1.4, z0 + 3.1, 2.9)
                continue
            run = a1 - a0
            nwin = max(1, int(run // 2.6))
            step = run / nwin
            for i in range(nwin):
                w0 = a0 + step * (i + 0.5) - 0.8
                panel("Glass", axis, c, face, w0, w0 + 1.6, z0 + 4.0, 1.7)


def build_roof():
    zr = FLOORS * PITCH
    floor_slabs(FLOORS, regions="ABC")
    hth = TH_EXT * SCALE / 2
    for fac, (axis, c, face, a0, a1) in FACADES.items():
        mid, half_run = (a0 + a1) / 2, (a1 - a0) * SCALE / 2 + hth
        if axis == "x":
            bah.box(nm("Parapet"), (X(mid), Y(c), zr + 1.0), (half_run, hth, 1.1))
        else:
            bah.box(nm("Parapet"), (X(c), Y(mid), zr + 1.0), (hth, half_run, 1.1))
    rails(zr + 0.5)  # parapet on the open balcony edges of the roof level too


def build(stage="ground"):
    bah.new_collection("CB")
    n_part[0] = 0
    build_ground()
    if stage != "ground":
        build_upper()
        build_roof()
    return n_part[0]


def finalize_multi(out_dir, asset_id, tex_size=1024):
    """Like bah.finalize_and_export but WITHOUT the join: parts stay separate meshes so each
    imports as its own MeshPart with exact box collision (a joined concave mesh would seal the
    walkable ground floor). Joint multi-object UV unwrap -> one baked texture -> one shared
    textured material -> multi-object GLB."""
    import os

    coll = bpy.data.collections["CB"]
    parts = [o for o in coll.objects if o.type == "MESH"]
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
        if not o.data.uv_layers:
            o.data.uv_layers.new(name="UVMap")
    bpy.context.view_layer.objects.active = parts[0]

    # Multi-object edit-mode unwrap packs all islands into one shared 0-1 UV space.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.151917, island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")

    img = bpy.data.images.get(asset_id + "_BaseColor")
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(asset_id + "_BaseColor", tex_size, tex_size)
    img.colorspace_settings.name = "sRGB"
    mats = {s.material for o in parts for s in o.material_slots if s.material}
    for m in mats:
        nt = m.node_tree
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.select = True
        nt.nodes.active = tex

    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    sc.render.bake.margin = 4
    sc.cycles.bake_type = "DIFFUSE"
    bpy.ops.object.bake(type="DIFFUSE")

    png = os.path.join(out_dir, asset_id + "_BaseColor.png")
    img.filepath_raw = png
    img.file_format = "PNG"
    img.save()

    m = bpy.data.materials.get(asset_id + "_Painted") or bpy.data.materials.new(asset_id + "_Painted")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (400, 0)
    b = nt.nodes.new("ShaderNodeBsdfPrincipled"); b.location = (100, 0)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.location = (-300, 0); tex.image = img
    b.inputs["Roughness"].default_value = 0.6
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.15
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    for o in parts:
        o.data.materials.clear()
        o.data.materials.append(m)
        for poly in o.data.polygons:
            poly.material_index = 0

    glb = os.path.join(out_dir, asset_id + ".glb")
    blend = os.path.join(out_dir, asset_id + ".blend")
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    return {"glb": glb, "png": png, "blend": blend, "parts": len(parts),
            "tris": sum(len(o.data.polygons) for o in parts)}
