extends TestCase
## Every script must at least parse. CI does not run the UI, so this catches a rename or removed
## method that would break scripts/view or scripts/ui without any rules test noticing.


func test_all_scripts_load() -> void:
	var paths: Array[String] = []
	_collect("res://scripts", paths)
	paths.append("res://tests/ui_smoke_test.gd")
	assert_true(paths.size() > 30, "found the project's scripts")
	for path in paths:
		var script: Variant = load(path)
		assert_true(script is GDScript and script.can_instantiate(), "%s loads and parses" % path)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
