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

mat_stone = make_material("Stone", (0.38, 0.38, 0.40), 0.95)
mat_wood = make_material("Wood", (0.30, 0.18, 0.10), 0.88)
mat_fabric = make_material("Fabric", (0.82, 0.76, 0.65), 0.9)
mat_metal = make_material("Metal", (0.20, 0.20, 0.22), 0.5, 0.6)
mat_window = make_material("Window", (1.0, 0.84, 0.52), 0.2, 0.0, (1.0, 0.84, 0.52), 3.2)
mat_door = make_material("Door", (0.25, 0.15, 0.08), 0.88)

# Tower
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=1, depth=1, location=(0, 0, 4.25))
tower = bpy.context.active_object
tower.name = "Tower"
tower.scale = (3.6, 3.6, 8.5)
for v in tower.data.vertices:
    if v.co.z > 0:
        v.co.x *= (2.4/3.6)
        v.co.y *= (2.4/3.6)
tower.data.materials.append(mat_stone)

# Cap
bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=2.6, depth=3.0, location=(0, 0, 10.0))
cap = bpy.context.active_object
cap.name = "Cap"
cap.data.materials.append(mat_wood)

# RotorHub
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.4, depth=1.0, location=(0, -2.5, 8.5))
hub = bpy.context.active_object
hub.name = "RotorHub"
hub.rotation_euler = (1.5708, 0, 0)
hub.data.materials.append(mat_metal)

# Blades
for i in range(4):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    blade = bpy.context.active_object
    blade.name = f"Blade{i}"
    blade.scale = (0.5, 6.0, 0.1)
    blade.location = (0, -2.6, 8.5)
    blade.rotation_euler = (0, 0, i * 1.5708)
    blade.parent = hub
    blade.data.materials.append(mat_fabric)

# Door
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -3.6, 1.0))
door = bpy.context.active_object
door.name = "Door"
door.scale = (1.2, 0.2, 2.0)
door.data.materials.append(mat_door)

# Window
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -3.0, 4.0))
window = bpy.context.active_object
window.name = "Window"
window.scale = (0.8, 0.2, 1.0)
window.data.materials.append(mat_window)

# LanternLight placeholder at (0, 3.2, 2.8) in Godot -> (0, -2.8, 3.2) in Blender
bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, -2.8, 3.2))
lantern_light = bpy.context.active_object
lantern_light.name = "LanternLight"

# Collision cylinder
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=3.6, depth=8.5, location=(0, 0, 4.25))
collision = bpy.context.active_object
collision.name = "Collision"
collision.display_type = 'WIRE'

output_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "windmill.glb")
bpy.ops.export_scene.gltf(filepath=output_path, export_format='GLB')
