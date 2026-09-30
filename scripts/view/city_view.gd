class_name CityView
extends Node2D
## City sprite on the map. The name banner is a separate CityBanner (drawn above fog).

var city_id: int = -1
var _sprite: Sprite2D


func _init() -> void:
	_sprite = Sprite2D.new()
	_sprite.position = Vector2(0, -6)
	add_child(_sprite)


func sync_from(city: City) -> void:
	city_id = city.id
	position = Hex.to_pixel(city.coord)
	var big := city.is_capital() or city.population >= 6
	_sprite.texture = Tex.object("castle_large" if big else "castle_small")
