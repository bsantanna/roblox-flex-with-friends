"""
blender_asset_helpers.py — reusable toolkit for the Flex-with-Friends asset pipeline:
"interpret an AI-generated .obj  ->  rebuild it as clean part-based geometry  ->  repaint  ->
bake  ->  export the .glb in place".

Why this exists: the raw OBJs under assets/source/<Id>/ are a single welded, untextured, ~40k-tri
shell — painting them fights the geometry. The reliable workflow is to treat the OBJ as a reference,
rebuild a clean part-based copy, give each part one material, bake to a single texture, and export
over the existing .glb so `make assets-upload` re-uploads just that asset (PATCHing its id). These
helpers were factored out of the Neighbor01 rebuild so each new asset doesn't reinvent them.

HOW TO USE (inside Blender, via the blender MCP `execute_blender_code` tool). Put this dir on
sys.path and import once — the import is cached for the life of the Blender process, so later
execute_blender_code calls can `import blender_asset_helpers as bah` cheaply:

    import sys
    sys.path.insert(0, "<flex-with-friends-dev skill dir>/scripts")  # base dir is printed when the skill loads
    import blender_asset_helpers as bah

Then drive the loop, RENDERING AFTER EVERY STAGE (never sign off from code):

    ref  = bah.import_reference("assets/source/Cab01/Cab01.obj", offset=(3,0,0))  # reference only
    info = bah.massing("REF")                       # read floors/roof/footprint from the real mesh
    bah.new_collection("Asset")                     # build into a fresh, active collection
    bah.box("Body", (0,0,0.3), (0.8,0.4,0.3))       # ... build clean parts (box / make_beam / poly_roof)
    bah.comic_lighting()
    bah.render_views("Asset", "/tmp/asset", "massing", ("front","q34","side"))
    bah.paint([("Roof","Mat_Roof"), (("Wall",),"Mat_Wall"), ("_gl","Mat_Glass")], collection="Asset")
    out  = bah.finalize_and_export("Asset", "assets/source/Cab01", "Cab01")   # overwrites .glb/.blend/.png
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector


# --------------------------------------------------------------------------- interpret

def import_reference(obj_path, name="REF", offset=(0.0, 0.0, 0.0)):
    """Import an OBJ as a *reference* (the thing you measure and copy, not the thing you export).
    Offset it aside so it doesn't overlap the rebuild. Returns the new object."""
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=obj_path)
    obj = next(o for o in bpy.data.objects if o not in before)
    obj.name = name
    obj.location = (obj.location.x + offset[0], obj.location.y + offset[1], obj.location.z + offset[2])
    return obj


def massing(obj_name, bands=15):
    """Read an object's massing: world bbox + per-height-band footprint (x/y span + vert count).
    The band table exposes floor heights, the roof line, and chimney/antenna positions — the
    information you need to rebuild it cleanly. Returns a JSON-serialisable dict."""
    obj = bpy.data.objects[obj_name]
    mw = obj.matrix_world
    vs = [mw @ v.co for v in obj.data.vertices]
    xs = [v.x for v in vs]; ys = [v.y for v in vs]; zs = [v.z for v in vs]
    zmin, zmax = min(zs), max(zs)
    H = (zmax - zmin) or 1e-6
    out = {"bbox": {"x": [round(min(xs), 3), round(max(xs), 3)],
                    "y": [round(min(ys), 3), round(max(ys), 3)],
                    "z": [round(zmin, 3), round(zmax, 3)]},
           "height": round(H, 3), "verts": len(vs), "bands": []}
    for i in range(bands):
        z0 = zmin + H * i / bands
        z1 = zmin + H * (i + 1) / bands
        bv = [v for v in vs if (z0 <= v.z < z1) or (i == bands - 1 and v.z >= z1)]
        if bv:
            out["bands"].append({"z": [round(z0, 2), round(z1, 2)], "n": len(bv),
                                 "x": [round(min(v.x for v in bv), 2), round(max(v.x for v in bv), 2)],
                                 "y": [round(min(v.y for v in bv), 2), round(max(v.y for v in bv), 2)]})
        else:
            out["bands"].append({"z": [round(z0, 2), round(z1, 2)], "n": 0})
    return out


# --------------------------------------------------------------------------- build

def new_collection(name, clear=True):
    """Create (or clear) a collection and make it the active one so new parts land in it."""
    c = bpy.data.collections.get(name)
    if c and clear:
        for o in list(c.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    if not c:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    for ch in bpy.context.view_layer.layer_collection.children:
        if ch.collection.name == name:
            bpy.context.view_layer.active_layer_collection = ch
    return c


def box(name, center, half):
    """Axis-aligned box. center=(x,y,z); half=(hx,hy,hz) HALF-extents. Uses size=2 so half-extents
    map 1:1 to scale — no factor-of-2 trap — and applies the scale immediately (active_object can
    drift inside loops, silently applying scale to the wrong mesh)."""
    bpy.ops.mesh.primitive_cube_add(size=2, location=center)
    o = bpy.context.active_object
    o.name = name
    o.scale = half
    bpy.ops.object.transform_apply(scale=True)
    return o


def make_beam(name, start, end, hw=0.03, hh=0.03):
    """Rectangular beam from start->end via explicit bmesh verts — NEVER a rotated cylinder/box
    (Euler order silently points it down the wrong axis). Use for any angled member: rafters,
    rails, axles, struts, pipes."""
    sx, sy, sz = start; ex, ey, ez = end
    dx, dy, dz = ex - sx, ey - sy, ez - sz
    L = math.sqrt(dx * dx + dy * dy + dz * dz)
    if L < 1e-6:
        return None
    fx, fy, fz = dx / L, dy / L, dz / L
    ux, uy, uz = (0, 0, 1) if abs(fz) < 0.99 else (1, 0, 0)
    rx, ry, rz = fy * uz - fz * uy, fz * ux - fx * uz, fx * uy - fy * ux
    rl = math.sqrt(rx * rx + ry * ry + rz * rz)
    rx, ry, rz = rx / rl, ry / rl, rz / rl
    upx, upy, upz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
    me = bpy.data.meshes.new(name)
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    bm = bmesh.new()
    vts = []
    for bx, by, bz in (start, end):
        for sgx, sgy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            vts.append(bm.verts.new((bx + rx * hw * sgx + upx * hh * sgy,
                                     by + ry * hw * sgx + upy * hh * sgy,
                                     bz + rz * hw * sgx + upz * hh * sgy)))
    for f in ((0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (0, 3, 2, 1), (4, 5, 6, 7)):
        bm.faces.new([vts[i] for i in f])
    bm.to_mesh(me); bm.free()
    return o


def poly_roof(name, faces, thickness=0.05):
    """Build a roof (or any flat-panel surface) from explicit quad/tri coordinate-lists, weld shared
    coords, then Solidify for thickness + an underside. The right tool for hip/gable roofs: real
    sloped planes, no rotation guesswork. `faces` = list of vertex-coordinate tuples."""
    bm = bmesh.new()
    cache = {}

    def V(c):
        k = tuple(round(x, 4) for x in c)
        if k not in cache:
            cache[k] = bm.verts.new(c)
        return cache[k]

    for f in faces:
        bm.faces.new([V(c) for c in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    m = o.modifiers.new("sol", "SOLIDIFY")
    m.thickness = thickness
    m.offset = 1.0
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="sol")
    return o


# --------------------------------------------------------------------------- verify

def bounds(name):
    """World-space bounding box of a part, as {'x':(min,max),'y':(...),'z':(...)}."""
    o = bpy.data.objects[name]
    mw = o.matrix_world
    vs = [mw @ v.co for v in o.data.vertices]
    return {"x": (min(v.x for v in vs), max(v.x for v in vs)),
            "y": (min(v.y for v in vs), max(v.y for v in vs)),
            "z": (min(v.z for v in vs), max(v.z for v in vs))}


def overlap(a, b, axis="z", min_overlap=0.005):
    """Confirm two parts physically overlap on `axis` (joints need >= ~5mm or they read as gaps)."""
    ba, bb = bounds(a), bounds(b)
    ov = min(ba[axis][1], bb[axis][1]) - max(ba[axis][0], bb[axis][0])
    return {"pair": (a, b), "axis": axis, "overlap": round(ov, 4), "ok": ov >= min_overlap}


# --------------------------------------------------------------------------- paint

def _s2l(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(h):
    """sRGB hex ('#F2C14E' or 'F2C14E') -> linear RGBA tuple for Base Color default_value."""
    h = h.lstrip("#")
    return (_s2l(int(h[0:2], 16) / 255), _s2l(int(h[2:4], 16) / 255), _s2l(int(h[4:6], 16) / 255), 1.0)


def flat_material(name, hexcolor, rough=0.62, spec=0.12, metal=0.0):
    """A flat 'comic' material: one solid base color, low spec, no metal, no texture noise.
    Glass reads better with a lower roughness (e.g. rough=0.22, spec=0.5)."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
    b = nt.nodes.new("ShaderNodeBsdfPrincipled"); b.location = (0, 0)
    b.inputs["Base Color"].default_value = hex_to_linear(hexcolor)
    b.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = spec
    if "Metallic" in b.inputs:
        b.inputs["Metallic"].default_value = metal
    nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    return m


def paint(rules, collection="Asset"):
    """Assign exactly one material per part. `rules` is an ordered list of (predicate, material),
    first match wins. A predicate is a substring (matched anywhere in the name), a tuple/list of
    name prefixes, or a callable(name)->bool. material is a Material or a material name. Put the
    most specific rules first. Returns a {material_name: count} summary."""
    coll = bpy.data.collections[collection]
    counts = {}

    def matches(nm, pred):
        if callable(pred):
            return pred(nm)
        if isinstance(pred, (tuple, list)):
            return nm.startswith(tuple(pred))
        return pred in nm

    for o in coll.objects:
        for pred, mat in rules:
            if matches(o.name, pred):
                mat = bpy.data.materials[mat] if isinstance(mat, str) else mat
                o.data.materials.clear()
                o.data.materials.append(mat)
                counts[mat.name] = counts.get(mat.name, 0) + 1
                break
    return counts


# --------------------------------------------------------------------------- render

def comic_lighting(sun_energy=3.0, world=(0.82, 0.86, 0.92), world_strength=0.9):
    """Soft, flat-ish lighting for reading shape and the comic palette (Eevee, sun + bright world,
    gentle AO). Creates a Camera/Light if the scene lacks them."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("World")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (*world, 1)
        bg.inputs[1].default_value = world_strength
    sun = bpy.data.objects.get("Light")
    if sun is None:
        sun = bpy.data.objects.new("Light", bpy.data.lights.new("Light", "SUN"))
        bpy.context.scene.collection.objects.link(sun)
    sun.data.type = "SUN"
    sun.data.energy = sun_energy
    sun.rotation_euler = (0.85, 0.12, -0.5)
    sun.data.angle = 0.2
    try:
        sc.eevee.use_gtao = True
        sc.eevee.gtao_distance = 0.2
    except Exception:
        pass


# named orbit directions: (direction vector, elevation factor * height)
VIEWS = {
    "front": ((0, -1, 0), 0.30), "q34": ((0.8, -1, 0.1), 0.30),
    "back": ((-0.4, 1, 0.1), 0.30), "side": ((1, -0.12, 0.05), 0.30),
    "left": ((-1, -0.12, 0.05), 0.30), "top": ((0.01, 0.01, 1), 0.0),
}


def _target_bbox(target):
    if isinstance(target, str) and target in bpy.data.collections:
        objs = list(bpy.data.collections[target].objects)
    elif isinstance(target, (list, tuple)):
        objs = [bpy.data.objects[t] if isinstance(t, str) else t for t in target]
    else:
        objs = [bpy.data.objects[target] if isinstance(target, str) else target]
    vs = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx


def render_views(target, out_dir, prefix="v", views=("front", "q34", "side"), res=820, k=1.6):
    """Render named orbit views framing `target` (an object name, a collection name, or a list of
    either). Returns {view: path}. This is the verification instrument — call it after EVERY build
    stage (massing -> roof -> windows -> paint -> final) and actually look at the images; geometry
    that floats/clips hides behind other parts, so one angle is never enough."""
    os.makedirs(out_dir, exist_ok=True)
    mn, mx = _target_bbox(target)
    center = (mn + mx) * 0.5
    size = mx - mn
    diag = size.length or 1.0
    sc = bpy.context.scene
    cam = bpy.data.objects.get("Camera")
    if cam is None:
        cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        bpy.context.scene.collection.objects.link(cam)
    sc.camera = cam
    sc.render.resolution_x = res
    sc.render.resolution_y = res
    paths = {}
    for name in views:
        dirv, elev = VIEWS[name]
        d = Vector(dirv).normalized()
        eye = center + d * diag * k + Vector((0, 0, size.z * elev))
        cam.location = eye
        cam.rotation_euler = (center - eye).normalized().to_track_quat("-Z", "Y").to_euler()
        p = os.path.join(out_dir, f"{prefix}_{name}.png")
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths[name] = p
    return paths


# --------------------------------------------------------------------------- finalize / export

def finalize_and_export(collection, out_dir, asset_id, tex_size=1024):
    """Join every part of `collection` into one object named `asset_id`, set origin to the base
    center, UV-unwrap, bake the per-part flat colors into one texture, consolidate to a single
    textured material, then overwrite <out_dir>/<asset_id>.glb, _BaseColor.png, and .blend.

    Roblox contract (see assets/PIPELINE.md): Y-up, origin at base center, ~original bbox so the
    manifest `scale`/placement still hold. Overwriting the .glb changes its hash, so
    `make assets-upload` re-uploads just this asset, PATCHing the existing id. Returns paths + counts."""
    coll = bpy.data.collections[collection]
    parts = list(coll.objects)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = asset_id
    obj.data.name = asset_id

    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

    if not obj.data.uv_layers:
        obj.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.151917, island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    img = bpy.data.images.get(asset_id + "_BaseColor")
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(asset_id + "_BaseColor", tex_size, tex_size)
    img.colorspace_settings.name = "sRGB"
    for slot in obj.material_slots:
        nt = slot.material.node_tree
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
    sc.render.bake.margin = 16
    sc.cycles.bake_type = "DIFFUSE"
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
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
    tex.image.colorspace_settings.name = "sRGB"
    b.inputs["Roughness"].default_value = 0.6
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.15
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    obj.data.materials.clear()
    obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = 0

    glb = os.path.join(out_dir, asset_id + ".glb")
    blend = os.path.join(out_dir, asset_id + ".blend")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    return {"glb": glb, "png": png, "blend": blend,
            "tris": len(obj.data.polygons), "verts": len(obj.data.vertices)}
