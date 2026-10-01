class_name MapAssetLoader
extends RefCounted

## Instantiate any imported Godot 3D scene, or wrap a directly imported Mesh
## (the default import mode for OBJ) in a MeshInstance3D.
static func instantiate_model(path: String) -> Node3D:
	if path.is_empty():
		return null
	var resource = ResourceLoader.load(path)
	if resource is PackedScene:
		var instance: Node = (resource as PackedScene).instantiate()
		if instance is Node3D:
			return instance
		var wrapper = Node3D.new()
		wrapper.add_child(instance)
		return wrapper
	if resource is Mesh:
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = resource
		return mesh_instance
	return null

## Load a texture through Godot's importer first, then decode a project/user
## image directly when the resource is not imported (for example user://).
static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return resource
	var image = load_image(path)
	if image and not image.is_empty():
		return ImageTexture.create_from_image(image)
	return null

## Image.load_from_file detects the supported raster/vector encoding from file
## contents, allowing maps to use any image format enabled in this Godot build.
static func load_image(path: String) -> Image:
	if path.is_empty():
		return null
	var image = Image.load_from_file(path)
	if image and not image.is_empty():
		return image
	var global_path = ProjectSettings.globalize_path(path)
	if global_path != path:
		image = Image.load_from_file(global_path)
		if image and not image.is_empty():
			return image
	return null
