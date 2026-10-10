extends Node

# Side-Quest System
# NPCs offer quests on dialogue (D key). Press M to accept. Quests track
# progress, complete with reward, and fail on timeout. This is the "NPCs give
# you work" system from spec.md section 11 (Future missions).

var active_quest: Dictionary = {}
var quest_pool: Array[Dictionary] = []

func _ready() -> void:
	quest_pool = [
		{"id": "collect_money", "type": "collect", "target": "money", "count": 3,
		 "reward": 150, "time_limit": 60.0, "desc": "Bring me 3 money bags from the streets."},
		{"id": "collect_ammo", "type": "collect", "target": "ammo", "count": 5,
		 "reward": 200, "time_limit": 90.0, "desc": "Find 5 ammo crates, they're scattered around."},
		{"id": "escort_citizen", "type": "escort", "target": "shop",
		 "reward": 300, "time_limit": 45.0, "desc": "Walk me to the shop on 3rd. I'm not going alone."},
		{"id": "deliver_package", "type": "deliver", "target": "office",
		 "reward": 250, "time_limit": 60.0, "desc": "Take this package to the office on 7th. Don't drop it."},
		{"id": "kill_thug", "type": "kill", "target": "thug", "count": 2,
		 "reward": 500, "time_limit": 120.0, "desc": "There are some thugs hanging near the docks. Make them disappear."},
		{"id": "lose_cops", "type": "survive", "target": "wanted",
		 "reward": 400, "time_limit": 30.0, "desc": "Lose the cops for 30 seconds and I'll pay you."},
	]

func offer_quest(npc_index: int) -> Dictionary:
	var q: Dictionary = quest_pool[npc_index % quest_pool.size()].duplicate()
	q["offered"] = true
	q["accepted"] = false
	q["completed"] = false
	q["npc_index"] = npc_index
	q["timer"] = q["time_limit"]
	q["progress"] = 0
	return q

func accept_quest(quest_data: Dictionary) -> void:
	quest_data["accepted"] = true
	quest_data["status"] = "active"
	active_quest = quest_data

func update_quest(delta: float, player_pos: Vector3, wanted_level: int,
		  pickups: Array, npcs: Array) -> void:
	if active_quest.is_empty():
		return
	if active_quest.get("status") != "active":
		return
	# Decrement timer
	active_quest["timer"] -= delta
	if active_quest["timer"] <= 0.0:
		_fail_quest()
		return
	# Progress checks by quest type
	match active_quest.get("type", ""):
		"collect":
			# Player collects pickups of the target type
			for p in pickups:
				if p.get("type", "") == active_quest["target"] and not p.get("collected", false):
					p["collected"] = true
					active_quest["progress"] += 1
					if active_quest["progress"] >= active_quest["count"]:
						_complete_quest()
						return
		"kill":
			# Player kills NPCs (already tracked by stats_npcs_killed)
			# We check against a baseline captured at accept time
			if stats_npcs_killed >= active_quest.get("_baseline_kills", 0) + active_quest["count"]:
				_complete_quest()
		"survive":
			# Player must have wanted_level == 0 for the duration
			# The timer counts down; if wanted > 0, reset timer
			if wanted_level > 0:
				active_quest["timer"] = active_quest["time_limit"]
		"escort", "deliver":
			# These need target positions; handled by main.gd calling
			# complete_quest() when the player reaches the target
			pass

func set_quest_target(pos: Vector3, radius: float) -> void:
	if not active_quest.is_empty():
		active_quest["target_pos"] = pos
		active_quest["target_radius"] = radius

func complete_quest() -> void:
	if active_quest.is_empty():
		return
	_complete_quest()

func _complete_quest() -> void:
	var reward: int = active_quest.get("reward", 0)
	active_quest["status"] = "complete"
	# Signal to main.gd to add reward
	get_parent()._on_side_quest_complete(reward, active_quest.get("id", ""))
	active_quest.clear()

func _fail_quest() -> void:
	if active_quest.is_empty():
		return
	active_quest["status"] = "failed"
	get_parent()._on_side_quest_failed(active_quest.get("id", ""))
	active_quest.clear()

func get_active_quest() -> Dictionary:
	return active_quest

func has_active_quest() -> bool:
	return not active_quest.is_empty() and active_quest.get("status") == "active"
