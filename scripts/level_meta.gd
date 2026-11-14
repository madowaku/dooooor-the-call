class_name LevelMeta
extends RefCounted
## Everything in a level file that is not a rule: how rooms look and sound, what rings, what is heard.
## LevelLogic ignores these lines; this class ignores the map. The two never disagree because they never overlap.
##
##   room <letter> wall=<tex> floor=<tex> ceil=<tex> step=<wood|concrete|carpet|tile> light=<kind:tone> win=1 ac=<surface>
##   bell <prefix> <period> <on> <db> <wall_db>     the sound that is looked for (prefix_ring / _wall / _tail / _pipe)
##   line <stream> <period> <on>                    what is in the receiver after it is lifted
##   amb <stream> <db>                              a loop for the whole chapter
##   duct <x1> <y1> <x2> <y2>                       sound (only sound) travels between these two cells
##   goal grille | final_door <id> | source <x> <z> | phone_at <x> <z>
##   cam <letter> px py pz lx ly lz track fov       override the automatic camera of a room
##   prop <kind> ...                                box / glow / sign / pic / stain / solid (see Building._build_auto)

var rooms: Dictionary = {}
var props: Array = []
var cams: Dictionary = {}
var bell := "bell"
var period := 3.0
var on := 1.05
var source_db := 0.0
var wall_db := 0.0
var line := "line_next"
var line_period := 3.0
var line_on := 1.0
var ambs: Array = []
var ducts: Array = []
var goal := "phone"
var final_door := -1
var source := Vector3.INF
var phone_at := Vector3.INF

static func load_file(path: String) -> LevelMeta:
	var m := LevelMeta.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return m
	var in_map := false
	for raw in f.get_as_text().split("\n"):
		var t: String = raw.rstrip("\r").strip_edges()
		if in_map:
			if t == "end":
				in_map = false
			continue
		if t == "map":
			in_map = true
			continue
		if t == "" or t.begins_with("#"):
			continue
		var p := t.split(" ", false)
		match p[0]:
			"room":
				var st := {"wall": "wall_start", "floor": "floor_vinyl", "ceil": "ceil_panel", "step": "concrete"}
				for i in range(2, p.size()):
					var kv := p[i].split("=")
					st[kv[0]] = kv[1]
				m.rooms[p[1]] = st
			"bell":
				m.bell = p[1]
				if p.size() > 5:
					m.period = float(p[2])
					m.on = float(p[3])
					m.source_db = float(p[4])
					m.wall_db = float(p[5])
			"line":
				m.line = p[1]
				if p.size() > 3:
					m.line_period = float(p[2])
					m.line_on = float(p[3])
			"amb":
				m.ambs.append([p[1], float(p[2])])
			"duct":
				m.ducts.append([Vector2i(int(p[1]), int(p[2])), Vector2i(int(p[3]), int(p[4]))])
			"goal":
				m.goal = p[1]
			"final_door":
				m.final_door = int(p[1])
			"source":
				m.source = Vector3(float(p[1]), 0.9, float(p[2]))
			"phone_at":
				m.phone_at = Vector3(float(p[1]), 0.0, float(p[2]))
			"cam":
				m.cams[p[1]] = [Vector3(float(p[2]), float(p[3]), float(p[4])), Vector3(float(p[5]), float(p[6]), float(p[7])), float(p[8]), float(p[9])]
			"prop":
				m.props.append(Array(p).slice(1))
	return m
