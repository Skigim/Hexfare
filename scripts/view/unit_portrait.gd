class_name UnitPortrait
extends SubViewport
## Renders one UnitModel into a transparent texture so the 2D map and UI can show it.
## Use `texture()` anywhere a Texture2D is expected; it updates while the model animates.

## Looking slightly down on the unit from the front, turned a little toward the viewer.
const CAMERA_POSITION := Vector3(0, 2.1, 6)
const CAMERA_TARGET := Vector3(0, 0.95, 0)

var model: UnitModel


static func create(model_def: Dictionary, size: int = 256) -> UnitPortrait:
	var unit := UnitModel.create(model_def)
	if unit == null:
		return null
	var portrait := UnitPortrait.new()
	portrait.model = unit
	portrait.size = Vector2i(size, size)
	portrait.transparent_bg = true
	portrait.own_world_3d = true
	portrait.msaa_3d = Viewport.MSAA_4X
	portrait.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	portrait.add_child(unit)
	unit.rotation_degrees.y = float(model_def.get("facing", 25))

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(model_def.get("frame", 3.0))
	camera.transform = Transform3D(Basis.looking_at(CAMERA_TARGET - CAMERA_POSITION), CAMERA_POSITION)
	portrait.add_child(camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	portrait.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.8
	camera.environment = env
	return portrait


func texture() -> ViewportTexture:
	return get_texture()
