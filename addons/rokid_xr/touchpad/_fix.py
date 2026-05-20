import re

with open('touchpad_input.gd', 'r') as f:
    content = f.read()

# Fix _scan_xr_trackers: replace the broken function
old_func = '''func _scan_xr_trackers() -> void:
		# 常见 XR 控制器追踪器名称
		var tracker_names := ["head", "left", "right",
			"/user/hand/left", "/user/hand/right",
			"/user/head"]
	for name in tracker_names:
			var tracker: XRPositionalTracker = XRServer.get_tracker(name)
			if tracker:
				print("[TouchpadInput] XR tracker '%s': type=%s" % [name, tracker.get_tracker_type()])
				# 列出可用的输入
				if not inputs.is_empty():
					print("[TouchpadInput]   inputs: %s" % str(inputs))'''

new_func = '''func _scan_xr_trackers() -> void:
	var tracker_names: Array[String] = ["head", "left", "right",
		"/user/hand/left", "/user/hand/right", "/user/head"]
	for name in tracker_names:
		var tracker: XRPositionalTracker = XRServer.get_tracker(name)
		if tracker:
			var found: String = ""
			for pn in ["trigger", "trigger_click", "grip", "grip_click",
				"primary", "primary_click", "menu_button",
				"ax_button", "by_button", "trackpad", "thumbstick"]:
				var v = tracker.get_input(pn)
				if v != null and v != 0.0 and v != false:
					found += pn + " "
			print("[TouchpadInput] XR '%s': %s" % [name, found if found != "" else "no inputs"])'''

content = content.replace(old_func, new_func)

with open('touchpad_input.gd', 'w') as f:
    f.write(content)
print("Done")
