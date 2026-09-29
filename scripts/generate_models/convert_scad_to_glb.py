import bpy
import sys
import os

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

def convert():
    argv = sys.argv
    try:
        index = argv.index("--") + 1
    except ValueError:
        index = len(argv)
        
    args = argv[index:]
    if len(args) < 3:
        print("Usage: blender --background --python convert_scad_to_glb.py -- <input.stl> <output.glb> <preset>")
        return
        
    input_stl = args[0]
    output_glb = args[1]
    preset = args[2]
    
    clear_scene()
    
    bpy.ops.import_mesh.stl(filepath=input_stl)
    obj = bpy.context.selected_objects[0]
    
    if preset == "lamp_post":
        obj.name = "LampPost"
        mat = create_material("Metal", (0.16, 0.18, 0.22, 1.0), 0.35, 0.85)
    elif preset == "beacon_lantern":
        obj.name = "BeaconLantern"
        mat = create_material("Metal", (0.18, 0.20, 0.24, 1.0), 0.30, 0.80)
        
    obj.data.materials.append(mat)
    
    if preset == "lamp_post":
        glow_mat = create_material("Glow", (1.0, 0.8, 0.2, 1.0), 1.0, 0.0, (1.0, 0.8, 0.2, 1.0), 5.0)
        obj.data.materials.append(glow_mat)
        for poly in obj.data.polygons:
            z = poly.center[2]
            if 3.9 < z < 4.7 and abs(poly.center[0] - 0.95) < 0.3:
                poly.material_index = 1
                
    elif preset == "beacon_lantern":
        glow_mat = create_material("BeaconGlow", (0.30, 0.90, 1.0, 1.0), 1.0, 0.0, (0.30, 0.90, 1.0, 1.0), 5.0)
        obj.data.materials.append(glow_mat)
        for poly in obj.data.polygons:
            z = poly.center[2]
            if 2.2 < z < 2.9 and (poly.center[0]**2 + poly.center[1]**2) < 0.11: 
                # r=0.32 -> r^2=0.1024, so <0.11 captures the sphere but maybe not cage?
                # Actually sphere and cage overlap. Let's just make the top part glow.
                poly.material_index = 1
                
    bpy.ops.export_scene.gltf(filepath=output_glb, export_format="GLB", export_yup=True)

if __name__ == "__main__":
    convert()
