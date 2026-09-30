extends SceneTree
## Headless test runner:
##   godot --headless --path . -s res://tests/run_tests.gd
## Exits with code 1 if any test fails.

const SUITES := [
	"res://tests/test_hex.gd",
	"res://tests/test_data.gd",
	"res://tests/test_rules.gd",
	"res://tests/test_ai.gd",
	"res://tests/test_simulation.gd",
]


func _initialize() -> void:
	Defs.ensure_loaded()
	var total_checks := 0
	var all_failures: Array[String] = []
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			all_failures.append("%s: failed to load (parse error?)" % path)
			continue
		var suite: TestCase = script.new()
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_") or (only != "" and not only in name):
				continue
			suite.current_test = "%s::%s" % [path.get_file(), name]
			var started := Time.get_ticks_msec()
			suite.call(name)
			print("  ran %-55s %5d ms" % [suite.current_test, Time.get_ticks_msec() - started])
		total_checks += suite.checks
		all_failures.append_array(suite.failures)
	for f in all_failures:
		printerr("FAIL: " + f)
	print("%d checks, %d failures" % [total_checks, all_failures.size()])
	quit(1 if not all_failures.is_empty() else 0)
