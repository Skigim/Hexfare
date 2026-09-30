class_name CameraRig
extends Camera2D
## Pan with WASD/arrow keys or middle-mouse drag; zoom toward the cursor with the wheel.

const PAN_SPEED := 1100.0
const MIN_ZOOM := 0.3
const MAX_ZOOM := 1.6

var bounds := Rect2()
var _dragging := false
var _tween: Tween


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x
		_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_at(mb.position, 1.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_at(mb.position, 1.0 / 1.12)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		_clamp()


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var half := get_viewport_rect().size * 0.5
	var world_before := position + (screen_pos - half) / zoom.x
	var z := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	position = world_before - (screen_pos - half) / z
	_clamp()


func set_zoom_level(z: float) -> void:
	z = clampf(z, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	_clamp()


func focus_on(world_pos: Vector2, animate: bool = true) -> void:
	if _tween != null:
		_tween.kill()
	if not animate:
		position = world_pos
		_clamp()
		return
	_tween = create_tween()
	_tween.tween_property(self, "position", _clamped(world_pos), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _clamp() -> void:
	position = _clamped(position)


func _clamped(p: Vector2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return p
	return Vector2(clampf(p.x, bounds.position.x, bounds.end.x), clampf(p.y, bounds.position.y, bounds.end.y))
