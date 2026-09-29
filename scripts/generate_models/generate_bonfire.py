import bpy
import math
import random

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for obj in bpy.data.objects:
        bpy.data.objects.remove(obj)

def create_material(name, color, roughness, metallic=0.0, emission_color=None, emission_energy=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    
    if emission_color:
        if 'Emission Color' in bsdf.inputs:
            bsdf.inputs['Emission Color'].default_value = emission_color
        elif 'Emission' in bsdf.inputs:
            bsdf.inputs['Emission'].default_value = emission_color
            
        if 'Emission Strength' in bsdf.inputs:
            bsdf.inputs['Emission Strength'].default_value = emission_energy
            
    return mat

def generate_bonfire():
    clear_scene()
    
    mat_stone = create_material("Stone", (0.22, 0.23, 0.25, 1.0), 0.92)
    mat_coal = create_material("Coal", (0.12, 0.06, 0.03, 1.0), 0.8, 0.0, (1.0, 0.32, 0.05, 1.0), 4.2)
    mat_log = create_material("Log", (0.18, 0.12, 0.07, 1.0), 0.90)

    stone_ring = bpy.data.objects.new("StoneRing", None)
    bpy.context.collection.objects.link(stone_ring)

    coals_empty = bpy.data.objects.new("Coals", None)
    bpy.context.collection.objects.link(coals_empty)

    logs_empty = bpy.data.objects.new("Logs", None)
    bpy.context.collection.objects.link(logs_empty)
    
    for i in range(16):
        angle = (i / 16) * math.pi * 2
        r = 2.45 + random.uniform(-0.15, 0.15)
        x = math.cos(angle) * r
        z = math.sin(angle) * r 
        
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.52)
        stone = bpy.context.active_object
        stone.name = f"Stone{i}"
        
        stone.location = (x, z, 0.2)
        stone.scale = (random.uniform(0.8, 1.2), random.uniform(0.8, 1.2), random.uniform(0.6, 1.4))
        stone.rotation_euler = (random.uniform(0, 3.14), random.uniform(0, 3.14), random.uniform(0, 3.14))
        
        stone.data.materials.append(mat_stone)
        stone.parent = stone_ring
        
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=2.2, depth=0.2)
    coals = bpy.context.active_object
    coals.name = "CoalBed"
    coals.location = (0, 0, 0.1)
    coals.data.materials.append(mat_coal)
    coals.parent = coals_empty
    
    for i in range(10):
        angle = (i / 10) * math.pi * 2
        radius = random.uniform(0.16, 0.22)
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=radius, depth=2.6)
        log = bpy.context.active_object
        log.name = f"Log{i}"
        
        log.location = (math.cos(angle) * 0.8, math.sin(angle) * 0.8, 1.0)
        log.rotation_euler = (0, 0.8, angle)
        
        log.data.materials.append(mat_log)
        log.parent = logs_empty
        
    flame_core = bpy.data.objects.new("FlameCore", None)
    flame_core.location = (0, 0, 0.35)
    bpy.context.collection.objects.link(flame_core)
    
    flame_outer = bpy.data.objects.new("FlameOuter", None)
    flame_outer.location = (0, 0, 0.30)
    bpy.context.collection.objects.link(flame_outer)
    
    for i in range(4):
        card = bpy.data.objects.new(f"FlameCard{i}", None)
        card.location = (0, 0, 2.4)
        card.rotation_euler = (0, 0, i * math.pi / 4)
        bpy.context.collection.objects.link(card)
        
    light = bpy.data.objects.new("BonfireLight", None)
    light.location = (0, 0, 2.0)
    bpy.context.collection.objects.link(light)
    
    bpy.context.view_layer.update()
    bpy.ops.export_scene.gltf(filepath="/home/gretchen/Projects/cylinder/assets/models/bonfire.glb", export_format="GLB", export_yup=True)

if __name__ == "__main__":
    generate_bonfire()
