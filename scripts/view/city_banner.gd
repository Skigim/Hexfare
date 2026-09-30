class_name CityBanner
extends Node2D
## Name plate above a city: population, name, capital star, production and health bars.

const FONT_SIZE := 20

var city_name := ""
var population := 1
var color := Color.WHITE
var capital := false
var production_ratio := -1.0   # < 0 hides the bar (foreign cities)
var hp_ratio := 1.0


func sync_from(state: GameState, city: City, own: bool) -> void:
	position = Hex.to_pixel(city.coord) + Vector2(0, -58)
	city_name = city.name
	population = city.population
	color = state.player(city.owner).color
	capital = city.is_capital()
	hp_ratio = float(city.hp) / float(Combat.city_max_hp(city))
	production_ratio = -1.0
	if own and not city.build.is_empty():
		production_ratio = clampf(float(city.production) / CityRules.item_cost(city.build.kind, city.build.id), 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var font := Tex.font()
	var label := city_name
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var pop_w := 30.0
	var star_w := 18.0 if capital else 0.0
	var width := pop_w + text_size.x + star_w + 22.0
	var rect := Rect2(-width * 0.5, -16, width, 32)
	var bg := UITheme.box(Color(color.darkened(0.35), 0.95), Color(0, 0, 0, 0.6), 7, 0)
	bg.draw(get_canvas_item(), rect)
	# Population bubble
	var pop_center := Vector2(rect.position.x + 17, 0)
	draw_circle(pop_center, 12, Color(0.08, 0.1, 0.13, 0.95))
	var pop_text := str(population)
	var pop_size := font.get_string_size(pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	draw_string(font, pop_center + Vector2(-pop_size.x * 0.5, 6), pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	var x := rect.position.x + pop_w + 4
	if capital:
		var star := Tex.icon("star")
		if star != null:
			draw_texture_rect(star, Rect2(x, -8, 16, 16), false, UITheme.ACCENT)
		x += star_w
	draw_string_outline(font, Vector2(x, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(x, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)
	var bar_y := rect.end.y + 2
	if production_ratio >= 0.0:
		draw_rect(Rect2(rect.position.x + 6, bar_y, width - 12, 5), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(rect.position.x + 6, bar_y, (width - 12) * production_ratio, 5), Tex.YIELD_COLORS.production)
		bar_y += 6
	if hp_ratio < 1.0:
		draw_rect(Rect2(rect.position.x + 6, bar_y, width - 12, 5), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(rect.position.x + 6, bar_y, (width - 12) * hp_ratio, 5), UITheme.BAD)
