import bpy
import os

bpy.ops.wm.read_factory_settings(use_empty=True)

def make_material(name, color, roughness, emission=None, emission_energy=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Roughness'].default_value = roughness
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1.0)
        bsdf.inputs['Emission Strength'].default_value = emission_energy
    return mat

mat_stone = make_material("Stone", (0.32, 0.33, 0.35), 0.94)
mat_wood = make_material("Wood", (0.42, 0.28, 0.16), 0.88)
mat_roof = make_material("Roof", (0.48, 0.20, 0.14), 0.82)
mat_door = make_material("Door", (0.25, 0.15, 0.08), 0.88)
mat_window = make_material("Window", (1.0, 0.84, 0.52), 0.2, (1.0, 0.84, 0.52), 3.2)

# Foundation
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.5))
foundation = bpy.context.active_object
foundation.name = "Foundation"
foundation.scale = (6.0, 5.0, 1.0)
foundation.data.materials.append(mat_stone)

# Walls
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 2.5))
walls = bpy.context.active_object
walls.name = "Walls"
walls.scale = (5.8, 4.8, 3.0)
walls.data.materials.append(mat_wood)

# Roof
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 4.65))
roof = bpy.context.active_object
roof.name = "Roof"
roof.scale = (6.4, 5.4, 1.3)
for v in roof.data.vertices:
    if v.co.z > 0:
        v.co.x = 0
roof.data.materials.append(mat_roof)

# Chimney
bpy.ops.mesh.primitive_cube_add(size=1, location=(3.0, 0, 3.0))
chimney = bpy.context.active_object
chimney.name = "Chimney"
chimney.scale = (0.8, 1.2, 6.0)
chimney.data.materials.append(mat_stone)

# Door
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -2.45, 1.0))
door = bpy.context.active_object
door.name = "Door"
door.scale = (1.2, 0.1, 2.0)
door.data.materials.append(mat_door)

# WindowFront
bpy.ops.mesh.primitive_cube_add(size=1, location=(-1.5, -2.45, 2.0))
win_front = bpy.context.active_object
win_front.name = "WindowFront"
win_front.scale = (1.0, 0.1, 1.2)
win_front.data.materials.append(mat_window)

# WindowSide
bpy.ops.mesh.primitive_cube_add(size=1, location=(2.95, -1.5, 2.0))
win_side = bpy.context.active_object
win_side.name = "WindowSide"
win_side.scale = (0.1, 1.0, 1.2)
win_side.data.materials.append(mat_window)

# WindowLight empty
bpy.ops.object.empty_add(type='PLAIN_AXES', location=(-1.6, -2.8, 2.1))
window_light = bpy.context.active_object
window_light.name = "WindowLight"

# Collision box
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 2.65))
collision = bpy.context.active_object
collision.name = "Collision"
collision.scale = (6.4, 5.4, 5.3)
collision.display_type = 'WIRE'

# Export
output_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "house.glb")
bpy.ops.export_scene.gltf(filepath=output_path, export_format='GLB')
