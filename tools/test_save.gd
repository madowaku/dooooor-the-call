extends SceneTree
## the digits heard so far must survive saving and continuing. run: godot --headless --path . -s tools/test_save.gd
func _init() -> void:
	var keep := ""
	var had := FileAccess.file_exists(Story.SAVE)
	if had:
		keep = FileAccess.get_file_as_string(Story.SAVE)
	Story.heard = [true, true, false]
	Story.save(3)
	Story.heard = [false, false, false]
	var ch := Story.saved()
	var ok: bool = ch == 3 and Story.heard == [true, true, false] and Story.memo() == "5  0  ・"
	print("continue from chapter %d, heard %s, pause screen shows '%s'" % [ch, Story.heard, Story.memo()])
	if had:
		var f := FileAccess.open(Story.SAVE, FileAccess.WRITE)
		f.store_string(keep)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Story.SAVE))
	print("SAVE TEST %s" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)
