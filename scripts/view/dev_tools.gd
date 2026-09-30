class_name DevTools
extends RefCounted
## Command-line helpers for automated runs, e.g.
##   godot --path . res://scenes/game.tscn -- --seed=5 --autoplay=40 --screenshot=out.png


## User args after "--" as a dictionary: "--key=value" -> {key: value}, "--flag" -> {flag: "true"}.
static func args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


## Saves a PNG of the viewport after `delay` seconds, then quits.
static func capture_and_quit(node: Node, path: String, delay: float = 1.0) -> void:
	await node.get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	node.get_viewport().get_texture().get_image().save_png(path)
	print("Saved screenshot to ", path)
	node.get_tree().quit()
