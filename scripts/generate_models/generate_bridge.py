import bpy
import os

bpy.ops.wm.read_factory_settings(use_empty=True)

def make_material(name, color, roughness, metallic=0.0, emission=None, emission_energy=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1.0)
        bsdf.inputs['Emission Strength'].default_value = emission_energy
    return mat

mat_stone = make_material("Stone", (0.48, 0.49, 0.52), 0.85, 0.2)
mat_metal = make_material("Metal", (0.24, 0.26, 0.30), 0.4, 0.8)
mat_lantern = make_material("Lantern", (1.0, 0.95, 0.80), 0.2, 0.0, (1.0, 0.95, 0.80), 3.0)

# Deck
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.42))
deck = bpy.context.active_object
deck.name = "Deck"
deck.scale = (9.0, 36.0, 0.5)
deck.data.materials.append(mat_stone)

# Arches
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=1, depth=1, location=(0, -8.0, 0.42))
arch1 = bpy.context.active_object
arch1.name = "PierNorth"
arch1.scale = (9.0, 6.0, 4.0)
arch1.rotation_euler = (0, 1.5708, 0)
arch1.data.materials.append(mat_stone)

bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=1, depth=1, location=(0, 8.0, 0.42))
arch2 = bpy.context.active_object
arch2.name = "PierSouth"
arch2.scale = (9.0, 6.0, 4.0)
arch2.rotation_euler = (0, 1.5708, 0)
arch2.data.materials.append(mat_stone)

# Left Railing
bpy.ops.mesh.primitive_cube_add(size=1, location=(-4.3, 0, 1.42))
l_rail = bpy.context.active_object
l_rail.name = "LeftRailing"
l_rail.scale = (0.2, 36.0, 1.0)
l_rail.data.materials.append(mat_metal)

# Right Railing
bpy.ops.mesh.primitive_cube_add(size=1, location=(4.3, 0, 1.42))
r_rail = bpy.context.active_object
r_rail.name = "RightRailing"
r_rail.scale = (0.2, 36.0, 1.0)
r_rail.data.materials.append(mat_metal)

# Lantern Posts
positions = [
    ("NW", -4.3, 16.0),
    ("NE", 4.3, 16.0),
    ("SW", -4.3, -16.0),
    ("SE", 4.3, -16.0)
]

for name, x, y in positions:
    # Post
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.15, depth=2.0, location=(x, y, 1.42))
    post = bpy.context.active_object
    post.name = f"Post{name}"
    post.data.materials.append(mat_metal)
    
    # Lantern
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 2.6))
    lantern = bpy.context.active_object
    lantern.name = f"Lantern{name}"
    lantern.scale = (0.4, 0.4, 0.6)
    lantern.data.materials.append(mat_lantern)

# BridgeLight empties. (0, 3.2, -16) and (0, 3.2, 16) in Godot -> Blender Y is -Z and Z is Y.
bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 16.0, 3.2))
light_n = bpy.context.active_object
light_n.name = "BridgeLightNorth"

bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, -16.0, 3.2))
light_s = bpy.context.active_object
light_s.name = "BridgeLightSouth"

# Collision box
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.42))
collision = bpy.context.active_object
collision.name = "Collision"
collision.scale = (9.0, 36.0, 0.5)
collision.display_type = 'WIRE'

output_path = "/home/gretchen/Projects/cylinder/assets/models/bridge.glb"
bpy.ops.export_scene.gltf(filepath=output_path, export_format='GLB')
