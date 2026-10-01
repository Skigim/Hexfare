class_name UnitModel
extends Node3D
## A 3D unit assembled from KayKit parts: the Mannequin rig, animation clips from the shared
## animation packs, and weapon pieces held in hand slots. Driven by a "model" dictionary in
## data/units.json, e.g.
##   "model": {"rig": "Medium",
##             "right": {"scene": "sword_A"},
##             "left": {"scene": "shield_A", "rotation": [0, 90, 0]},
##             "clips": {"idle": "Melee_Blocking", "attack": "Melee_1H_Attack_Chop"}}
## Pieces are named by file stem (see the path constants). "clips" maps the roles below to clip
## names and only needs the roles that differ from DEFAULT_CLIPS. A role can also layer limbs
## from another clip: {"clip": "Walking_A", "left_arm": "Melee_Blocking"} walks with the shield
## arm held in the guard pose (see LIMBS). A piece can carry "rotation" (degrees), "position"
## and "scale", applied inside its hand slot.

const KAYKIT := "res://assets/KayKit_Character_Animations_1.1/"
const CHARACTER := KAYKIT + "Mannequin Character/characters/Mannequin_%s.glb"
const ANIMATIONS := KAYKIT + "Animations/gltf/Rig_%s/Rig_%s_%s.glb"
const WEAPON := "res://assets/KayKit_FantasyWeaponsBits_1.0_FREE/Assets/gltf/%s.gltf"
const ANIMATION_SETS := ["General", "CombatMelee", "CombatRanged", "MovementBasic", "MovementAdvanced"]

## What the game asks a unit to do, and the clip each role plays unless the data overrides it.
## idle and walk loop; attack and hit play once and fall back to idle; death holds its last frame.
const DEFAULT_CLIPS := {
	"idle": "Idle_A", "walk": "Walking_A", "attack": "Melee_1H_Attack_Chop",
	"hit": "Hit_A", "death": "Death_A",
}
const LOOPING_ROLES := ["idle", "walk"]
## Clips that loop when played directly (the packs don't mark loops).
const LOOPING_CLIPS := ["Idle", "Walking", "Running", "Blocking", "Aiming", "Crawling",
	"Crouching", "Sneaking", "Spellcasting", "Shooting"]
const BLEND_TIME := 0.15
## Bones a layered role can take from another clip.
const LIMBS := {
	"left_arm": ["upperarm.l", "lowerarm.l", "wrist.l", "hand.l"],
	"right_arm": ["upperarm.r", "lowerarm.r", "wrist.r", "hand.r"],
}

## The Mannequin rig has no handslot bones, so the slots are built here. KayKit weapons are
## modelled with the grip at the origin, the blade or haft along +Y, the edge or head along +X and
## a shield's face along +Z. Measured on the rig: hand bones run +Y down the fingers and +Z out
## of the back of the hand; the thumb is -X on the right hand and +X on the left. A slot sends a
## piece's +Y out of the thumb side of the fist and its +X toward the knuckles, so a sword's
## edge leads every swing; shields need "rotation": [0, 90, 0] to face the knuckles too.
const HAND_SLOTS := {
	"right": {"bone": "hand.r", "basis": Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))},
	"left": {"bone": "hand.l", "basis": Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))},
}
## From the hand bone (at the wrist) to the middle of the closed fist.
const GRIP := Vector3(0, 0.09, -0.02)

## Clip libraries are loaded once per rig and shared by every unit on it.
static var _libraries: Dictionary = {}

var player: AnimationPlayer
var skeleton: Skeleton3D
var clips: Dictionary = {}


## Builds a unit from a model dictionary; returns null (with a warning) if the rig is missing.
static func create(model: Dictionary) -> UnitModel:
	var rig: String = model.get("rig", "Medium")
	var body_scene := _load_scene(CHARACTER % rig)
	if body_scene == null:
		return null
	var unit := UnitModel.new()
	var body := body_scene.instantiate()
	unit.add_child(body)
	unit.skeleton = body.find_child("Skeleton3D", true, false)
	unit.clips = DEFAULT_CLIPS.duplicate()
	var overrides: Dictionary = model.get("clips", {})
	for role in overrides:
		var spec: Variant = overrides[role]
		unit.clips[role] = layered(rig, spec) if spec is Dictionary else String(spec)

	unit.player = AnimationPlayer.new()
	unit.player.name = "AnimationPlayer"
	unit.add_child(unit.player)
	unit.player.root_node = NodePath("../" + body.name)
	unit.player.add_animation_library("", library(rig))
	unit.player.playback_default_blend_time = BLEND_TIME
	unit.player.animation_finished.connect(unit._on_clip_finished)

	for hand in HAND_SLOTS:
		if model.has(hand):
			unit._hold(hand, model[hand])
	unit.act("idle")
	return unit


## Every clip from the animation packs for a rig, merged into one library (cached).
## The packs use the character's node names, so their track paths resolve unchanged.
static func library(rig: String) -> AnimationLibrary:
	if _libraries.has(rig):
		return _libraries[rig]
	var lib := AnimationLibrary.new()
	for set_name in ANIMATION_SETS:
		var scene := _load_scene(ANIMATIONS % [rig, rig, set_name])
		if scene == null:
			continue
		var source := scene.instantiate()
		var source_player: AnimationPlayer = source.find_child("AnimationPlayer", true, false)
		for clip in source_player.get_animation_list():
			if clip == "T-Pose" or lib.has_animation(clip):
				continue
			var anim: Animation = source_player.get_animation(clip).duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR if _loops(clip) else Animation.LOOP_NONE
			lib.add_animation(clip, anim)
		source.free()
	_libraries[rig] = lib
	return lib


## A clip whose LIMBS tracks come from other clips, e.g. {"clip": "Walking_A", "left_arm":
## "Melee_Blocking"}. Added to the rig's shared library under a descriptive name, which is returned.
static func layered(rig: String, spec: Dictionary) -> String:
	var lib := library(rig)
	var base: String = spec.get("clip", "")
	if not lib.has_animation(base):
		push_warning("UnitModel: no animation %s" % base)
		return base
	var clip_name := base
	for limb in LIMBS:
		if spec.has(limb):
			clip_name += " with %s %s" % [limb, spec[limb]]
	if lib.has_animation(clip_name):
		return clip_name
	var anim: Animation = lib.get_animation(base).duplicate()
	for limb in LIMBS:
		if not spec.has(limb):
			continue
		if not lib.has_animation(spec[limb]):
			push_warning("UnitModel: no animation %s" % spec[limb])
			continue
		var bones: Array = LIMBS[limb]
		for t in range(anim.get_track_count() - 1, -1, -1):
			if anim.track_get_path(t).get_concatenated_subnames() in bones:
				anim.remove_track(t)
		var overlay: Animation = lib.get_animation(spec[limb])
		for t in overlay.get_track_count():
			if overlay.track_get_path(t).get_concatenated_subnames() in bones:
				overlay.copy_track(t, anim)
	lib.add_animation(clip_name, anim)
	return clip_name


## Plays the clip for a role ("idle", "walk", "attack", "hit", "death").
func act(role: String) -> void:
	play(clips.get(role, role))


## Plays a clip by name, cross-fading from the current one (blend < 0 uses BLEND_TIME).
func play(clip: String, blend: float = -1.0) -> void:
	if not player.has_animation(clip):
		push_warning("UnitModel: no animation %s" % clip)
		return
	player.play(clip, blend)


func has_clip(clip: String) -> bool:
	return player.has_animation(clip)


func clip_length(clip: String) -> float:
	return player.get_animation(clip).length if player.has_animation(clip) else 0.0


static func _loops(clip: String) -> bool:
	if clip.ends_with("_Pose"):
		return false
	for key in LOOPING_CLIPS:
		if clip.contains(key):
			return true
	return false


## One-shot clips hand back to idle when they end; death holds its last frame.
func _on_clip_finished(clip: StringName) -> void:
	if clip != clips.death and not player.get_animation(clip).loop_mode:
		act("idle")


func _hold(hand: String, piece: Dictionary) -> void:
	var scene := _load_scene(WEAPON % piece.scene)
	if scene == null:
		return
	var slot := BoneAttachment3D.new()
	slot.name = hand.capitalize() + "Hand"
	slot.bone_name = HAND_SLOTS[hand].bone
	skeleton.add_child(slot)
	var grip := Node3D.new()
	grip.name = "Grip"
	grip.transform = Transform3D(HAND_SLOTS[hand].basis, GRIP)
	slot.add_child(grip)
	var item := scene.instantiate() as Node3D
	var rot: Array = piece.get("rotation", [0, 0, 0])
	var pos: Array = piece.get("position", [0, 0, 0])
	item.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	item.position = Vector3(pos[0], pos[1], pos[2])
	item.scale = Vector3.ONE * float(piece.get("scale", 1.0))
	grip.add_child(item)


static func _load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		push_warning("UnitModel: missing %s" % path)
		return null
	return load(path)
