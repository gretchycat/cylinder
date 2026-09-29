import bpy
import os
import math
import random

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for col in bpy.data.collections:
        bpy.data.collections.remove(col)
    for mat in bpy.data.materials:
        bpy.data.materials.remove(mat)
    for mesh in bpy.data.meshes:
        bpy.data.meshes.remove(mesh)

def create_material(name, color, roughness, double_sided=False):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    
    if bsdf:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = color + (1.0,)
            if "Roughness" in bsdf.inputs:
                bsdf.inputs["Roughness"].default_value = roughness
        else:
            # Blender 4.0+
            bsdf.inputs[0].default_value = color + (1.0,)
            bsdf.inputs[1].default_value = roughness

    if double_sided:
        mat.use_backface_culling = False
    
    return mat

def create_cylinder_trunk(name, radius, height, mat, segments=8):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=radius, depth=height, location=(0, 0, height/2))
    trunk = bpy.context.active_object
    trunk.name = name
    bpy.ops.object.shade_smooth()
    if trunk.data.materials:
        trunk.data.materials[0] = mat
    else:
        trunk.data.materials.append(mat)
    return trunk

def create_cone_trunk(name, radius1, radius2, height, mat, segments=8):
    bpy.ops.mesh.primitive_cone_add(vertices=segments, radius1=radius1, radius2=radius2, depth=height, location=(0, 0, height/2))
    trunk = bpy.context.active_object
    trunk.name = name
    bpy.ops.object.shade_smooth()
    trunk.data.materials.append(mat)
    return trunk

def create_foliage_blob(name, radius, location, mat, segments=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=segments, radius=radius, location=location)
    foliage = bpy.context.active_object
    foliage.name = name
    bpy.ops.object.shade_flat()
    foliage.data.materials.append(mat)
    return foliage

def create_collision_shape(name, radius, height):
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius, depth=height, location=(0, 0, height/2))
    col = bpy.context.active_object
    col.name = name + "-colonly"
    col.display_type = 'WIRE'
    return col

def export_tree(name, output_dir):
    filepath = os.path.join(output_dir, f"{name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=False,
        export_yup=True,
        export_apply=True
    )
    print(f"Exported {filepath}")

def generate_oak(output_dir):
    clear_scene()
    root = bpy.data.objects.new("Oak", None)
    bpy.context.scene.collection.objects.link(root)
    
    mat_trunk = create_material("Oak_Bark", (0.24, 0.16, 0.08), 0.9)
    mat_leaves = create_material("Oak_Leaves", (0.18, 0.44, 0.14), 0.85, True)
    
    trunk = create_cone_trunk("Trunk", 0.8, 0.4, 6.0, mat_trunk, 10)
    trunk.parent = root
    
    foliage_positions = [
        (0, 0, 7), (2, 2, 6.5), (-2, 2, 6.5), (2, -2, 6.5), (-2, -2, 6.5),
        (3, 0, 7.5), (-3, 0, 7.5), (0, 3, 7.5), (0, -3, 7.5), (0, 0, 9)
    ]
    
    for i, pos in enumerate(foliage_positions):
        rad = random.uniform(2.5, 3.5)
        f = create_foliage_blob(f"Canopy_{i}", rad, pos, mat_leaves, 2)
        f.scale = (1, 1, 0.8)
        f.parent = root
        
    col = create_collision_shape("Trunk", 0.8, 6.0)
    col.parent = root
    
    export_tree("oak", output_dir)

def generate_pine(output_dir):
    clear_scene()
    root = bpy.data.objects.new("Pine", None)
    bpy.context.scene.collection.objects.link(root)
    
    mat_trunk = create_material("Pine_Bark", (0.22, 0.14, 0.06), 0.9)
    mat_leaves = create_material("Pine_Leaves", (0.12, 0.36, 0.10), 0.85, True)
    
    trunk = create_cylinder_trunk("Trunk", 0.4, 14.0, mat_trunk, 8)
    trunk.parent = root
    
    for i in range(6):
        h = 2.0 + i * 2.0
        r1 = 3.5 - i * 0.5
        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=r1, radius2=0, depth=2.5, location=(0, 0, h + 1.25))
        f = bpy.context.active_object
        f.name = f"Tier_{i}"
        bpy.ops.object.shade_flat()
        f.data.materials.append(mat_leaves)
        f.parent = root
        
    col = create_collision_shape("Trunk", 0.4, 14.0)
    col.parent = root
    
    export_tree("pine", output_dir)

def generate_birch(output_dir):
    clear_scene()
    root = bpy.data.objects.new("Birch", None)
    bpy.context.scene.collection.objects.link(root)
    
    mat_trunk = create_material("Birch_Bark", (0.85, 0.82, 0.75), 0.9)
    mat_leaves = create_material("Birch_Leaves", (0.32, 0.58, 0.22), 0.85, True)
    
    trunk = create_cone_trunk("Trunk", 0.3, 0.1, 8.0, mat_trunk, 8)
    trunk.parent = root
    
    for i in range(12):
        x = random.uniform(-1.5, 1.5)
        y = random.uniform(-1.5, 1.5)
        z = random.uniform(4.0, 9.0)
        f = create_foliage_blob(f"Leaves_{i}", 1.2, (x, y, z), mat_leaves, 1)
        f.parent = root
        
    col = create_collision_shape("Trunk", 0.3, 8.0)
    col.parent = root
    
    export_tree("birch", output_dir)

def generate_willow(output_dir):
    clear_scene()
    root = bpy.data.objects.new("Willow", None)
    bpy.context.scene.collection.objects.link(root)
    
    mat_trunk = create_material("Willow_Bark", (0.28, 0.22, 0.14), 0.9)
    mat_leaves = create_material("Willow_Leaves", (0.28, 0.52, 0.18), 0.85, True)
    
    trunk = create_cone_trunk("Trunk", 0.9, 0.4, 5.0, mat_trunk, 12)
    trunk.parent = root
    
    for i in range(15):
        angle = (i / 15.0) * math.pi * 2
        r = random.uniform(2.0, 4.0)
        x = math.cos(angle) * r
        y = math.sin(angle) * r
        z = random.uniform(4.0, 7.0)
        
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.2, depth=random.uniform(4.0, 6.0), location=(x, y, z - 2.0))
        f = bpy.context.active_object
        f.name = f"Curtain_{i}"
        f.scale = (1, 1, 1)
        bpy.ops.object.shade_flat()
        f.data.materials.append(mat_leaves)
        f.parent = root
        
    col = create_collision_shape("Trunk", 0.9, 5.0)
    col.parent = root
    
    export_tree("willow", output_dir)

def generate_cherry_blossom(output_dir):
    clear_scene()
    root = bpy.data.objects.new("Cherry_Blossom", None)
    bpy.context.scene.collection.objects.link(root)
    
    mat_trunk = create_material("Cherry_Bark", (0.20, 0.12, 0.08), 0.9)
    mat_pink = create_material("Cherry_Pink", (0.92, 0.62, 0.72), 0.85, True)
    mat_green = create_material("Cherry_Green", (0.22, 0.44, 0.20), 0.85, True)
    
    trunk = create_cone_trunk("Trunk", 0.5, 0.2, 5.0, mat_trunk, 10)
    trunk.parent = root
    
    for i in range(14):
        x = random.uniform(-3, 3)
        y = random.uniform(-3, 3)
        z = random.uniform(4.0, 7.5)
        mat = mat_pink if random.random() < 0.7 else mat_green
        f = create_foliage_blob(f"Blossoms_{i}", random.uniform(1.0, 1.8), (x, y, z), mat, 2)
        f.parent = root
        
    col = create_collision_shape("Trunk", 0.5, 5.0)
    col.parent = root
    
    export_tree("cherry_blossom", output_dir)

def generate_dead_tree(output_dir):
    clear_scene()
    root = bpy.data.objects.new("Dead_Tree", None)
    bpy.context.scene.collection.objects.link(root)
    
    mat_trunk = create_material("Dead_Bark", (0.32, 0.28, 0.24), 0.95)
    
    trunk = create_cone_trunk("Trunk", 0.6, 0.3, 6.0, mat_trunk, 8)
    trunk.parent = root
    
    for i in range(5):
        angle = (i / 5.0) * math.pi * 2
        r = 0.5
        x = math.cos(angle) * r
        y = math.sin(angle) * r
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.2, radius2=0, depth=4.0, location=(x*3, y*3, 6.0 + 1.5))
        f = bpy.context.active_object
        f.name = f"Branch_{i}"
        f.rotation_euler = (0, random.uniform(0.5, 1.0), angle)
        bpy.ops.object.shade_smooth()
        f.data.materials.append(mat_trunk)
        f.parent = root
        
    col = create_collision_shape("Trunk", 0.6, 6.0)
    col.parent = root
    
    export_tree("dead_tree", output_dir)

if __name__ == "__main__":
    output_directory = "/home/gretchen/Projects/cylinder/assets/models/trees/"
    os.makedirs(output_directory, exist_ok=True)
    
    generate_oak(output_directory)
    generate_pine(output_directory)
    generate_birch(output_directory)
    generate_willow(output_directory)
    generate_cherry_blossom(output_directory)
    generate_dead_tree(output_directory)
