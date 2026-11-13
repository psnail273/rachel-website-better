extends SceneTree
## The Godot arch step's runtime probe: what the arch checks can't read from the
## text. The arch step (tools/verify/arch) runs it once, headless, in one process:
##   godot --headless --path . -s res://tools/verify/_arch_probe.gd -- \
##       model res://model/score_model.gd scene res://main/main.tscn ...
## It prints one tab-separated line per fact, each starting with ARCH, then quits:
##   ARCH model <script> base <native base type>
##   ARCH model <script> node-field <property> <type>
##   ARCH signal <emitter> <signal> <target> <method> <persist 1|0> <scene>
##   ARCH ref <script> <node> <property> <node path> <scene> <subtree|scene>
##   ARCH error <path> <what went wrong>
## A signal line is a connection whose target is neither the emitter nor one of its
## ancestors; a ref line is an exported NodePath or Node-typed property
## (`node_paths`) whose path leaves the scene its node belongs to. A node that
## instances a scene belongs to that scene, so its path may not leave its own
## subtree (`subtree`), wherever the value is set; any other node belongs to the
## scene that defines it, so its path may not leave that scene (`scene`). Only
## connections to project scripts count, so the engine's own wiring is left out.
## Lines are sorted, so two runs print the same.

## Frames each scene runs before its tree is walked, so deferred wiring is done.
const SETTLE_FRAMES: int = 2

var _lines: PackedStringArray = []
var _scenes: PackedStringArray = []
var _next_scene: int = 0
var _current: Node = null
var _current_path: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in range(0, args.size() - 1, 2):
		match args[i]:
			"model":
				_probe_model(args[i + 1])
			"scene":
				_scenes.append(args[i + 1])


func _process(_delta: float) -> bool:
	if _current != null:
		_frames += 1
		if _frames < SETTLE_FRAMES:
			return false
		_walk_signals(_current)
		_current.queue_free()
		_current = null
		return false
	while _next_scene < _scenes.size():
		var path: String = _scenes[_next_scene]
		_next_scene += 1
		var packed: PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null:
			_emit(["error", path, "could not load the scene"])
			continue
		_probe_refs(path, packed)
		var node: Node = packed.instantiate()
		if node == null:
			_emit(["error", path, "could not instance the scene"])
			continue
		_current = node
		_current_path = path
		_frames = 0
		root.add_child(node)
		return false
	_lines.sort()
	var seen: Dictionary[String, bool] = { }
	for line: String in _lines:
		if not seen.has(line):
			seen[line] = true
			print(line)
	return true


func _emit(fields: Array[String]) -> void:
	_lines.append("ARCH\t" + "\t".join(PackedStringArray(fields)))

# --- R2: the plain model ---------------------------------------------------------


func _probe_model(path: String) -> void:
	var script: Script = ResourceLoader.load(path, "Script") as Script
	if script == null:
		_emit(["error", path, "could not load the script"])
		return
	var base: StringName = script.get_instance_base_type()
	if not ClassDB.is_parent_class(base, &"RefCounted"):
		_emit(["model", path, "base", String(base)])
	for prop: Dictionary in script.get_script_property_list():
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var type_name: String = _object_type(prop)
		if type_name != "" and _is_node_class(type_name):
			_emit(["model", path, "node-field", str(prop["name"]), type_name])


## The class an Object property (or an Array of them) holds, or "".
func _object_type(prop: Dictionary) -> String:
	var type: int = prop["type"]
	if type == TYPE_OBJECT:
		return str(prop["class_name"])
	var hint: int = prop["hint"]
	var hint_string: String = prop["hint_string"]
	if type == TYPE_ARRAY and hint == PROPERTY_HINT_ARRAY_TYPE:
		return hint_string
	if type == TYPE_ARRAY and hint_string.begins_with("%d/" % TYPE_OBJECT):
		return hint_string.get_slice(":", 1)
	return ""


## True when the engine class or project class_name extends Node.
func _is_node_class(type_name: String) -> bool:
	var name: String = type_name
	for _hop: int in range(50):
		if ClassDB.class_exists(name):
			return ClassDB.is_parent_class(name, &"Node")
		var base: String = ""
		for entry: Dictionary in ProjectSettings.get_global_class_list():
			if str(entry["class"]) == name:
				base = str(entry["base"])
		if base == "":
			return false
		name = base
	return false

# --- R5: signals go up -----------------------------------------------------------


func _walk_signals(scene_root: Node) -> void:
	var nodes: Array[Node] = [scene_root]
	nodes.append_array(scene_root.find_children("*", "", true, false))
	for emitter: Node in nodes:
		for sig: Dictionary in emitter.get_signal_list():
			var signal_name: StringName = sig["name"]
			for conn: Dictionary in emitter.get_signal_connection_list(signal_name):
				var callable: Callable = conn["callable"]
				var target: Node = callable.get_object() as Node
				if target == null or not _is_project_script(target):
					continue
				if target == emitter or target.is_ancestor_of(emitter):
					continue
				var method: String = callable.get_method()
				# The engine's own wiring names a native method, such as Control::_size_changed.
				if method.contains("::"):
					continue
				var flags: int = conn["flags"]
				var persist: String = "1" if flags & CONNECT_PERSIST else "0"
				_emit(
					[
						"signal",
						String(emitter.name),
						String(signal_name),
						String(target.name),
						method,
						persist,
						_current_path,
					]
				)


func _is_project_script(object: Object) -> bool:
	var attached: Variant = object.get_script()
	if not attached is Script:
		return false
	var script: Script = attached
	var path: String = script.resource_path
	return path.begins_with("res://") and not path.begins_with("res://addons/")

# --- R12: no sideways references -------------------------------------------------


func _probe_refs(path: String, packed: PackedScene) -> void:
	var state: SceneState = packed.get_state()
	for i: int in state.get_node_count():
		var script: Script = _node_script(state, i)
		if script == null:
			continue
		var declared: Dictionary[String, bool] = { }
		for prop: Dictionary in script.get_script_property_list():
			declared[str(prop["name"])] = true
		var node_path: NodePath = state.get_node_path(i)
		# A node that instances a scene belongs to that scene: its own subtree.
		var bound: String = "subtree" if state.get_node_instance(i) != null else "scene"
		for p: int in state.get_node_property_count(i):
			var prop_name: String = state.get_node_property_name(i, p)
			# Only the script's own properties: @export NodePaths and Node-typed
			# exports (`node_paths`), never an engine property such as root_node.
			if not declared.has(prop_name):
				continue
			var value: Variant = state.get_node_property_value(i, p)
			var refs: Array[NodePath] = []
			if value is NodePath:
				refs.append(value)
			elif value is Array:
				var items: Array = value
				for item: Variant in items:
					if item is NodePath:
						refs.append(item)
			for ref: NodePath in refs:
				if _leaves(node_path, ref, bound == "subtree"):
					var node_name: String = String(state.get_node_name(i))
					_emit(["ref", script.resource_path, node_name, prop_name, String(ref), path, bound])


## The script on node <i>, looking into the scene it instances when it sets none.
func _node_script(state: SceneState, i: int) -> Script:
	for p: int in state.get_node_property_count(i):
		if state.get_node_property_name(i, p) == &"script":
			var value: Variant = state.get_node_property_value(i, p)
			if not value is Script:
				return null
			var script: Script = value
			return script
	var instance: PackedScene = state.get_node_instance(i)
	if instance == null:
		return null
	return _node_script(instance.get_state(), 0)


## True when <ref>, taken from the node at <node_path>, points outside that
## node's subtree (<own_subtree>) or outside the scene (the scene's root is the
## floor).
func _leaves(node_path: NodePath, ref: NodePath, own_subtree: bool) -> bool:
	if ref.is_empty():
		return false
	if ref.is_absolute():
		return true
	var base: Array[String] = []
	for i: int in node_path.get_name_count():
		var part: String = String(node_path.get_name(i))
		if part != ".":
			base.append(part)
	var floor_depth: int = base.size() if own_subtree else 0
	var at: Array[String] = base.duplicate()
	for i: int in ref.get_name_count():
		var part: String = String(ref.get_name(i))
		if part == "..":
			if at.size() <= floor_depth:
				return true
			at.pop_back()
		elif part != ".":
			at.append(part)
	return false
