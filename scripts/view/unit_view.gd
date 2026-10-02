class_name UnitView
extends Node2D
## A unit on the map. Units with a sprite sheet (UnitSprite.has_sheet) are an animated figure on
## a civ-coloured base: it faces the way it walks, attacks, flinches when struck and plays its
## death before disappearing. Other units are a civ-coloured disc (military) or diamond
## (civilian) with a white icon. Both show a health bar and status pips.

const RADIUS := 23.0
const SPRITE_SCALE := 0.8
const SPRITE_STEP_TIME := 0.7    # seconds per hex for walking figures (tokens slide faster)
const STRIKE_DELAY := 0.3        # attack clip start to the blow landing
const BODY_TIME := 1.8           # a fallen figure lies this long before fading
const FADE_TIME := 0.6
## From the killing blow until the body is gone; a unit moving onto that hex waits this long.
const DEATH_TIME := STRIKE_DELAY + BODY_TIME + FADE_TIME
const BASE_RX := 24.0           # default stand; a sheet can ask for its own size ("base")
const BASE_RY := 10.0

var unit_id: int = -1
var coord := Hex.NONE
var color := Color.WHITE
var icon: Texture2D
var civilian := false
var hp_ratio := 1.0
var exhausted := false
var status := ""        # "", "fortified", "sleeping", "moving"
var sprite: UnitSprite
var dying := false      # killed in combat: play the death when the unit leaves the game
var founding := false   # founded a city: play "build" when the unit leaves the game
var _hit_delay := STRIKE_DELAY   # the last attack on this unit: its start to the blow landing
var _tween: Tween
var _badges: _Badges


func sync_from(u: Unit, player_color: Color, own: bool) -> void:
	unit_id = u.id
	color = player_color
	icon = Tex.icon(u.def().get("icon", "pawn"))
	civilian = u.is_civilian()
	hp_ratio = float(u.hp) / float(Defs.rules.units.max_hp)
	exhausted = own and u.moves_left <= 0
	status = "fortified" if u.fortified else ("sleeping" if u.sleeping else ("moving" if u.has_destination else ""))
	if sprite == null and UnitSprite.has_sheet(u.type):
		_make_sprite(u.type)
	if sprite != null:
		sprite.set_team_color(color)
		_badges.queue_redraw()
	queue_redraw()


func is_animating() -> bool:
	return _tween != null and _tween.is_running()


## Moves along world-space points after `delay` seconds (e.g. until a body on the destination
## has gone); a figure turns to face each step and walks. A figure that is mid-attack finishes
## the blow first.
func animate_path(points: Array, step_time: float = 0.09, delay: float = 0.0) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	if sprite != null:
		step_time = SPRITE_STEP_TIME
		if sprite.role == "attack":
			delay = maxf(delay, STRIKE_DELAY + 0.2)
	if delay > 0.0:
		_tween.tween_interval(delay)
	if sprite != null:
		_tween.tween_callback(sprite.act.bind("walk"))
	var prev := position
	for p in points:
		if sprite != null and prev.distance_to(p) > 1.0:
			_tween.tween_callback(sprite.face.bind(UnitSprite.direction_toward(p - prev)))
		_tween.tween_property(self, "position", p, step_time)
		prev = p
	if sprite != null:
		_tween.tween_callback(sprite.act.bind("idle"))


func lunge(toward: Vector2) -> void:
	if sprite != null:
		sprite.face(UnitSprite.direction_toward(toward - position))
		sprite.act("attack")
	if _tween != null and _tween.is_running():
		return
	var home := position
	_tween = create_tween()
	if sprite != null:
		_tween.tween_interval(STRIKE_DELAY - 0.08)   # step in on the downswing
	_tween.tween_property(self, "position", home.lerp(toward, 0.35), 0.08)
	_tween.tween_property(self, "position", home, 0.12)


## A ranged attack toward `toward` (world position): a figure turns to it and plays its attack.
## Returns the seconds until the shot leaves (the sheet's "release" mark; 0 for a token).
func shoot(toward: Vector2) -> float:
	if sprite == null:
		return 0.0
	sprite.face(UnitSprite.direction_toward(toward - position))
	sprite.act("attack")
	return maxf(sprite.mark_time("attack", "release"), 0.0)


## Struck by an attack from `from` (world position): a figure turns toward it and flinches
## when the blow lands, `delay` seconds from now (a shot lands later than a melee blow).
func struck(from: Vector2, delay: float = STRIKE_DELAY) -> void:
	_hit_delay = delay
	if sprite == null:
		return
	sprite.face(UnitSprite.direction_toward(from - position))
	get_tree().create_timer(delay).timeout.connect(_flinch)


func _flinch() -> void:
	if not dying:
		sprite.act("hit")


## Seconds from founding a city until the build reaches its last blow (when the city appears);
## 0 if this unit has no build to play.
func founding_time() -> float:
	if sprite == null or not sprite.has_role("build"):
		return 0.0
	return maxf(sprite.mark_time("build", "strike"), 0.0)


## The unit has left the game. A figure killed in combat plays its death, and a settler that
## founded a city its build; then it fades and frees itself. Anything else is freed at once.
func remove(animated: bool) -> void:
	if animated and founding and founding_time() > 0.0:
		_badges.hide()
		var t := create_tween()
		t.tween_callback(sprite.act.bind("build"))
		t.tween_interval(sprite.role_time("build") + 0.3)
		t.tween_property(self, "modulate:a", 0.0, FADE_TIME)
		t.tween_callback(queue_free)
		return
	if sprite == null or not dying or not animated:
		queue_free()
		return
	_badges.hide()
	get_parent().move_child(self, 0)   # the body lies under anyone who steps onto the hex
	var t := create_tween()
	t.tween_interval(_hit_delay)
	t.tween_callback(sprite.act.bind("death"))
	t.tween_interval(BODY_TIME)
	t.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	t.tween_callback(queue_free)


func _make_sprite(type: String) -> void:
	sprite = UnitSprite.create(type, color, false)
	if sprite == null:
		return
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	add_child(sprite)
	_badges = _Badges.new()
	add_child(_badges)


func _draw() -> void:
	if sprite != null:
		_draw_base()
		return
	var r := RADIUS
	var ring := _ring_color()
	if civilian:
		r = RADIUS * 0.85
		var d := _diamond(r + 3)
		draw_colored_polygon(_offset(d, Vector2(2, 3)), Color(0, 0, 0, 0.35))
		draw_colored_polygon(d, ring)
		draw_colored_polygon(_diamond(r), color)
	else:
		draw_circle(Vector2(2, 3), r + 3, Color(0, 0, 0, 0.35))
		draw_circle(Vector2.ZERO, r + 3, ring)
		draw_circle(Vector2.ZERO, r, color)
	if icon != null:
		var s := r * 1.15
		draw_texture_rect(icon, Rect2(-s * 0.5, -s * 0.5, s, s), false, Color(1, 1, 1, 0.75 if exhausted else 1.0))
	draw_badges(self, -r, r)


## The figure's stand: a civ-coloured oval with a white rim (grey once it has no moves left).
func _draw_base() -> void:
	var r := base_radii()
	draw_colored_polygon(_ellipse(r.x + 3, r.y + 2, Vector2(2, 3)), Color(0, 0, 0, 0.35))
	draw_colored_polygon(_ellipse(r.x + 3, r.y + 2), _ring_color())
	draw_colored_polygon(_ellipse(r.x, r.y), color.darkened(0.1))


## The stand's radii in this view's space.
func base_radii() -> Vector2:
	if sprite == null or sprite.base_size == Vector2.ZERO:
		return Vector2(BASE_RX, BASE_RY)
	return sprite.base_size * SPRITE_SCALE


## Health bar under the unit and a status pip at its top right, on `canvas`.
func draw_badges(canvas: CanvasItem, top: float, bottom: float) -> void:
	if hp_ratio < 1.0:
		var w := 44.0
		var y := bottom + 6
		canvas.draw_rect(Rect2(-w * 0.5 - 1, y - 1, w + 2, 7), Color(0, 0, 0, 0.8))
		var hp_color := Color("#7ed957") if hp_ratio > 0.6 else (Color("#f6d44a") if hp_ratio > 0.3 else Color("#ff6b5e"))
		canvas.draw_rect(Rect2(-w * 0.5, y, w * hp_ratio, 5), hp_color)
	if status != "":
		var pip := Vector2(RADIUS * 0.75, top + RADIUS * 0.25)
		canvas.draw_circle(pip, 9, Color(0.1, 0.12, 0.15, 0.95))
		var letter: String = {"fortified": "F", "sleeping": "Z", "moving": ">"}[status]
		canvas.draw_string(Tex.font(), pip + Vector2(-5, 6), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


func _ring_color() -> Color:
	return Color(0.55, 0.58, 0.62) if exhausted else Color.WHITE


static func _ellipse(rx: float, ry: float, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _diamond(r: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])


static func _offset(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out


## Draws the badges above the figure (children draw over their parent's own drawing).
class _Badges extends Node2D:
	func _draw() -> void:
		var v := get_parent() as UnitView
		v.draw_badges(self, -62.0, v.base_radii().y)
