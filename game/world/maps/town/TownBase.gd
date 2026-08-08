# 正式小镇地图运行基类。
# 负责地图、玩家、运行层、建筑室内传送和共享家具编辑。
extends Node2D

const MAP_PATH := "res://world/maps/town/assets/town.png"
const MAP_SIZE := Vector2(6688.0, 3764.0)
const OUTDOOR_MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)
const PORTAL_CATALOG := preload(
	"res://world/data/town/TownPortalCatalog.gd"
)
const MAP_RUNTIME_LAYER_LOADER_SCRIPT := preload("res://world/runtime/MapRuntimeLayerLoader.gd")
const RUNTIME_LAYER_WATCH_GENERATED_FILES := false
const RUNTIME_LAYER_PRINT_RELOAD_MESSAGES := false
const INTERIOR_ROOM_SCENE := preload("res://world/maps/town/interiors/InteriorRoom.tscn")
const PAPER_DOLL_64_SPRITE_SCRIPT := preload("res://characters/paper_doll/PaperDoll64Sprite.gd")
# The formal player avatar uses the 64px PaperDoll atlas. Keep its in-map
# visible height near two thirds of a town door so it reads as a walkable
# character instead of a large UI-scale sprite.
const PLAYER_DISPLAY_SCALE := 1.65
const PLAYER_OCCLUSION_SUBJECT_GROUP := "map_occlusion_subject"
# 一秒现实时间等于一分钟游戏时间。按小镇长轴步行约 20 分钟计算速度：
# 6688 px / 20 游戏分钟 / 1 现实秒每游戏分钟 = 334.4 px/s。
const REAL_SECONDS_PER_GAME_MINUTE := 1.0
const TOWN_LONG_AXIS_TRAVEL_GAME_MINUTES := 20.0
const PLAYER_SPEED := (
	MAP_SIZE.x / TOWN_LONG_AXIS_TRAVEL_GAME_MINUTES / REAL_SECONDS_PER_GAME_MINUTE
)
const PLAYER_CONTACT_PROBE_DISTANCE := 1.0
const CAFE_PLAYER_DEPTH := 1000
# 室外完整地图在 z=0，运行时重绘的前景遮挡最低会落到 z=99；脚底阴影
# 必须夹在两者之间。室内地板壳在 z=-10，家具从 z=0 开始，因此室内
# 阴影单独落在 -9，避免跟随人物层级盖黑台阶、家具和屋顶。
const OUTDOOR_GROUND_SHADOW_Z_INDEX := 98
const INTERIOR_GROUND_SHADOW_Z_INDEX := -9
const DOOR_THRESHOLD_TRIGGER_SIZE := (
	PORTAL_CATALOG.DOOR_THRESHOLD_TRIGGER_SIZE
)
const PORTAL_FADE_OUT_SECONDS := 0.22
const PORTAL_BLACK_HOLD_SECONDS := 0.08
const PORTAL_FADE_IN_SECONDS := 0.28
const INTERIOR_LOCATION_TITLE_TEXTURE := preload(
	"res://assets/ui/indoor_overlay/runtime_skin_v8/composite/indoor_title_bar_native_v8.png"
)
const INTERIOR_TITLE_FADE_IN_SECONDS := 0.22
const INTERIOR_TITLE_HOLD_SECONDS := 2.2
const INTERIOR_TITLE_FADE_OUT_SECONDS := 0.75
const INTERIOR_TITLE_BANNER_SIZE := Vector2(320.0, 72.0)
const INTERIOR_TITLE_BANNER_TOP := 10.0
const PLAYER_SPAWN := Vector2(3240.0, 3600.0)
const COLLISION_SAMPLE_SPAWN := Vector2(3250.0, 2050.0)
const CAFE_INTERIOR_ORIGIN := Vector2(8200.0, 1800.0)
const CAFE_DOOR_TRIGGER_RECT := Rect2(4323.0, 3185.0, 110.0, 90.0)
const CAFE_EXIT_TRIGGER_LOCAL_RECT := Rect2(
	Vector2(-165.0, 360.0) - DOOR_THRESHOLD_TRIGGER_SIZE * 0.5,
	DOOR_THRESHOLD_TRIGGER_SIZE
)
const CAFE_INTERIOR_LOCAL_BOUNDS := Rect2(-520.0, -230.0, 1040.0, 610.0)
const CAFE_INTERIOR_CAMERA_BOUNDS := Rect2(7560.0, 1160.0, 1280.0, 1280.0)
const INTERIOR_CAMERA_LOCAL_BOUNDS := Rect2(-640.0, -640.0, 1280.0, 1280.0)
const INTERIOR_DEFINITIONS := {
	"cafe": {
		"display_name": "花房咖啡馆",
		"node_name": "IndoorCafe",
		"shell_path": "res://world/maps/town/interiors/redesign_v2/rooms/cafe/assets/background/room_shell.png",
		"geometry_path": "res://world/maps/town/interiors/redesign_v2/rooms/cafe/room_geometry.json",
		"occlusion_path": "res://world/maps/town/interiors/redesign_v2/rooms/cafe/wall_occlusion.json",
		"furniture_manifest_path": "res://world/maps/town/interiors/redesign_v2/rooms/cafe/furniture_manifest.json",
		"layout_path": "res://world/maps/town/interiors/redesign_v2/rooms/cafe/layout.json",
		"origin": CAFE_INTERIOR_ORIGIN,
		"local_bounds": CAFE_INTERIOR_LOCAL_BOUNDS,
		"entry_point": Vector2.ZERO,
		"exit_point": Vector2.ZERO,
	},
	"library": {
		"display_name": "图书馆",
		"node_name": "IndoorLibrary",
		"shell_path": "res://world/maps/town/interiors/redesign_v2/rooms/library/assets/background/room_shell.png",
		"geometry_path": "res://world/maps/town/interiors/redesign_v2/rooms/library/room_geometry.json",
		"occlusion_path": "res://world/maps/town/interiors/redesign_v2/rooms/library/wall_occlusion.json",
		"furniture_manifest_path": "res://world/maps/town/interiors/redesign_v2/rooms/library/furniture_manifest.json",
		"layout_path": "res://world/maps/town/interiors/redesign_v2/rooms/library/layout.json",
		"origin": Vector2(9600.0, 1800.0),
		"local_bounds": Rect2(-470.0, -210.0, 940.0, 640.0),
		"entry_point": Vector2.ZERO,
		"exit_point": Vector2.ZERO,
	},
	"town_hall": {
		"display_name": "镇公所",
		"node_name": "IndoorTownHall",
		"shell_path": "res://world/maps/town/interiors/redesign_v2/rooms/town_hall/assets/background/room_shell.png",
		"geometry_path": "res://world/maps/town/interiors/redesign_v2/rooms/town_hall/room_geometry.json",
		"occlusion_path": "res://world/maps/town/interiors/redesign_v2/rooms/town_hall/wall_occlusion.json",
		"furniture_manifest_path": "res://world/maps/town/interiors/redesign_v2/rooms/town_hall/furniture_manifest.json",
		"layout_path": "res://world/maps/town/interiors/redesign_v2/rooms/town_hall/layout.json",
		"origin": Vector2(11000.0, 1800.0),
		"local_bounds": Rect2(-555.0, -240.0, 1110.0, 690.0),
		"entry_point": Vector2.ZERO,
		"exit_point": Vector2.ZERO,
	},
	"clinic": {
		"display_name": "诊所",
		"node_name": "IndoorClinic",
		"shell_path": "res://world/maps/town/interiors/redesign_v2/rooms/clinic/assets/background/room_shell.png",
		"geometry_path": "res://world/maps/town/interiors/redesign_v2/rooms/clinic/room_geometry.json",
		"occlusion_path": "res://world/maps/town/interiors/redesign_v2/rooms/clinic/wall_occlusion.json",
		"furniture_manifest_path": "res://world/maps/town/interiors/redesign_v2/rooms/clinic/furniture_manifest.json",
		"layout_path": "res://world/maps/town/interiors/redesign_v2/rooms/clinic/layout.json",
		"origin": Vector2(12400.0, 1800.0),
		"local_bounds": Rect2(-500.0, -195.0, 1000.0, 625.0),
		"entry_point": Vector2.ZERO,
		"exit_point": Vector2.ZERO,
	},
	"market": {
		"display_name": "独立市集",
		"node_name": "IndoorMarket",
		"shell_path": "res://world/maps/town/interiors/redesign_v2/rooms/market_shop/assets/background/room_shell.png",
		"geometry_path": "res://world/maps/town/interiors/redesign_v2/rooms/market_shop/room_geometry.json",
		"occlusion_path": "res://world/maps/town/interiors/redesign_v2/rooms/market_shop/wall_occlusion.json",
		"furniture_manifest_path": "res://world/maps/town/interiors/redesign_v2/rooms/market_shop/furniture_manifest.json",
		"layout_path": "res://world/maps/town/interiors/redesign_v2/rooms/market_shop/layout.json",
		"origin": Vector2(13800.0, 1800.0),
		"local_bounds": Rect2(64.0, 128.0, 1120.0, 832.0),
		"entry_point": Vector2.ZERO,
		"exit_point": Vector2.ZERO,
	},
	"dining_hall": {
		"display_name": "公共食堂",
		"node_name": "IndoorDiningHall",
		"shell_path": "res://world/maps/town/interiors/redesign_v2/rooms/dining_hall/assets/background/room_shell.png",
		"geometry_path": "res://world/maps/town/interiors/redesign_v2/rooms/dining_hall/room_geometry.json",
		"occlusion_path": "res://world/maps/town/interiors/redesign_v2/rooms/dining_hall/wall_occlusion.json",
		"furniture_manifest_path": "res://world/maps/town/interiors/redesign_v2/rooms/dining_hall/furniture_manifest.json",
		"layout_path": "res://world/maps/town/interiors/redesign_v2/rooms/dining_hall/layout.json",
		"origin": Vector2(15200.0, 1800.0),
		"local_bounds": Rect2(-535.0, -240.0, 1070.0, 700.0),
		"entry_point": Vector2.ZERO,
		"exit_point": Vector2.ZERO,
	},
	"workshop": {
		"display_name": "工作坊",
		"node_name": "IndoorWorkshop",
		"shell_path": "res://world/maps/town/interiors/redesign_v2/rooms/workshop/assets/background/room_shell.png",
		"geometry_path": "res://world/maps/town/interiors/redesign_v2/rooms/workshop/room_geometry.json",
		"occlusion_path": "res://world/maps/town/interiors/redesign_v2/rooms/workshop/wall_occlusion.json",
		"furniture_manifest_path": "res://world/maps/town/interiors/redesign_v2/rooms/workshop/furniture_manifest.json",
		"layout_path": "res://world/maps/town/interiors/redesign_v2/rooms/workshop/layout.json",
		"origin": Vector2(18000.0, 1800.0),
		"local_bounds": Rect2(-545.0, -205.0, 1090.0, 630.0),
		"entry_point": Vector2.ZERO,
		"exit_point": Vector2.ZERO,
	},
	"dock_warehouse": {
		"display_name": "码头仓库与渔港",
		"node_name": "IndoorDockWarehouse",
		"shell_path": "res://world/maps/town/interiors/redesign_v2/rooms/dock_warehouse/assets/background/room_shell.png",
		"geometry_path": "res://world/maps/town/interiors/redesign_v2/rooms/dock_warehouse/room_geometry.json",
		"occlusion_path": "res://world/maps/town/interiors/redesign_v2/rooms/dock_warehouse/wall_occlusion.json",
		"furniture_manifest_path": "res://world/maps/town/interiors/redesign_v2/rooms/dock_warehouse/furniture_manifest.json",
		"layout_path": "res://world/maps/town/interiors/redesign_v2/rooms/dock_warehouse/layout.json",
		"origin": Vector2(19400.0, 1800.0),
		"local_bounds": Rect2(-575.0, -225.0, 1150.0, 680.0),
		"entry_point": Vector2.ZERO,
		"exit_point": Vector2.ZERO,
	},
	"home_a": {
		"display_name": "住宅",
		"node_name": "IndoorHomeA",
		"shell_path": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/assets/background/room_shell.png",
		"geometry_path": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/room_geometry.json",
		"occlusion_path": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/wall_occlusion.json",
		"furniture_manifest_path": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/furniture_manifest.json",
		"layout_path": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/layouts/home_01.json",
		"layout_paths_by_portal": {
			"home_01": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/layouts/home_01.json",
			"home_05": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/layouts/home_05.json",
			"home_09": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/layouts/home_09.json",
			"home_11": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/layouts/home_11.json",
			"home_12": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/layouts/home_12.json",
			"home_13": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/layouts/home_13.json",
			"home_14": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/layouts/home_14.json",
			"home_15": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_a/layouts/home_15.json",
		},
		"origin": Vector2(20800.0, 1800.0),
		"local_bounds": Rect2(-315.0, -205.0, 630.0, 625.0),
		"entry_point": Vector2.ZERO,
		"exit_point": Vector2.ZERO,
	},
	"home_b": {
		"display_name": "住宅",
		"node_name": "IndoorHomeB",
		"shell_path": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/assets/background/room_shell.png",
		"geometry_path": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/room_geometry.json",
		"occlusion_path": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/wall_occlusion.json",
		"furniture_manifest_path": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/furniture_manifest.json",
		"layout_path": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/layouts/home_02.json",
		"layout_paths_by_portal": {
			"home_02": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/layouts/home_02.json",
			"home_03": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/layouts/home_03.json",
			"home_04": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/layouts/home_04.json",
			"home_06": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/layouts/home_06.json",
			"home_07": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/layouts/home_07.json",
			"home_08": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/layouts/home_08.json",
			"home_10": "res://world/maps/town/interiors/redesign_v2/rooms/home_template_b/layouts/home_10.json",
		},
		"origin": Vector2(22200.0, 1800.0),
		"local_bounds": Rect2(-500.0, -190.0, 1000.0, 600.0),
		"entry_point": Vector2.ZERO,
		"exit_point": Vector2.ZERO,
	},
}
const EXTERIOR_INTERIOR_PORTALS: Array[Dictionary] = (
	PORTAL_CATALOG.EXTERIOR_INTERIOR_PORTALS
)
const OVERVIEW_ZOOM_INDEX := 0
const DEFAULT_ZOOM_INDEX := 2
const OVERVIEW_ZOOM_MARGIN := 0.96
# 0 号档位运行时按窗口和地图尺寸计算；其余档位保持像素画常用倍率。
const ZOOM_LEVELS: Array[float] = [0.0, 0.5, 1.0, 2.0]
const WATER_FLOW_LOOP_SECONDS := 9.0
const WATER_SHEEN_ALPHA := 0.055
const WATER_LINE_ALPHA := 0.52
const DAY_CYCLE_SECONDS := 10.0
const WEATHER_HOLD_SECONDS := 6.0
const WEATHER_NAMES: Array[String] = ["晴天", "多云", "下雨"]
const CAFE_FURNITURE_DIRECTION_NAMES := {
	"down": "朝下",
	"right": "朝右",
	"up": "朝上",
	"left": "朝左",
}
const OUTFIT_ORDER: Array[String] = ["elder_man", "skirt_woman", "suit_man"]
const OUTFIT_NAMES := {
	"elder_man": "温和老人",
	"skirt_woman": "裙装女性",
	"suit_man": "西装男性",
}
const SLOT_ORDER: Array[String] = ["bottom", "shoes", "top_hands", "head"]
const DIRECTION_ROWS := {"down": 0, "right": 1, "up": 2, "left": 3}
const WATER_SHEEN_SHADER_CODE := """
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 sheen_color : source_color = vec4(0.64, 0.94, 1.0, 1.0);
uniform float alpha_scale = 0.055;
uniform float line_alpha = 0.52;
uniform float flow_phase = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float inside_rect(vec2 point, vec4 rect) {
	vec2 lower = step(rect.xy, point);
	vec2 upper = step(point, rect.zw);
	return lower.x * lower.y * upper.x * upper.y;
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;

	float blue_bias = src.b - max(src.r, src.g * 0.82);
	float cyan_bias = min(src.g, src.b) - src.r * 1.12;
	float brightness = max(max(src.r, src.g), src.b);
	float water_mask = smoothstep(0.035, 0.14, blue_bias);
	water_mask *= smoothstep(0.02, 0.13, cyan_bias);
	water_mask *= smoothstep(0.40, 0.62, brightness);

	// This map's connected river and harbor live on the east side.
	water_mask *= smoothstep(4580.0, 4820.0, pixel.x);
	// Exclude the large blue-green harbor roof from color-key animation.
	water_mask *= 1.0 - inside_rect(pixel, vec4(5480.0, 2440.0, 6350.0, 3260.0));

	vec2 flow_pixel = pixel;
	flow_pixel.y -= flow_phase * 420.0;
	vec2 cell_size = vec2(176.0, 86.0);
	vec2 cell = floor(flow_pixel / cell_size);
	vec2 local = fract(flow_pixel / cell_size);
	float seed = hash21(cell);
	float show_dash = step(0.34, seed);
	float center_x = mix(0.25, 0.75, hash21(cell + vec2(11.7, 4.3)));
	float center_y = mix(0.28, 0.72, hash21(cell + vec2(5.1, 19.8)));
	float half_width = mix(0.18, 0.34, hash21(cell + vec2(23.5, 8.4)));
	float curve = sin((local.x + seed) * 6.28318) * 0.035;
	float y_line = 1.0 - smoothstep(0.010, 0.034, abs(local.y - center_y - curve));
	float x_gate = 1.0 - smoothstep(half_width, half_width + 0.08, abs(local.x - center_x));
	float dash = y_line * x_gate * show_dash;
	float soft_flow = 0.56 + 0.44 * sin((UV.y + flow_phase) * 34.0 + sin(UV.x * 18.0) * 0.65);
	float sheen = alpha_scale * mix(0.32, 1.0, smoothstep(0.18, 1.0, soft_flow));
	float highlight = max(sheen, dash * line_alpha);
	COLOR = vec4(sheen_color.rgb, water_mask * highlight);
}
"""
const WEATHER_OVERLAY_SHADER_CODE := """
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float weather_mode = 0.0;
uniform float weather_time = 0.0;
uniform float lightning_flash = 0.0;
uniform float day_cycle = 0.0;
uniform float night_factor = 0.0;
uniform float wind_strength = 0.0;
uniform float rain_intensity = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

void fragment() {
	float cloudy = step(0.5, weather_mode);
	float raining = step(1.5, weather_mode);
	vec2 cloud_uv = UV * vec2(4.2, 2.5) + vec2(weather_time * (0.035 + wind_strength * 0.012), weather_time * 0.008);
	float cloud = value_noise(cloud_uv) * 0.62 + value_noise(cloud_uv * 2.1) * 0.38;
	cloud = smoothstep(0.42, 0.78, cloud);

	float rain_slope = 0.13 + wind_strength * 0.11;
	vec2 rain_space = vec2(UV.x + UV.y * rain_slope, UV.y) * vec2(118.0, 58.0);
	rain_space += vec2(weather_time * (7.0 + wind_strength * 5.0), -weather_time * (16.0 + rain_intensity * 12.0));
	vec2 rain_cell = floor(rain_space);
	vec2 rain_local = fract(rain_space);
	float rain_gate = step(mix(0.78, 0.42, rain_intensity), hash21(rain_cell));
	float rain_line = 1.0 - smoothstep(0.025, 0.075, abs(rain_local.x - 0.5));
	rain_line *= 1.0 - smoothstep(0.52, 0.94, rain_local.y);
	rain_line *= rain_gate * raining * mix(0.45, 1.0, rain_intensity);

	vec2 splash_space = UV * vec2(72.0, 28.0) + vec2(weather_time * 0.7, 0.0);
	vec2 splash_cell = floor(splash_space);
	vec2 splash_local = fract(splash_space) - vec2(0.5);
	float splash_seed = hash21(splash_cell + floor(weather_time * 5.0));
	float splash_ring = 1.0 - smoothstep(0.025, 0.09, abs(length(splash_local * vec2(1.0, 3.2)) - 0.18));
	splash_ring *= step(mix(0.93, 0.74, rain_intensity), splash_seed) * smoothstep(0.35, 0.95, UV.y) * raining;

	float morning = smoothstep(0.70, 0.78, day_cycle) * (1.0 - smoothstep(0.92, 0.99, day_cycle));
	vec2 mist_uv = vec2(UV.x * 3.2 + weather_time * (0.018 + wind_strength * 0.008), UV.y * 6.0);
	float mist = value_noise(mist_uv) * 0.65 + value_noise(mist_uv * 1.9) * 0.35;
	mist = smoothstep(0.45, 0.78, mist) * morning * (1.0 - raining * 0.35);
	mist *= smoothstep(0.05, 0.42, UV.y) * (1.0 - smoothstep(0.90, 1.0, UV.y));

	vec2 wet_uv = UV * vec2(7.0, 11.0) + vec2(weather_time * 0.045, -weather_time * 0.025);
	float wet_sheen = pow(max(0.0, sin((wet_uv.x + wet_uv.y) * 3.14159)), 18.0);
	wet_sheen *= value_noise(wet_uv * 0.55) * raining * rain_intensity * 0.24;

	vec2 firefly_space = UV * vec2(25.0, 14.0);
	vec2 firefly_cell = floor(firefly_space);
	vec2 firefly_local = fract(firefly_space) - vec2(0.5);
	float firefly_seed = hash21(firefly_cell);
	vec2 firefly_motion = vec2(
		sin(weather_time * 0.72 + firefly_seed * 19.0),
		cos(weather_time * 0.55 + firefly_seed * 23.0)
	) * 0.18;
	float firefly = 1.0 - smoothstep(0.035, 0.12, length(firefly_local - firefly_motion));
	firefly *= step(0.91, firefly_seed) * night_factor * (1.0 - raining);
	firefly *= 0.55 + 0.45 * sin(weather_time * 4.0 + firefly_seed * 31.0);

	vec2 pollen_space = UV * vec2(32.0, 18.0) + vec2(-weather_time * wind_strength * 0.18, weather_time * 0.08);
	vec2 pollen_cell = floor(pollen_space);
	vec2 pollen_local = fract(pollen_space) - vec2(0.5);
	float pollen_seed = hash21(pollen_cell);
	float pollen = 1.0 - smoothstep(0.018, 0.065, length(pollen_local));
	pollen *= step(0.94, pollen_seed) * (1.0 - night_factor) * (1.0 - cloudy);

	vec2 butterfly_space = UV * vec2(14.0, 8.0) + vec2(-weather_time * wind_strength * 0.08, sin(weather_time * 0.55) * 0.18);
	vec2 butterfly_cell = floor(butterfly_space);
	vec2 butterfly_local = fract(butterfly_space) - vec2(0.5);
	float butterfly_seed = hash21(butterfly_cell + vec2(7.0, 13.0));
	float wing_open = 0.045 + abs(sin(weather_time * 7.0 + butterfly_seed * 17.0)) * 0.055;
	float wing_left = 1.0 - smoothstep(0.025, 0.075, length(butterfly_local - vec2(-wing_open, 0.0)));
	float wing_right = 1.0 - smoothstep(0.025, 0.075, length(butterfly_local - vec2(wing_open, 0.0)));
	float butterfly = max(wing_left, wing_right) * step(0.965, butterfly_seed);
	butterfly *= (1.0 - night_factor) * (1.0 - cloudy);

	vec2 vignette_uv = (UV - vec2(0.5)) * vec2(1.0, 0.72);
	float vignette = smoothstep(0.34, 0.70, length(vignette_uv));
	vignette *= night_factor * 0.25 + cloudy * 0.045;

	vec3 tint = mix(vec3(0.11, 0.15, 0.20), vec3(0.07, 0.11, 0.17), raining);
	float shade_alpha = cloud * mix(0.10, 0.17, raining) * cloudy + vignette;
	float rain_alpha = rain_line * 0.46 + splash_ring * 0.30;
	vec3 rain_color = vec3(0.63, 0.82, 0.96);
	vec3 color = mix(tint, rain_color, clamp(rain_line + splash_ring, 0.0, 1.0));
	color = mix(color, vec3(0.78, 0.88, 0.93), mist * 0.84);
	color = mix(color, vec3(0.72, 0.88, 1.0), wet_sheen);
	color = mix(color, vec3(1.0, 0.82, 0.25), firefly);
	color = mix(color, vec3(1.0, 0.94, 0.70), pollen);
	color = mix(color, vec3(1.0, 0.62, 0.83), butterfly);
	color = mix(color, vec3(0.92, 0.97, 1.0), lightning_flash);
	float alpha = clamp(
		shade_alpha + rain_alpha + mist * 0.22 + wet_sheen + firefly * 0.82 + pollen * 0.52 + butterfly * 0.72 + lightning_flash * 0.68,
		0.0,
		0.82
	);
	COLOR = vec4(color, alpha);
}
"""

var _player := CharacterBody2D.new()
var _runtime_layer_loader: Node2D
var _player_sprite: PaperDoll64Sprite
var _player_visual_root: Node2D
var _player_occlusion_foot_point: Marker2D
var _player_shadow: Polygon2D
var _player_feet_collision: CollisionShape2D
var _player_blocking_normals: Array[Vector2] = []
var _camera := Camera2D.new()
var _status_label := Label.new()
var _scene_name_layer := CanvasLayer.new()
var _scene_name_banner := TextureRect.new()
var _scene_name_label := Label.new()
var _scene_name_tween: Tween
var _portal_transition_layer := CanvasLayer.new()
var _portal_transition_overlay := ColorRect.new()
var _map_control_panel: ColorRect
var _cafe_furniture_entry_panel := ColorRect.new()
var _cafe_furniture_panel := ColorRect.new()
var _furniture_entry_button: Button
var _furniture_editor_title: Label
var _furniture_library_grid: GridContainer
var _cafe_decor_library_buttons: Dictionary = {}
var _cafe_furniture_direction_label := Label.new()
var _cafe_furniture_feedback_label := Label.new()
var _cafe_furniture_direction_buttons: Dictionary = {}
var _control_buttons: Dictionary = {}
var _control_state_label := Label.new()
var _water_overlay := Sprite2D.new()
var _water_material: ShaderMaterial
var _water_elapsed := 0.0
var _world_tint := CanvasModulate.new()
var _weather_overlay := ColorRect.new()
var _weather_layer := CanvasLayer.new()
var _weather_material: ShaderMaterial
var _environment_lights: Array[PointLight2D] = []
var _light_base_energies: Array[float] = []
var _smoke_materials: Array[ParticleProcessMaterial] = []
var _leaf_particles := GPUParticles2D.new()
var _leaf_material: ParticleProcessMaterial
var _thunder_player := AudioStreamPlayer.new()
var _environment_elapsed := 0.0
var _weather_elapsed := 0.0
var _weather_shader_elapsed := 0.0
var _weather_index := 0
var _rain_intensity := 0.0
var _wind_strength := 0.0
var _environment_running := true
var _weather_auto := true
var _lightning_wait := 2.0
var _lightning_flash := 0.0
var _camera_shake_time := 0.0
var _camera_shake_strength := 0.0
var _direction := "down"
var _zoom_index := DEFAULT_ZOOM_INDEX
var _outdoor_zoom_index := DEFAULT_ZOOM_INDEX
var _interior_root: InteriorRoom
var _interior_roots: Dictionary = {}
var _active_interior_id := ""
var _active_exterior_portal_id := ""
var _blocked_exterior_reentry_portal_id := ""
var _cafe_layout: Node2D
var _library_layout: Node2D
var _town_hall_layout: Node2D
var _clinic_layout: Node2D
var _active_furniture_layout: Node2D
var _cafe_furniture_edit_mode := false
var _inside_furniture_room := false
var _furniture_drag_active := false
var _furniture_drag_from_existing := false
var _furniture_drag_offset := Vector2.ZERO
var _portal_transition_active := false
var _selection := {
	"head": "elder_man",
	"top_hands": "elder_man",
	"bottom": "elder_man",
	"shoes": "elder_man",
}


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("101820"))
	_build_map()
	_build_runtime_layers()
	_build_water_animation()
	_build_interior_portals()
	_build_player()
	_build_camera()
	_build_environment_test()
	_build_ui()
	_build_portal_transition()
	_build_interior_location_title()
	_set_preset("elder_man")
	_focus_player()
	_sync_player_visual()


func _exit_tree() -> void:
	# Several legacy/demo layers are constructed eagerly as member Nodes. Formal
	# Town overrides their builders, so those Nodes never enter the SceneTree and
	# would otherwise survive shutdown as ObjectDB/Canvas RID orphans.
	for value: Variant in [
		_status_label,
		_scene_name_layer,
		_scene_name_banner,
		_scene_name_label,
		_portal_transition_layer,
		_portal_transition_overlay,
		_cafe_furniture_entry_panel,
		_cafe_furniture_panel,
		_cafe_furniture_direction_label,
		_cafe_furniture_feedback_label,
		_control_state_label,
		_water_overlay,
		_world_tint,
		_weather_layer,
		_weather_overlay,
		_leaf_particles,
		_thunder_player,
	]:
		var node := value as Node
		if is_instance_valid(node) and node.get_parent() == null:
			node.free()


func _runtime_map_id() -> String:
	return "town"


func _build_runtime_layers() -> void:
	var loader = MAP_RUNTIME_LAYER_LOADER_SCRIPT.new()
	loader.name = "MapRuntimeLayerLoader"
	loader.set("runtime_json_path", "res://world/maps/%s/generated/runtime.json" % _runtime_map_id())
	loader.set("layers_scene_path", "res://world/maps/%s/generated/layers.tscn" % _runtime_map_id())
	loader.set("load_on_ready", false)
	loader.set("watch_generated_files", RUNTIME_LAYER_WATCH_GENERATED_FILES)
	loader.set("clear_existing_runtime_layers", true)
	loader.set("print_reload_messages", RUNTIME_LAYER_PRINT_RELOAD_MESSAGES)
	add_child(loader)
	_runtime_layer_loader = loader as Node2D
	loader.reload_runtime_layers()

func _process(delta: float) -> void:
	if _water_material != null and _water_overlay.visible:
		_water_elapsed += delta
		var phase := fmod(_water_elapsed / WATER_FLOW_LOOP_SECONDS, 1.0)
		_water_material.set_shader_parameter("flow_phase", phase)
	_update_environment_test(delta)
	_update_cafe_depth_order()
	_update_cafe_furniture_placement_preview()


func _physics_process(delta: float) -> void:
	var player_locked := (
		_portal_transition_active
		or _cafe_furniture_edit_mode
	)
	var input_vector := Vector2.ZERO if player_locked else _read_move_input()
	var previous_position := _player.position
	var previous_frame_column := _player_sprite.frame_coords.x if _player_sprite != null else 0
	if input_vector.length_squared() > 0.0001:
		input_vector = input_vector.normalized()
		_direction = _direction_from_vector(input_vector)
		var requested_velocity := input_vector * PLAYER_SPEED
		_player.velocity = _filter_player_velocity_against_contacts(
			requested_velocity,
		)
	else:
		_player.velocity = Vector2.ZERO
		_clear_player_blocking_normals()
	_player.move_and_slide()
	_capture_player_blocking_normals(input_vector * PLAYER_SPEED)
	_clamp_player_position()
	var moved_distance := _player.position.distance_to(previous_position)
	if _player_sprite != null:
		_player_sprite.set_motion(input_vector, moved_distance)
		var current_frame_column := _player_sprite.frame_coords.x
		if current_frame_column != previous_frame_column and current_frame_column in [1, 3]:
			_emit_footstep_effect()
	_check_interior_auto_portals()
	_update_camera_target()
	_update_camera_feedback(delta)
	_update_status()


func _filter_player_velocity_against_contacts(
	requested_velocity: Vector2,
) -> Vector2:
	var filtered_velocity := requested_velocity
	var retained_normals: Array[Vector2] = []
	for normal: Vector2 in _player_blocking_normals:
		# Keep a contact while input is still neutral to it or pressing into it.
		# Release it as soon as the body has cleared the obstacle; otherwise a
		# remembered wall normal can keep blocking movement after rounding a corner.
		if (
			requested_velocity.dot(normal) <= 0.01
			and _player_still_contacts_normal(normal)
		):
			retained_normals.append(normal)
			if filtered_velocity.dot(normal) < 0.0:
				filtered_velocity = filtered_velocity.slide(normal)
	_player_blocking_normals = retained_normals
	return filtered_velocity


func _player_still_contacts_normal(normal: Vector2) -> bool:
	var normalized := normal.normalized()
	if normalized == Vector2.ZERO or not _player.is_inside_tree():
		return false
	return _player.test_move(
		_player.global_transform,
		-normalized * PLAYER_CONTACT_PROBE_DISTANCE,
	)


func _capture_player_blocking_normals(
	requested_velocity: Vector2,
) -> void:
	for index in _player.get_slide_collision_count():
		var collision := _player.get_slide_collision(index)
		var normal := collision.get_normal().normalized()
		if requested_velocity.dot(normal) >= -0.01:
			continue
		_remember_player_blocking_normal(normal)
		# Never carry the component that points back into the obstacle.
		if _player.velocity.dot(normal) < 0.0:
			_player.velocity = _player.velocity.slide(normal)


func _clear_player_blocking_normals() -> void:
	_player_blocking_normals.clear()


func _remember_player_blocking_normal(normal: Vector2) -> void:
	var normalized := normal.normalized()
	if normalized == Vector2.ZERO:
		return
	for current: Vector2 in _player_blocking_normals:
		if current.dot(normalized) > 0.98:
			return
	_player_blocking_normals.append(normalized)


func _unhandled_input(event: InputEvent) -> void:
	if _portal_transition_active:
		return
	if event is InputEventMouseMotion:
		if _inside_furniture_room and _cafe_furniture_edit_mode and is_cafe_furniture_placing():
			_update_cafe_furniture_placement_preview()
			_refresh_furniture_placement_feedback()
		return
	if event is InputEventMouseButton:
		if _inside_furniture_room and _cafe_furniture_edit_mode:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_begin_furniture_drag()
				else:
					_finish_furniture_drag()
				return
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				cancel_cafe_furniture_placement()
				return
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom_index(_zoom_index + 1)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom_index(_zoom_index - 1)
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_0:
			_set_zoom_index(0)
		KEY_1:
			_set_preset("elder_man")
		KEY_2:
			_set_preset("skirt_woman")
		KEY_3:
			_set_preset("suit_man")
		KEY_Q:
			_cycle_slot("head")
		KEY_E:
			if not _inside_furniture_room:
				_cycle_slot("top_hands")
		KEY_R:
			if _inside_furniture_room and _cafe_furniture_edit_mode:
				rotate_cafe_furniture_clockwise()
			elif not _inside_furniture_room:
				_cycle_slot("bottom")
		KEY_ESCAPE:
			if _inside_furniture_room and _cafe_furniture_edit_mode:
				exit_cafe_furniture_edit_mode()
		KEY_T:
			_cycle_slot("shoes")
		KEY_F:
			_focus_player()
		KEY_V:
			_water_overlay.visible = not _water_overlay.visible
		KEY_C:
			_toggle_collision_debug()
		KEY_P:
			_player.position = COLLISION_SAMPLE_SPAWN
			_clear_player_blocking_normals()
			_update_camera_target(true)
		KEY_O:
			_toggle_map_overlays()
		KEY_B:
			_weather_auto = false
			_set_weather((_weather_index + 1) % WEATHER_NAMES.size())
		KEY_H:
			_weather_auto = not _weather_auto
			_weather_elapsed = 0.0
		KEY_N:
			_environment_running = not _environment_running
		KEY_M:
			_trigger_lightning()


func _build_map() -> void:
	var map_sprite := Sprite2D.new()
	map_sprite.name = "TownHdFull"
	map_sprite.texture = _load_texture(MAP_PATH)
	if map_sprite.texture == null:
		push_error("HD town map is missing: %s" % MAP_PATH)
	map_sprite.centered = false
	map_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(map_sprite)


func _build_water_animation() -> void:
	_water_overlay.name = "WaterSheen"
	_water_overlay.texture = _load_texture(MAP_PATH)
	if _water_overlay.texture == null:
		push_error("Water overlay could not load the town map: %s" % MAP_PATH)
		return
	_water_overlay.centered = false
	_water_overlay.z_index = 10
	_water_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shader := Shader.new()
	shader.code = WATER_SHEEN_SHADER_CODE
	_water_material = ShaderMaterial.new()
	_water_material.shader = shader
	_water_material.set_shader_parameter("alpha_scale", WATER_SHEEN_ALPHA)
	_water_material.set_shader_parameter("line_alpha", WATER_LINE_ALPHA)
	_water_material.set_shader_parameter("flow_phase", 0.0)
	_water_overlay.material = _water_material
	add_child(_water_overlay)


func _build_interior_portals() -> void:
	for interior_id_value in INTERIOR_DEFINITIONS:
		var interior_id := str(interior_id_value)
		var definition := INTERIOR_DEFINITIONS[interior_id] as Dictionary
		var room := INTERIOR_ROOM_SCENE.instantiate() as Node2D
		room.configure(str(definition["shell_path"]),
			definition["entry_point"] as Vector2,
			definition["exit_point"] as Vector2,
			str(definition.get("geometry_path", "")),
			str(definition.get("occlusion_path", "")),
			str(definition.get("furniture_manifest_path", "")),
			str(definition.get("layout_path", "")))
		room.name = str(definition["node_name"])
		room.position = definition["origin"] as Vector2
		room.visible = false
		add_child(room)
		_interior_roots[interior_id] = room

		var exit_marker := room.get_node("IndoorExitPoint") as Marker2D
		var exit_portal := _create_auto_portal(
			_interior_exit_portal_name(interior_id),
			room.position + exit_marker.position,
			DOOR_THRESHOLD_TRIGGER_SIZE
		)
		add_child(exit_portal)
		exit_portal.body_entered.connect(_exit_interior.bind(interior_id))

	var cafe_room := _interior_roots["cafe"] as Node2D
	_interior_root = cafe_room
	_cafe_layout = null
	_library_layout = null
	_town_hall_layout = null
	_clinic_layout = null
	_active_furniture_layout = null

	for portal_spec in EXTERIOR_INTERIOR_PORTALS:
		var portal_id := str(portal_spec["id"])
		var exterior_portal := _create_auto_portal(
			str(portal_spec["node_name"]),
			portal_spec["door"] as Vector2,
			_door_threshold_size(portal_spec["size"] as Vector2)
		)
		add_child(exterior_portal)
		exterior_portal.body_entered.connect(_enter_interior.bind(portal_id))

func _interior_exit_portal_name(interior_id: String) -> String:
	if interior_id == "cafe":
		return "CafeExitAutoPortal"
	var definition := INTERIOR_DEFINITIONS[interior_id] as Dictionary
	return "%sExitAutoPortal" % str(definition["node_name"]).trim_prefix("Indoor")


func _create_auto_portal(portal_name: String, portal_position: Vector2, portal_size: Vector2) -> Area2D:
	var portal := Area2D.new()
	portal.name = portal_name
	portal.position = portal_position
	portal.collision_layer = 0
	portal.collision_mask = 2
	portal.monitoring = true
	var collision := CollisionShape2D.new()
	collision.name = "Trigger"
	var rectangle := RectangleShape2D.new()
	rectangle.size = portal_size
	collision.shape = rectangle
	portal.add_child(collision)
	return portal


func _check_interior_auto_portals() -> void:
	if _portal_transition_active:
		return
	if _is_inside_interior():
		var definition := INTERIOR_DEFINITIONS[_active_interior_id] as Dictionary
		var local_position := _player.position - (definition["origin"] as Vector2)
		if _interior_exit_trigger_rect(definition, _interior_root).has_point(local_position):
			_exit_interior(_player, _active_interior_id)
		return
	if not _blocked_exterior_reentry_portal_id.is_empty():
		if _player_overlaps_exterior_portal(
			_blocked_exterior_reentry_portal_id,
		):
			return
		_blocked_exterior_reentry_portal_id = ""
	for portal_spec in EXTERIOR_INTERIOR_PORTALS:
		if _exterior_portal_rect(portal_spec).has_point(_player.position):
			_enter_interior(_player, str(portal_spec["id"]))
			return


func _player_overlaps_exterior_portal(portal_id: String) -> bool:
	var portal_spec := _exterior_portal_spec(portal_id)
	if portal_spec.is_empty():
		return false
	var player_foot_position := _player.position
	var player_clearance := 0.0
	if _player_feet_collision != null:
		player_foot_position += _player_feet_collision.position
		var feet_shape := _player_feet_collision.shape
		if feet_shape is CircleShape2D:
			player_clearance = (feet_shape as CircleShape2D).radius
	return _exterior_portal_rect(portal_spec).grow(
		player_clearance,
	).has_point(player_foot_position)


func _interior_exit_trigger_rect(
	definition: Dictionary,
	room: Node2D = null
) -> Rect2:
	if room != null:
		var exit_marker := room.get_node_or_null("IndoorExitPoint") as Marker2D
		if exit_marker != null:
			return Rect2(
				exit_marker.position - DOOR_THRESHOLD_TRIGGER_SIZE * 0.5,
				DOOR_THRESHOLD_TRIGGER_SIZE
			)
	if definition.has("exit_trigger_rect"):
		return definition["exit_trigger_rect"] as Rect2
	var exit_point := definition["exit_point"] as Vector2
	return Rect2(exit_point - DOOR_THRESHOLD_TRIGGER_SIZE * 0.5, DOOR_THRESHOLD_TRIGGER_SIZE)


func _exterior_portal_rect(portal_spec: Dictionary) -> Rect2:
	return PORTAL_CATALOG.exterior_trigger_rect(portal_spec)


func _door_threshold_size(authored_size: Vector2) -> Vector2:
	# 入口只占门洞中心的一条短门槛，避免门前整片区域误触发。
	return PORTAL_CATALOG.threshold_size({"size": authored_size})


func _exterior_portal_spec(portal_id: String) -> Dictionary:
	for portal_spec in EXTERIOR_INTERIOR_PORTALS:
		if str(portal_spec["id"]) == portal_id:
			return portal_spec
	return {}


func _is_inside_interior() -> bool:
	return not _active_interior_id.is_empty()


func _build_portal_transition() -> void:
	_portal_transition_layer.name = "InteriorTransition"
	_portal_transition_layer.layer = 1000
	add_child(_portal_transition_layer)
	_portal_transition_overlay.name = "FadeOverlay"
	_portal_transition_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portal_transition_overlay.color = Color("090c12")
	_portal_transition_overlay.modulate.a = 0.0
	_portal_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_portal_transition_overlay.visible = false
	_portal_transition_layer.add_child(_portal_transition_overlay)


func _fade_portal_to_black() -> void:
	if not is_instance_valid(_portal_transition_overlay):
		return
	_portal_transition_overlay.modulate.a = 0.0
	_portal_transition_overlay.visible = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(
		_portal_transition_overlay,
		"modulate:a",
		1.0,
		PORTAL_FADE_OUT_SECONDS
	)
	await tween.finished


func _fade_portal_from_black() -> void:
	if not is_instance_valid(_portal_transition_overlay):
		return
	if PORTAL_BLACK_HOLD_SECONDS > 0.0:
		await get_tree().create_timer(PORTAL_BLACK_HOLD_SECONDS).timeout
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		_portal_transition_overlay,
		"modulate:a",
		0.0,
		PORTAL_FADE_IN_SECONDS
	)
	await tween.finished
	_portal_transition_overlay.visible = false


# 传送黑屏完全遮盖、淡入开始之前的钩子。子类（TownRuntime）在此预同步
# 居民表现层的激活空间与权威位置，使淡入后玩家看到的就是已对齐的画面。
# entering_interior=true 表示刚进入室内房间，false 表示刚退回室外。
func _on_portal_black_covering(_entering_interior: bool) -> void:
	pass


func _enter_interior(body: Node2D, portal_id: String) -> void:
	if (
		body != _player
		or _is_inside_interior()
		or _portal_transition_active
		or portal_id == _blocked_exterior_reentry_portal_id
	):
		return
	var portal_spec := _exterior_portal_spec(portal_id)
	if portal_spec.is_empty():
		push_error("Unknown exterior interior portal: %s" % portal_id)
		return
	var interior_id := str(portal_spec["interior_id"])
	var definition := INTERIOR_DEFINITIONS.get(interior_id, {}) as Dictionary
	var room := _interior_roots.get(interior_id) as Node2D
	if definition.is_empty() or room == null:
		push_error("Interior is not available: %s" % interior_id)
		return

	_portal_transition_active = true
	_player.velocity = Vector2.ZERO
	await _fade_portal_to_black()
	if not is_inside_tree():
		return

	_outdoor_zoom_index = _zoom_index
	_active_interior_id = interior_id
	_active_exterior_portal_id = portal_id
	var portal_layout_path := _layout_path_for_portal(definition, portal_id)
	if (
		not portal_layout_path.is_empty()
		and room.has_method("set_furniture_layout_path")
		and not bool(room.set_furniture_layout_path(portal_layout_path))
	):
		push_error("Interior layout could not be selected: %s" % portal_layout_path)
	_active_furniture_layout = null
	_inside_furniture_room = false
	_interior_root = room
	room.visible = true
	if room.has_method("set_geometry_debug_visible"):
		room.set_geometry_debug_visible(_collision_debug_visible())
	var entry := room.get_node("IndoorEntryPoint") as Marker2D
	_player.position = room.position + entry.position
	_clear_player_blocking_normals()
	_set_camera_limits(_interior_camera_bounds(definition, room))
	_set_zoom_index(DEFAULT_ZOOM_INDEX)
	_weather_layer.visible = false
	_leaf_particles.emitting = false
	_world_tint.color = Color.WHITE
	for light in _environment_lights:
		light.energy = 0.0
	_cafe_furniture_edit_mode = false
	_cafe_furniture_entry_panel.visible = _inside_furniture_room
	_cafe_furniture_panel.visible = false
	if is_instance_valid(_map_control_panel):
		_map_control_panel.visible = false
	if _inside_furniture_room:
		_populate_furniture_library(interior_id)
		_refresh_cafe_furniture_panel()
	# 黑屏完全遮盖、淡入之前：让子类预同步表现层，玩家看到画面时即为对齐状态。
	_on_portal_black_covering(true)
	await _fade_portal_from_black()
	if not is_inside_tree():
		return
	_portal_transition_active = false
	_show_interior_location_title(str(definition["display_name"]))


func _exit_interior(body: Node2D, interior_id: String) -> void:
	if (
		body != _player
		or not _is_inside_interior()
		or interior_id != _active_interior_id
		or _portal_transition_active
	):
		return
	_portal_transition_active = true
	_player.velocity = Vector2.ZERO
	_hide_interior_location_title()
	var was_furniture_room := _inside_furniture_room
	var return_zoom_index := _outdoor_zoom_index
	await _fade_portal_to_black()
	if not is_inside_tree():
		return

	var portal_spec := _exterior_portal_spec(_active_exterior_portal_id)
	_blocked_exterior_reentry_portal_id = _active_exterior_portal_id
	_player.position = portal_spec.get("return", PLAYER_SPAWN) as Vector2
	_clear_player_blocking_normals()
	if _interior_root != null:
		_interior_root.visible = false
	_active_interior_id = ""
	_active_exterior_portal_id = ""
	_inside_furniture_room = false
	_interior_root = null
	_set_camera_limits(Rect2(Vector2.ZERO, MAP_SIZE))
	_set_zoom_index(return_zoom_index)
	_weather_layer.visible = true
	_leaf_particles.emitting = true
	_scene_name_banner.visible = false
	if was_furniture_room:
		exit_cafe_furniture_edit_mode()
	_cafe_furniture_entry_panel.visible = false
	_cafe_furniture_panel.visible = false
	if is_instance_valid(_map_control_panel):
		_map_control_panel.visible = true
	if was_furniture_room:
		save_cafe_furniture_state()
	_active_furniture_layout = null
	# 房间已隐藏、淡入之前：让子类预同步回室外表现层。
	_on_portal_black_covering(false)
	await _fade_portal_from_black()
	if not is_inside_tree():
		return
	_portal_transition_active = false


func _furniture_layout_for_interior(interior_id: String) -> Node2D:
	match interior_id:
		"cafe":
			return _cafe_layout
		"library":
			return _library_layout
		"town_hall":
			return _town_hall_layout
		"clinic":
			return _clinic_layout
	return null


func _layout_path_for_portal(definition: Dictionary, portal_id: String) -> String:
	var per_portal := definition.get("layout_paths_by_portal", {}) as Dictionary
	if per_portal.has(portal_id):
		return str(per_portal[portal_id])
	return str(definition.get("layout_path", ""))


func _interior_camera_bounds(
	definition: Dictionary,
	room: Node2D = null
) -> Rect2:
	if (
		room != null
		and definition.has("geometry_path")
		and room.has_method("get_shell_local_bounds")
	):
		var shell_bounds: Rect2 = room.get_shell_local_bounds()
		if shell_bounds.has_area():
			return Rect2(
				(definition["origin"] as Vector2) + shell_bounds.position,
				shell_bounds.size
			)
	if str(definition["node_name"]) == "IndoorCafe":
		return CAFE_INTERIOR_CAMERA_BOUNDS
	return Rect2(
		(definition["origin"] as Vector2) + INTERIOR_CAMERA_LOCAL_BOUNDS.position,
		INTERIOR_CAMERA_LOCAL_BOUNDS.size
	)


func _enter_cafe(body: Node2D) -> void:
	_enter_interior(body, "cafe")


func _exit_cafe(body: Node2D) -> void:
	_exit_interior(body, "cafe")


func _set_camera_limits(bounds: Rect2) -> void:
	_camera.limit_left = floori(bounds.position.x)
	_camera.limit_top = floori(bounds.position.y)
	_camera.limit_right = ceili(bounds.end.x)
	_camera.limit_bottom = ceili(bounds.end.y)


func _build_player() -> void:
	_player.name = "Player"
	_player.position = PLAYER_SPAWN
	_player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_player.z_index = 100
	_player.z_as_relative = false
	_player.collision_layer = 2
	_player.collision_mask = 1
	add_child(_player)
	_player_occlusion_foot_point = Marker2D.new()
	_player_occlusion_foot_point.name = "PlayerOcclusionFootPoint"
	_player_occlusion_foot_point.z_index = _player.z_index
	_player_occlusion_foot_point.z_as_relative = false
	_player_occlusion_foot_point.add_to_group(PLAYER_OCCLUSION_SUBJECT_GROUP)
	_player.add_child(_player_occlusion_foot_point)
	_player_feet_collision = CollisionShape2D.new()
	_player_feet_collision.name = "FeetCollision"
	_player_feet_collision.position = Vector2(0.0, -12.0)
	var feet_shape := CircleShape2D.new()
	feet_shape.radius = 18.0
	_player_feet_collision.shape = feet_shape
	_player.add_child(_player_feet_collision)

	_player_shadow = Polygon2D.new()
	_player_shadow.name = "Shadow"
	_player_shadow.position = Vector2(0.0, -3.0)
	_player_shadow.polygon = PackedVector2Array([
		Vector2(-30.0, 0.0), Vector2(-20.0, -7.0), Vector2(20.0, -7.0),
		Vector2(30.0, 0.0), Vector2(20.0, 7.0), Vector2(-20.0, 7.0),
	])
	_player_shadow.color = Color(0.02, 0.03, 0.04, 0.32)
	_player_shadow.z_as_relative = false
	_player_shadow.z_index = OUTDOOR_GROUND_SHADOW_Z_INDEX
	_player.add_child(_player_shadow)

	_player_visual_root = Node2D.new()
	_player_visual_root.name = "PaperDoll64Visual"
	_player_visual_root.scale = Vector2.ONE * PLAYER_DISPLAY_SCALE
	_player.add_child(_player_visual_root)
	_player_sprite = PAPER_DOLL_64_SPRITE_SCRIPT.new() as PaperDoll64Sprite
	_player_sprite.name = "CharacterSprite"
	_player_visual_root.add_child(_player_sprite)
	_player_sprite.configure_motion_speed(PLAYER_SPEED)


func _build_camera() -> void:
	_camera.name = "PlayerCamera"
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_camera.zoom = Vector2.ONE
	_set_camera_limits(Rect2(Vector2.ZERO, MAP_SIZE))
	add_child(_camera)
	_camera.make_current()
	get_viewport().size_changed.connect(_on_camera_viewport_size_changed)


func _build_environment_test() -> void:
	_world_tint.name = "DayNightTint"
	add_child(_world_tint)
	_build_environment_lights()

	_weather_layer.name = "WeatherOverlayLayer"
	_weather_layer.layer = 20
	add_child(_weather_layer)
	_weather_overlay.name = "CloudRainAndLightning"
	_weather_overlay.position = Vector2.ZERO
	_weather_overlay.size = get_viewport_rect().size
	_weather_overlay.color = Color.WHITE
	_weather_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = WEATHER_OVERLAY_SHADER_CODE
	_weather_material = ShaderMaterial.new()
	_weather_material.shader = shader
	_weather_overlay.material = _weather_material
	_weather_layer.add_child(_weather_overlay)
	_build_screen_leaf_particles(_weather_layer)
	_build_chimney_smoke()
	_build_thunder_audio()
	get_viewport().size_changed.connect(_resize_weather_overlay)
	_set_weather(0)


func _build_environment_lights() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.94, 0.74, 1.0),
		Color(1.0, 0.70, 0.30, 0.68),
		Color(1.0, 0.46, 0.12, 0.0),
	])
	var light_texture := GradientTexture2D.new()
	light_texture.gradient = gradient
	light_texture.width = 256
	light_texture.height = 256
	light_texture.fill = GradientTexture2D.FILL_RADIAL
	light_texture.fill_from = Vector2(0.5, 0.5)
	light_texture.fill_to = Vector2(1.0, 0.5)
	var light_specs: Array[Dictionary] = [
		{"name": "TownHallLampLeft", "position": Vector2(3005.0, 1175.0), "scale": 1.45, "energy": 1.05},
		{"name": "TownHallLampRight", "position": Vector2(3365.0, 1175.0), "scale": 1.45, "energy": 1.05},
		{"name": "TownHallWindowLeft", "position": Vector2(2860.0, 925.0), "scale": 1.15, "energy": 0.72},
		{"name": "TownHallWindowRight", "position": Vector2(3525.0, 925.0), "scale": 1.15, "energy": 0.72},
		{"name": "PlazaLampNorthLeft", "position": Vector2(2890.0, 1570.0), "scale": 1.35, "energy": 0.92},
		{"name": "PlazaLampNorthRight", "position": Vector2(3590.0, 1570.0), "scale": 1.35, "energy": 0.92},
		{"name": "PlazaLampSouthLeft", "position": Vector2(2890.0, 1885.0), "scale": 1.35, "energy": 0.92},
		{"name": "PlazaLampSouthRight", "position": Vector2(3590.0, 1885.0), "scale": 1.35, "energy": 0.92},
	]
	var light_root := Node2D.new()
	light_root.name = "NightLights"
	add_child(light_root)
	for spec in light_specs:
		var light := PointLight2D.new()
		light.name = str(spec["name"])
		light.position = spec["position"] as Vector2
		light.texture = light_texture
		light.texture_scale = float(spec["scale"])
		light.color = Color(1.0, 0.72, 0.34)
		light.energy = 0.0
		light.shadow_enabled = false
		light_root.add_child(light)
		_environment_lights.append(light)
		_light_base_energies.append(float(spec["energy"]))


func _build_screen_leaf_particles(weather_layer: CanvasLayer) -> void:
	_leaf_particles.name = "WindLeaves"
	_leaf_particles.amount = 28
	_leaf_particles.lifetime = 5.5
	_leaf_particles.preprocess = 5.5
	_leaf_particles.randomness = 0.72
	_leaf_particles.position = Vector2(get_viewport_rect().size.x * 0.5, -40.0)
	_leaf_particles.texture = _make_soft_particle_texture(10, Color(0.96, 0.67, 0.18, 0.92))
	_leaf_material = ParticleProcessMaterial.new()
	_leaf_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_leaf_material.emission_box_extents = Vector3(get_viewport_rect().size.x * 0.58, 24.0, 0.0)
	_leaf_material.direction = Vector3(0.18, 1.0, 0.0).normalized()
	_leaf_material.spread = 22.0
	_leaf_material.initial_velocity_min = 95.0
	_leaf_material.initial_velocity_max = 155.0
	_leaf_material.gravity = Vector3(8.0, 28.0, 0.0)
	_leaf_material.scale_min = 0.55
	_leaf_material.scale_max = 1.25
	_leaf_material.angular_velocity_min = -150.0
	_leaf_material.angular_velocity_max = 150.0
	_leaf_particles.process_material = _leaf_material
	weather_layer.add_child(_leaf_particles)


func _build_chimney_smoke() -> void:
	var smoke_root := Node2D.new()
	smoke_root.name = "ChimneySmoke"
	smoke_root.z_index = 230
	add_child(smoke_root)
	var smoke_texture := _make_soft_particle_texture(32, Color(0.78, 0.80, 0.82, 0.58))
	var smoke_gradient := Gradient.new()
	smoke_gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	smoke_gradient.colors = PackedColorArray([
		Color(0.76, 0.78, 0.80, 0.0),
		Color(0.70, 0.72, 0.75, 0.46),
		Color(0.62, 0.65, 0.69, 0.0),
	])
	var smoke_ramp := GradientTexture1D.new()
	smoke_ramp.gradient = smoke_gradient
	var chimney_positions: Array[Vector2] = [
		Vector2(3415.0, 650.0),
		Vector2(4390.0, 770.0),
		Vector2(5940.0, 1515.0),
		Vector2(1600.0, 2030.0),
		Vector2(2980.0, 2540.0),
		Vector2(5290.0, 2450.0),
	]
	for index in chimney_positions.size():
		var smoke := GPUParticles2D.new()
		smoke.name = "Smoke%02d" % (index + 1)
		smoke.position = chimney_positions[index]
		smoke.amount = 14
		smoke.lifetime = 4.8
		smoke.preprocess = 4.8
		smoke.randomness = 0.78
		smoke.texture = smoke_texture
		smoke.visibility_rect = Rect2(-180.0, -260.0, 360.0, 320.0)
		var material := ParticleProcessMaterial.new()
		material.direction = Vector3(0.12, -1.0, 0.0).normalized()
		material.spread = 20.0
		material.initial_velocity_min = 20.0
		material.initial_velocity_max = 34.0
		material.gravity = Vector3(3.0, -2.0, 0.0)
		material.scale_min = 0.42
		material.scale_max = 1.35
		material.color_ramp = smoke_ramp
		smoke.process_material = material
		smoke_root.add_child(smoke)
		_smoke_materials.append(material)


func _build_thunder_audio() -> void:
	_thunder_player.name = "ProceduralThunder"
	_thunder_player.volume_db = -11.0
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var duration := 1.75
	var sample_count := int(float(stream.mix_rate) * duration)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7142026
	var low_noise := 0.0
	for sample_index in sample_count:
		var time := float(sample_index) / float(stream.mix_rate)
		low_noise = low_noise * 0.955 + rng.randf_range(-1.0, 1.0) * 0.045
		var envelope := exp(-time * 1.65) * (0.72 + 0.28 * sin(time * 17.0) * sin(time * 17.0))
		var rumble := low_noise * 3.2 + sin(TAU * 48.0 * time) * 0.08
		var sample := int(clampf(rumble * envelope, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(sample_index * 2, sample)
	stream.data = bytes
	_thunder_player.stream = stream
	add_child(_thunder_player)


func _make_soft_particle_texture(size: int, color: Color) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size - 1, size - 1) * 0.5
	var radius := float(size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x, y).distance_to(center) / radius
			var alpha := clampf(1.0 - distance, 0.0, 1.0)
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha))
	return ImageTexture.create_from_image(image)


func _resize_weather_overlay() -> void:
	_weather_overlay.size = get_viewport_rect().size
	_leaf_particles.position = Vector2(get_viewport_rect().size.x * 0.5, -40.0)
	if _leaf_material != null:
		_leaf_material.emission_box_extents = Vector3(get_viewport_rect().size.x * 0.58, 24.0, 0.0)


func _update_environment_test(delta: float) -> void:
	if _is_inside_interior():
		_world_tint.color = Color.WHITE
		return
	if _environment_running:
		_environment_elapsed += delta
	_weather_shader_elapsed += delta
	_wind_strength = sin(_weather_shader_elapsed * 0.31) * 0.68 + sin(_weather_shader_elapsed * 0.11 + 1.2) * 0.32
	if _weather_auto:
		_weather_elapsed += delta
		if _weather_elapsed >= WEATHER_HOLD_SECONDS:
			_weather_elapsed = fmod(_weather_elapsed, WEATHER_HOLD_SECONDS)
			_set_weather((_weather_index + 1) % WEATHER_NAMES.size())

	if _weather_index == 2:
		_lightning_wait -= delta
		if _lightning_wait <= 0.0:
			_trigger_lightning()
			_lightning_wait = randf_range(2.2, 4.8)
	else:
		_lightning_wait = 2.0
	_lightning_flash = move_toward(_lightning_flash, 0.0, delta * 3.8)
	var rain_target := 0.0
	if _weather_index == 2:
		var rain_wave := sin(_weather_shader_elapsed * 0.72) * 0.22 + sin(_weather_shader_elapsed * 0.23 + 0.8) * 0.18
		rain_target = clampf(0.68 + rain_wave, 0.30, 1.0)
	_rain_intensity = move_toward(_rain_intensity, rain_target, delta * 0.42)

	var cycle := fmod(_environment_elapsed / DAY_CYCLE_SECONDS, 1.0)
	var weather_tint := Color.WHITE
	if _weather_index == 1:
		weather_tint = Color(0.84, 0.89, 0.94)
	elif _weather_index == 2:
		weather_tint = Color(0.68, 0.76, 0.84)
	_world_tint.color = _day_cycle_color(cycle) * weather_tint
	var night_factor := 0.5 - 0.5 * cos(TAU * cycle)
	var light_strength := smoothstep(0.36, 0.72, night_factor)
	for index in _environment_lights.size():
		var flicker := 0.97 + sin(_weather_shader_elapsed * 4.0 + float(index) * 1.7) * 0.03
		_environment_lights[index].energy = _light_base_energies[index] * light_strength * flicker
	if _leaf_material != null:
		_leaf_material.direction = Vector3(_wind_strength * 0.72, 1.0, 0.0).normalized()
		_leaf_material.gravity = Vector3(_wind_strength * 22.0, 28.0, 0.0)
	_leaf_particles.modulate.a = 0.36 if _weather_index == 2 else 0.92
	for smoke_material in _smoke_materials:
		smoke_material.direction = Vector3(_wind_strength * 0.42, -1.0, 0.0).normalized()
		smoke_material.gravity = Vector3(_wind_strength * 10.0, -2.0, 0.0)

	if _weather_material != null:
		_weather_material.set_shader_parameter("weather_time", _weather_shader_elapsed)
		_weather_material.set_shader_parameter("lightning_flash", _lightning_flash)
		_weather_material.set_shader_parameter("day_cycle", cycle)
		_weather_material.set_shader_parameter("night_factor", night_factor)
		_weather_material.set_shader_parameter("wind_strength", _wind_strength)
		_weather_material.set_shader_parameter("rain_intensity", _rain_intensity)


func _day_cycle_color(cycle: float) -> Color:
	if cycle < 0.25:
		return Color.WHITE.lerp(Color(1.0, 0.73, 0.55), smoothstep(0.0, 1.0, cycle / 0.25))
	if cycle < 0.5:
		return Color(1.0, 0.73, 0.55).lerp(Color(0.25, 0.34, 0.52), smoothstep(0.0, 1.0, (cycle - 0.25) / 0.25))
	if cycle < 0.75:
		return Color(0.25, 0.34, 0.52).lerp(Color(0.72, 0.63, 0.78), smoothstep(0.0, 1.0, (cycle - 0.5) / 0.25))
	return Color(0.72, 0.63, 0.78).lerp(Color.WHITE, smoothstep(0.0, 1.0, (cycle - 0.75) / 0.25))


func _day_phase_name() -> String:
	var cycle := fmod(_environment_elapsed / DAY_CYCLE_SECONDS, 1.0)
	if cycle < 0.18 or cycle >= 0.92:
		return "白天"
	if cycle < 0.42:
		return "黄昏"
	if cycle < 0.72:
		return "夜晚"
	return "清晨"


func _set_weather(index: int) -> void:
	_weather_index = posmod(index, WEATHER_NAMES.size())
	_weather_elapsed = 0.0
	if _weather_material != null:
		_weather_material.set_shader_parameter("weather_mode", float(_weather_index))


func _trigger_lightning() -> void:
	if _weather_index == 2:
		_lightning_flash = 1.0
		_camera_shake_time = 0.28
		_camera_shake_strength = 8.0 + _rain_intensity * 8.0
		var thunder_delay := randf_range(0.16, 0.42)
		get_tree().create_timer(thunder_delay).timeout.connect(_play_thunder)


func _play_thunder() -> void:
	if _thunder_player.playing:
		_thunder_player.stop()
	_thunder_player.pitch_scale = randf_range(0.90, 1.06)
	_thunder_player.play()


func _update_camera_feedback(delta: float) -> void:
	if _camera_shake_time > 0.0:
		_camera_shake_time -= delta
		var fade := clampf(_camera_shake_time / 0.28, 0.0, 1.0)
		_camera.offset = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * _camera_shake_strength * fade
	else:
		_camera.offset = _camera.offset.lerp(Vector2.ZERO, minf(1.0, delta * 14.0))


func _emit_footstep_effect() -> void:
	var effect := Node2D.new()
	var raining_outdoors := not _is_inside_interior() and _weather_index == 2
	effect.name = "RainStep" if raining_outdoors else "DustStep"
	effect.position = _player.position + Vector2(0.0, -3.0)
	effect.z_index = 95
	add_child(effect)
	if raining_outdoors:
		var ring := Line2D.new()
		ring.closed = true
		ring.width = 2.5
		ring.default_color = Color(0.66, 0.88, 1.0, 0.72)
		ring.points = _ellipse_points(13.0, 4.5, 18)
		effect.add_child(ring)
	else:
		for mote_index in 4:
			var mote := Polygon2D.new()
			var radius := randf_range(2.5, 5.5)
			mote.polygon = _ellipse_points(radius, radius, 8)
			mote.position = Vector2(randf_range(-13.0, 13.0), randf_range(-3.0, 6.0))
			mote.color = Color(0.77, 0.61, 0.37, 0.48 - float(mote_index) * 0.045)
			effect.add_child(mote)
	var tween := effect.create_tween()
	tween.set_parallel(true)
	tween.tween_property(effect, "scale", Vector2(1.75, 1.75), 0.42)
	tween.tween_property(effect, "position", effect.position + Vector2(-_wind_strength * 7.0, -9.0), 0.42)
	tween.tween_property(effect, "modulate:a", 0.0, 0.42)
	tween.chain().tween_callback(effect.queue_free)


func _ellipse_points(radius_x: float, radius_y: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in segments:
		var angle := TAU * float(index) / float(segments)
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PlayerUi"
	layer.layer = 100
	add_child(layer)
	var panel := ColorRect.new()
	panel.position = Vector2(12.0, 12.0)
	panel.size = Vector2(1500.0, 108.0)
	panel.color = Color(0.02, 0.03, 0.04, 0.88)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	_status_label.position = Vector2(24.0, 18.0)
	_status_label.add_theme_font_size_override("font_size", 19)
	_status_label.add_theme_color_override("font_color", Color("eef6ff"))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status_label)
	_build_map_control_panel(layer)
	_build_cafe_furniture_panel(layer)


func _build_interior_location_title() -> void:
	_scene_name_layer.name = "InteriorLocationTitle"
	_scene_name_layer.layer = 950
	add_child(_scene_name_layer)
	_scene_name_banner.name = "SceneNameBanner"
	_scene_name_banner.anchor_left = 0.5
	_scene_name_banner.anchor_right = 0.5
	_scene_name_banner.offset_left = -INTERIOR_TITLE_BANNER_SIZE.x * 0.5
	_scene_name_banner.offset_top = INTERIOR_TITLE_BANNER_TOP
	_scene_name_banner.offset_right = INTERIOR_TITLE_BANNER_SIZE.x * 0.5
	_scene_name_banner.offset_bottom = (
		INTERIOR_TITLE_BANNER_TOP + INTERIOR_TITLE_BANNER_SIZE.y
	)
	_scene_name_banner.texture = INTERIOR_LOCATION_TITLE_TEXTURE
	_scene_name_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scene_name_banner.stretch_mode = TextureRect.STRETCH_SCALE
	_scene_name_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_name_banner.modulate.a = 0.0
	_scene_name_banner.visible = false
	_scene_name_layer.add_child(_scene_name_banner)
	_scene_name_label.name = "SceneNameLabel"
	_scene_name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_name_label.offset_left = 18.0
	_scene_name_label.offset_top = 4.0
	_scene_name_label.offset_right = -48.0
	_scene_name_label.offset_bottom = -4.0
	_scene_name_label.text = ""
	_scene_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scene_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scene_name_label.add_theme_font_size_override("font_size", 22)
	_scene_name_label.add_theme_color_override("font_color", Color("4d321d"))
	_scene_name_label.add_theme_color_override(
		"font_outline_color",
		Color(1.0, 0.91, 0.67, 0.62)
	)
	_scene_name_label.add_theme_constant_override("outline_size", 2)
	_scene_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_name_banner.add_child(_scene_name_label)


func _show_interior_location_title(location_name: String) -> void:
	if location_name.is_empty() or not is_instance_valid(_scene_name_banner):
		return
	if _scene_name_tween != null and _scene_name_tween.is_valid():
		_scene_name_tween.kill()
	_scene_name_label.text = location_name
	_scene_name_banner.modulate.a = 0.0
	_scene_name_banner.visible = true
	_scene_name_tween = create_tween()
	_scene_name_tween.set_trans(Tween.TRANS_QUAD)
	_scene_name_tween.set_ease(Tween.EASE_OUT)
	_scene_name_tween.tween_property(
		_scene_name_banner,
		"modulate:a",
		1.0,
		INTERIOR_TITLE_FADE_IN_SECONDS
	)
	_scene_name_tween.tween_interval(INTERIOR_TITLE_HOLD_SECONDS)
	_scene_name_tween.set_ease(Tween.EASE_IN)
	_scene_name_tween.tween_property(
		_scene_name_banner,
		"modulate:a",
		0.0,
		INTERIOR_TITLE_FADE_OUT_SECONDS
	)
	_scene_name_tween.tween_callback(
		func() -> void:
			if is_instance_valid(_scene_name_banner):
				_scene_name_banner.visible = false
	)


func _hide_interior_location_title() -> void:
	if _scene_name_tween != null and _scene_name_tween.is_valid():
		_scene_name_tween.kill()
	if is_instance_valid(_scene_name_banner):
		_scene_name_banner.modulate.a = 0.0
		_scene_name_banner.visible = false


func _build_map_control_panel(layer: CanvasLayer) -> void:
	_map_control_panel = ColorRect.new()
	_map_control_panel.name = "MapControlPanel"
	_map_control_panel.anchor_left = 1.0
	_map_control_panel.anchor_right = 1.0
	_map_control_panel.offset_left = -390.0
	_map_control_panel.offset_top = 88.0
	_map_control_panel.offset_right = -16.0
	_map_control_panel.offset_bottom = 846.0
	_map_control_panel.color = Color(0.02, 0.03, 0.04, 0.90)
	layer.add_child(_map_control_panel)

	var column := VBoxContainer.new()
	column.position = Vector2(14.0, 14.0)
	column.size = Vector2(346.0, 730.0)
	column.add_theme_constant_override("separation", 9)
	_map_control_panel.add_child(column)
	var title := Label.new()
	title.text = "地图测试控制台"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("eef6ff"))
	column.add_child(title)
	_control_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_control_state_label.add_theme_font_size_override("font_size", 16)
	_control_state_label.add_theme_color_override("font_color", Color("b8cbc5"))
	column.add_child(_control_state_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	_add_control_button(grid, "sample", "到镇公所", _teleport_to_sample)
	_add_control_button(grid, "focus", "恢复视角", _focus_player)
	_add_control_button(grid, "overview", "全览地图", _show_map_overview)
	_add_control_button(grid, "water", "水面动画", _toggle_water)
	_add_control_button(grid, "collision", "碰撞显示", _toggle_collision_debug)
	_add_control_button(grid, "overlays", "地图标记", _toggle_map_overlays)
	_add_control_button(grid, "weather", "切换天气", _cycle_weather_manual)
	_add_control_button(grid, "weather_auto", "自动天气", _toggle_weather_auto)
	_add_control_button(grid, "day_cycle", "日夜循环", _toggle_day_cycle)
	_add_control_button(grid, "lightning", "触发闪电", _trigger_lightning)
	_add_control_button(grid, "zoom_out", "缩小视角", _zoom_out)
	_add_control_button(grid, "zoom_in", "放大视角", _zoom_in)
	_add_control_button(grid, "outfit_1", "服装 1", _set_preset.bind("elder_man"))
	_add_control_button(grid, "outfit_2", "服装 2", _set_preset.bind("skirt_woman"))
	_add_control_button(grid, "outfit_3", "服装 3", _set_preset.bind("suit_man"))
	_add_control_button(grid, "head", "切换头部", _cycle_slot.bind("head"))
	_add_control_button(grid, "top", "切换上衣", _cycle_slot.bind("top_hands"))
	_add_control_button(grid, "bottom", "切换下装", _cycle_slot.bind("bottom"))
	_add_control_button(grid, "shoes", "切换鞋子", _cycle_slot.bind("shoes"))


func _build_cafe_furniture_panel(layer: CanvasLayer) -> void:
	_cafe_furniture_entry_panel.name = "CafeFurnitureEditEntryPanel"
	_cafe_furniture_entry_panel.anchor_left = 1.0
	_cafe_furniture_entry_panel.anchor_right = 1.0
	_cafe_furniture_entry_panel.offset_left = -332.0
	_cafe_furniture_entry_panel.offset_top = 218.0
	_cafe_furniture_entry_panel.offset_right = -16.0
	_cafe_furniture_entry_panel.offset_bottom = 296.0
	_cafe_furniture_entry_panel.color = Color(0.035, 0.025, 0.02, 0.94)
	_cafe_furniture_entry_panel.visible = false
	layer.add_child(_cafe_furniture_entry_panel)
	_furniture_entry_button = Button.new()
	_furniture_entry_button.name = "EnterFurnitureEditButton"
	_furniture_entry_button.position = Vector2(10.0, 10.0)
	_furniture_entry_button.size = Vector2(296.0, 58.0)
	_furniture_entry_button.text = "进入家具编辑模式"
	_furniture_entry_button.add_theme_font_size_override("font_size", 20)
	_furniture_entry_button.pressed.connect(enter_cafe_furniture_edit_mode)
	_cafe_furniture_entry_panel.add_child(_furniture_entry_button)

	_cafe_furniture_panel.name = "CafeFurnitureEditorPanel"
	_cafe_furniture_panel.anchor_left = 1.0
	_cafe_furniture_panel.anchor_right = 1.0
	_cafe_furniture_panel.offset_left = -416.0
	_cafe_furniture_panel.offset_top = 198.0
	_cafe_furniture_panel.offset_right = -16.0
	_cafe_furniture_panel.offset_bottom = 1010.0
	_cafe_furniture_panel.color = Color(0.035, 0.025, 0.02, 0.94)
	_cafe_furniture_panel.visible = false
	layer.add_child(_cafe_furniture_panel)

	var column := VBoxContainer.new()
	column.position = Vector2(18.0, 18.0)
	column.size = Vector2(364.0, 776.0)
	column.add_theme_constant_override("separation", 9)
	_cafe_furniture_panel.add_child(column)

	_furniture_editor_title = Label.new()
	_furniture_editor_title.text = "咖啡馆家具编辑模式"
	_furniture_editor_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_furniture_editor_title.add_theme_font_size_override("font_size", 25)
	_furniture_editor_title.add_theme_color_override("font_color", Color("f3d486"))
	column.add_child(_furniture_editor_title)

	var library_title := Label.new()
	library_title.text = "家具库"
	library_title.add_theme_font_size_override("font_size", 19)
	library_title.add_theme_color_override("font_color", Color("eef6ff"))
	column.add_child(library_title)

	_furniture_library_grid = GridContainer.new()
	_furniture_library_grid.columns = 3
	_furniture_library_grid.add_theme_constant_override("h_separation", 8)
	_furniture_library_grid.add_theme_constant_override("v_separation", 8)
	column.add_child(_furniture_library_grid)
	_populate_furniture_library("cafe")

	_cafe_furniture_direction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cafe_furniture_direction_label.add_theme_font_size_override("font_size", 20)
	_cafe_furniture_direction_label.add_theme_color_override("font_color", Color("ffe6a7"))
	column.add_child(_cafe_furniture_direction_label)

	var help := Label.new()
	help.text = (
		"青格可用　红格已占用　金格是门槛或工作位\n"
		+ "按住家具拖动　松开落格　R旋转　右键取消"
	)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", Color("c8d6dc"))
	column.add_child(help)

	var direction_grid := GridContainer.new()
	direction_grid.columns = 2
	direction_grid.add_theme_constant_override("h_separation", 10)
	direction_grid.add_theme_constant_override("v_separation", 10)
	column.add_child(direction_grid)
	_add_cafe_direction_button(direction_grid, "down", "朝下 ↓")
	_add_cafe_direction_button(direction_grid, "right", "朝右 →")
	_add_cafe_direction_button(direction_grid, "up", "朝上 ↑")
	_add_cafe_direction_button(direction_grid, "left", "朝左 ←")

	var rotate_button := Button.new()
	rotate_button.name = "RotateClockwiseButton"
	rotate_button.text = "顺时针旋转（R）"
	rotate_button.custom_minimum_size = Vector2(360.0, 46.0)
	rotate_button.add_theme_font_size_override("font_size", 18)
	rotate_button.pressed.connect(rotate_cafe_furniture_clockwise)
	column.add_child(rotate_button)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	column.add_child(action_row)
	var save_button := Button.new()
	save_button.name = "SaveFurnitureButton"
	save_button.text = "保存布局"
	save_button.custom_minimum_size = Vector2(175.0, 48.0)
	save_button.add_theme_font_size_override("font_size", 17)
	save_button.pressed.connect(save_cafe_furniture_state)
	action_row.add_child(save_button)
	var reset_button := Button.new()
	reset_button.name = "ResetFurnitureButton"
	reset_button.text = "恢复规范布局"
	reset_button.custom_minimum_size = Vector2(175.0, 48.0)
	reset_button.add_theme_font_size_override("font_size", 17)
	reset_button.pressed.connect(reset_cafe_furniture_state)
	action_row.add_child(reset_button)

	var exit_button := Button.new()
	exit_button.name = "ExitFurnitureEditButton"
	exit_button.text = "完成并退出编辑模式（Esc）"
	exit_button.custom_minimum_size = Vector2(360.0, 48.0)
	exit_button.add_theme_font_size_override("font_size", 17)
	exit_button.pressed.connect(exit_cafe_furniture_edit_mode)
	column.add_child(exit_button)

	_cafe_furniture_feedback_label.text = "进入编辑后会显示全部可用地板格"
	_cafe_furniture_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cafe_furniture_feedback_label.add_theme_font_size_override("font_size", 15)
	_cafe_furniture_feedback_label.add_theme_color_override("font_color", Color("a9c7ad"))
	_cafe_furniture_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_cafe_furniture_feedback_label)
	_refresh_cafe_furniture_panel()


func _populate_furniture_library(interior_id: String) -> void:
	if not is_instance_valid(_furniture_library_grid):
		return
	for child in _furniture_library_grid.get_children():
		_furniture_library_grid.remove_child(child)
		child.queue_free()
	_cafe_decor_library_buttons.clear()
	for catalog_item in _furniture_catalog(interior_id):
		_add_cafe_library_button(
			_furniture_library_grid,
			str(catalog_item["asset_id"]),
			str(catalog_item["label"]),
			str(catalog_item["icon"])
		)
	var definition := INTERIOR_DEFINITIONS.get(interior_id, {}) as Dictionary
	var room_name := str(definition.get("display_name", "室内"))
	if is_instance_valid(_furniture_entry_button):
		_furniture_entry_button.text = "进入%s家具编辑模式" % room_name
	if is_instance_valid(_furniture_editor_title):
		_furniture_editor_title.text = "%s家具编辑模式" % room_name
	match interior_id:
		"library":
			_cafe_furniture_feedback_label.text = "金色格只标出南门门槛和借阅台工作位"
		"town_hall":
			_cafe_furniture_feedback_label.text = "金色格只标出南门门槛和办事柜台工作位"
		"clinic":
			_cafe_furniture_feedback_label.text = "金色格只标出南门门槛；问诊、等候和检查区由寻路连通性校验"
		_:
			_cafe_furniture_feedback_label.text = "金色格只标出南门、花房门槛和柜台工作位"


func _furniture_catalog(interior_id: String) -> Array[Dictionary]:
	var configured_layout := _furniture_layout_for_interior(interior_id)
	if is_instance_valid(configured_layout) and configured_layout.has_method("get_furniture_catalog"):
		var configured_catalog: Array[Dictionary] = []
		for item in configured_layout.get_furniture_catalog() as Array:
			configured_catalog.append(item as Dictionary)
		return configured_catalog
	return [
		{"asset_id": "counter", "label": "空柜台", "icon": "res://world/maps/town/interiors/cafe/assets/furniture/generated_v3/counter/counter_down.png"},
		{"asset_id": "espresso_machine", "label": "咖啡机", "icon": "res://world/maps/town/interiors/cafe/assets/furniture/generated_v3/espresso_machine/espresso_machine_down.png"},
		{"asset_id": "pastry_display", "label": "展示柜", "icon": "res://world/maps/town/interiors/cafe/assets/furniture/generated_v3/pastry_display/pastry_display_down.png"},
		{"asset_id": "round_table_large", "label": "四人圆桌", "icon": "res://world/maps/town/interiors/cafe/assets/furniture/generated_v3/round_table_large/round_table_large.png"},
		{"asset_id": "round_table_small", "label": "双人圆桌", "icon": "res://world/maps/town/interiors/cafe/assets/furniture/generated_v3/round_table_small/round_table_small.png"},
		{"asset_id": "wooden_chair", "label": "胡桃木椅", "icon": "res://world/maps/town/interiors/cafe/assets/furniture/generated_v3/wooden_chair/chair_down.png"},
		{"asset_id": "floor_lamp", "label": "落地暖灯", "icon": "res://world/maps/town/interiors/cafe/assets/furniture/generated_v3/floor_lamp/floor_lamp.png"},
		{"asset_id": "leafy_plant", "label": "阔叶盆栽", "icon": "res://world/maps/town/interiors/cafe/assets/furniture/generated_v3/leafy_plant/leafy_plant.png"},
		{"asset_id": "flowering_plant", "label": "粉花盆栽", "icon": "res://world/maps/town/interiors/cafe/assets/furniture/generated_v3/flowering_plant/flowering_plant.png"},
	]


func _add_cafe_library_button(
	parent: GridContainer,
	asset_id: String,
	button_text: String,
	icon_path: String
) -> void:
	var button := Button.new()
	button.name = "%sLibraryButton" % asset_id.to_pascal_case()
	button.text = button_text
	button.icon = _load_texture(icon_path)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(114.0, 74.0)
	button.add_theme_font_size_override("font_size", 14)
	_cafe_decor_library_buttons[asset_id] = button
	button.pressed.connect(select_cafe_decor_from_library.bind(asset_id))
	parent.add_child(button)


func _add_cafe_direction_button(parent: GridContainer, direction_id: String, button_text: String) -> void:
	var button := Button.new()
	button.name = "%sDirectionButton" % direction_id.capitalize()
	button.text = button_text
	button.custom_minimum_size = Vector2(175.0, 44.0)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(set_cafe_furniture_direction.bind(direction_id))
	parent.add_child(button)
	_cafe_furniture_direction_buttons[direction_id] = button


func enter_cafe_furniture_edit_mode() -> void:
	if not _inside_furniture_room:
		return
	_reset_furniture_drag_state()
	_cafe_furniture_edit_mode = true
	if is_instance_valid(_active_furniture_layout):
		_active_furniture_layout.call("set_editor_active", true)
	_cafe_furniture_entry_panel.visible = false
	_cafe_furniture_panel.visible = true
	_player.velocity = Vector2.ZERO
	_cafe_furniture_feedback_label.text = "按住家具拖动；绿色格可放，红色格已占用，金色格是门槛或工作位"
	_refresh_cafe_furniture_panel()


func exit_cafe_furniture_edit_mode() -> void:
	_reset_furniture_drag_state()
	if is_instance_valid(_active_furniture_layout):
		_active_furniture_layout.call("cancel_placement")
		_active_furniture_layout.call("save_state")
		_active_furniture_layout.call("set_editor_active", false)
	_cafe_furniture_edit_mode = false
	_rebuild_cafe_runtime_artifacts()
	_cafe_furniture_panel.visible = false
	_cafe_furniture_entry_panel.visible = _inside_furniture_room
	_refresh_cafe_furniture_panel()


func select_cafe_decor_from_library(asset_id: String) -> void:
	if not _cafe_furniture_edit_mode or not is_instance_valid(_active_furniture_layout):
		return
	_reset_furniture_drag_state()
	if bool(_active_furniture_layout.call("begin_placement", asset_id)):
		_cafe_furniture_feedback_label.text = "移动鼠标选择绿色地板格，按下并松开左键完成放置"
	_refresh_cafe_furniture_panel()


func place_cafe_furniture_at(local_position: Vector2) -> bool:
	if not _cafe_furniture_edit_mode:
		return false
	var placed := false
	var failure_message := "当前位置不可放置"
	if is_cafe_decor_placing():
		_active_furniture_layout.call("update_placement_position", local_position)
		placed = bool(_active_furniture_layout.call("confirm_placement"))
		failure_message = str(_active_furniture_layout.get("placement_error"))
	_cafe_furniture_feedback_label.text = (
		"家具已落格；按住它可以再次拖动" if placed
		else failure_message
	)
	_refresh_cafe_furniture_panel()
	return placed


func cancel_cafe_furniture_placement() -> void:
	_reset_furniture_drag_state()
	if is_instance_valid(_active_furniture_layout):
		_active_furniture_layout.call("cancel_placement")
	_cafe_furniture_feedback_label.text = "已取消本次放置"
	_refresh_cafe_furniture_panel()


func set_cafe_furniture_direction(direction_id: String) -> void:
	if not _cafe_furniture_edit_mode:
		return
	if is_cafe_decor_placing():
		_active_furniture_layout.call("set_direction", direction_id)


func rotate_cafe_furniture_clockwise() -> void:
	if not _cafe_furniture_edit_mode:
		return
	if not is_cafe_furniture_placing() and not is_cafe_furniture_placed():
		_cafe_furniture_feedback_label.text = "请先从家具库选择家具"
		return
	if is_cafe_decor_placing():
		_active_furniture_layout.call("rotate_clockwise")


func save_cafe_furniture_state() -> void:
	var saved := true
	if is_instance_valid(_active_furniture_layout):
		saved = bool(_active_furniture_layout.call("save_state")) and saved
	if saved:
		_rebuild_cafe_runtime_artifacts()
		_cafe_furniture_feedback_label.text = "家具布局已保存"


func reset_cafe_furniture_state() -> void:
	_reset_furniture_drag_state()
	if is_instance_valid(_active_furniture_layout):
		_active_furniture_layout.call("reset_to_default")
	_rebuild_cafe_runtime_artifacts()
	_cafe_furniture_feedback_label.text = "已恢复规范布局：工作区、入口和主通道均保持畅通"
	_refresh_cafe_furniture_panel()


func get_cafe_furniture_direction() -> String:
	if is_cafe_decor_placing():
		return str(_active_furniture_layout.get("current_direction"))
	return ""


func is_cafe_furniture_placing() -> bool:
	return is_cafe_chair_placing() or is_cafe_decor_placing()


func is_cafe_chair_placing() -> bool:
	return false


func is_cafe_decor_placing() -> bool:
	return is_instance_valid(_active_furniture_layout) and bool(_active_furniture_layout.get("is_placing"))


func is_cafe_furniture_placed() -> bool:
	return false


func _update_cafe_furniture_placement_preview() -> void:
	if not _inside_furniture_room or not _cafe_furniture_edit_mode or not is_cafe_furniture_placing():
		return
	var local_mouse_position := _interior_root.to_local(get_global_mouse_position())
	if is_cafe_decor_placing():
		var active_is_new := bool(_active_furniture_layout.call("is_active_item_new"))
		if active_is_new or _furniture_drag_active:
			_active_furniture_layout.call(
				"update_placement_position",
				local_mouse_position + _furniture_drag_offset
			)


func _update_cafe_depth_order() -> void:
	_update_player_ground_shadow_depth()
	if not _inside_furniture_room or not is_instance_valid(_interior_root):
		_player.z_index = 100
		return
	_player.z_as_relative = false
	# 室内人物始终是一张完整图，只用 CharacterBody2D 原点这个脚点参与遮挡命中。
	_player.z_index = CAFE_PLAYER_DEPTH
	if is_instance_valid(_active_furniture_layout):
		_active_furniture_layout.call("update_depth_for_subject", _player)


func _update_player_ground_shadow_depth() -> void:
	if not is_instance_valid(_player_shadow):
		return
	_player_shadow.z_as_relative = false
	_player_shadow.z_index = (
		INTERIOR_GROUND_SHADOW_Z_INDEX
		if _is_inside_interior()
		else OUTDOOR_GROUND_SHADOW_Z_INDEX
	)


func _rebuild_cafe_runtime_artifacts() -> bool:
	if not is_instance_valid(_active_furniture_layout):
		return false
	return false


func _begin_furniture_drag() -> void:
	if not is_instance_valid(_active_furniture_layout):
		return
	var local_mouse_position := _interior_root.to_local(get_global_mouse_position())
	if is_cafe_furniture_placing():
		_furniture_drag_active = true
		_furniture_drag_from_existing = not bool(
			_active_furniture_layout.call("is_active_item_new")
		)
		_furniture_drag_offset = Vector2.ZERO
		if _furniture_drag_from_existing:
			var existing_active_position: Vector2 = _active_furniture_layout.call("get_active_item_position")
			_furniture_drag_offset = existing_active_position - local_mouse_position
		_update_cafe_furniture_placement_preview()
		_refresh_furniture_placement_feedback()
		return
	if bool(_active_furniture_layout.call("try_pick_up_at", local_mouse_position)):
		_furniture_drag_active = true
		_furniture_drag_from_existing = true
		var picked_active_position: Vector2 = _active_furniture_layout.call("get_active_item_position")
		_furniture_drag_offset = picked_active_position - local_mouse_position
		_update_cafe_furniture_placement_preview()
		_refresh_furniture_placement_feedback()
	else:
		_cafe_furniture_feedback_label.text = "请按住家具本体或它脚下的占用格进行拖动"
	_refresh_cafe_furniture_panel()


func _finish_furniture_drag() -> void:
	if not _furniture_drag_active or not is_instance_valid(_active_furniture_layout):
		return
	var local_mouse_position := _interior_root.to_local(get_global_mouse_position())
	var target_position := local_mouse_position + _furniture_drag_offset
	var was_existing := _furniture_drag_from_existing
	var placed := place_cafe_furniture_at(target_position)
	if not placed and was_existing:
		var failure_message := str(_active_furniture_layout.get("placement_error"))
		_active_furniture_layout.call("cancel_placement")
		_cafe_furniture_feedback_label.text = "这里不能放，家具已回到原位：%s" % failure_message
	elif placed:
		_cafe_furniture_feedback_label.text = "家具已落格；继续按住其他家具即可拖动"
	_reset_furniture_drag_state()
	_refresh_cafe_furniture_panel()


func _refresh_furniture_placement_feedback() -> void:
	if not is_cafe_decor_placing() or not is_instance_valid(_active_furniture_layout):
		return
	if bool(_active_furniture_layout.get("placement_valid")):
		_cafe_furniture_feedback_label.text = "绿色占格：松开左键即可放下"
	else:
		var failure_message := str(_active_furniture_layout.get("placement_error"))
		_cafe_furniture_feedback_label.text = failure_message if not failure_message.is_empty() else "红色占格：当前位置不能放置"


func _reset_furniture_drag_state() -> void:
	_furniture_drag_active = false
	_furniture_drag_from_existing = false
	_furniture_drag_offset = Vector2.ZERO


func _on_cafe_furniture_direction_changed(direction_id: String) -> void:
	_refresh_cafe_furniture_panel()
	_cafe_furniture_feedback_label.text = "朝向已切换为：%s" % str(
		CAFE_FURNITURE_DIRECTION_NAMES.get(direction_id, direction_id)
	)


func _on_cafe_furniture_placement_state_changed(_is_placing: bool, _is_placed: bool) -> void:
	_refresh_cafe_furniture_panel()


func _on_cafe_furniture_state_saved(_save_path: String) -> void:
	_refresh_cafe_furniture_panel()


func _on_cafe_decor_placement_state_changed(_is_placing: bool) -> void:
	_refresh_cafe_furniture_panel()


func _on_cafe_decor_selection_changed(_asset_id: String, _direction_id: String) -> void:
	_refresh_cafe_furniture_panel()


func _on_cafe_decor_state_saved(_save_path: String) -> void:
	_refresh_cafe_furniture_panel()


func _refresh_cafe_furniture_panel() -> void:
	var direction_id := get_cafe_furniture_direction()
	var direction_name := str(CAFE_FURNITURE_DIRECTION_NAMES.get(direction_id, direction_id))
	var active_item := is_cafe_furniture_placing() or is_cafe_furniture_placed()
	_cafe_furniture_direction_label.text = (
		"当前朝向：%s" % direction_name if active_item
		else "尚未选择家具"
	)
	for id in _cafe_furniture_direction_buttons:
		var button := _cafe_furniture_direction_buttons[id] as Button
		if button != null:
			button.disabled = not _cafe_furniture_edit_mode or not active_item or str(id) == direction_id
	for asset_id in _cafe_decor_library_buttons:
		var library_button := _cafe_decor_library_buttons[asset_id] as Button
		if library_button != null:
			library_button.disabled = not _cafe_furniture_edit_mode


func _add_control_button(parent: GridContainer, id: String, text_value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(169.0, 46.0)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	parent.add_child(button)
	_control_buttons[id] = button


func _teleport_to_sample() -> void:
	_player.position = COLLISION_SAMPLE_SPAWN
	_clear_player_blocking_normals()
	_update_camera_target(true)


func _toggle_water() -> void:
	_water_overlay.visible = not _water_overlay.visible


func _toggle_collision_debug() -> void:
	var debug_overlay := _runtime_layers_canvas_item("DebugOverlay")
	var next_visible := not _collision_debug_visible()
	if debug_overlay != null:
		debug_overlay.visible = next_visible
	if (
		_is_inside_interior()
		and is_instance_valid(_interior_root)
		and _interior_root.has_method("set_geometry_debug_visible")
	):
		_interior_root.set_geometry_debug_visible(next_visible)


func _toggle_roof_occluder() -> void:
	var occlusion_debug := _runtime_layers_canvas_item("OcclusionDebug")
	if occlusion_debug != null:
		occlusion_debug.visible = not occlusion_debug.visible


func _toggle_map_overlays() -> void:
	_set_map_overlays_visible(not _map_overlays_visible())


func _set_map_overlays_visible(should_show: bool) -> void:
	for path in ["NavigationDebug", "DebugOverlay", "OcclusionDebug"]:
		var layer := _runtime_layers_canvas_item(path)
		if layer != null:
			layer.visible = should_show
	_refresh_map_overlay_button()


func _map_overlays_visible() -> bool:
	for path in ["NavigationDebug", "DebugOverlay", "OcclusionDebug"]:
		var layer := _runtime_layers_canvas_item(path)
		if layer != null and layer.visible:
			return true
	return false


func _refresh_map_overlay_button() -> void:
	var button := get_node_or_null("TownUi/CameraControls/OcclusionDebugButton") as Button
	if button != null:
		button.text = "地图标记：%s  O" % ("开" if _map_overlays_visible() else "关")


func _runtime_layers_canvas_item(path: String) -> CanvasItem:
	if _runtime_layer_loader == null:
		return null
	var runtime_layers := _runtime_layer_loader.get_node_or_null("MapRuntimeLayers")
	if runtime_layers == null:
		return null
	return runtime_layers.get_node_or_null(path) as CanvasItem


func _collision_debug_visible() -> bool:
	var debug_overlay := _runtime_layers_canvas_item("DebugOverlay")
	if debug_overlay != null:
		return debug_overlay.visible
	return false


func _runtime_occlusion_visible() -> bool:
	var occlusion_debug := _runtime_layers_canvas_item("OcclusionDebug")
	if occlusion_debug != null:
		return occlusion_debug.visible
	return false


func _cycle_weather_manual() -> void:
	_weather_auto = false
	_set_weather((_weather_index + 1) % WEATHER_NAMES.size())


func _toggle_weather_auto() -> void:
	_weather_auto = not _weather_auto
	_weather_elapsed = 0.0


func _toggle_day_cycle() -> void:
	_environment_running = not _environment_running


func _zoom_out() -> void:
	_set_zoom_index(_zoom_index - 1)


func _zoom_in() -> void:
	_set_zoom_index(_zoom_index + 1)


func _show_map_overview() -> void:
	if not _is_inside_interior():
		_set_zoom_index(OVERVIEW_ZOOM_INDEX)


func _read_move_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _clear_move_action_state() -> void:
	for action: StringName in [
		&"move_left",
		&"move_right",
		&"move_up",
		&"move_down",
	]:
		Input.action_release(action)


func _direction_from_vector(direction: Vector2) -> String:
	if absf(direction.x) >= absf(direction.y):
		return "right" if direction.x >= 0.0 else "left"
	return "down" if direction.y >= 0.0 else "up"


func _sync_player_visual() -> void:
	if _player_sprite != null:
		_player_sprite.set_preview_direction(int(DIRECTION_ROWS[_direction]))


func _set_preset(outfit_id: String) -> void:
	if not OUTFIT_NAMES.has(outfit_id) or _player_sprite == null:
		return
	if _player_sprite.set_loadout(outfit_id):
		_selection = _player_sprite.get_current_selection()


func _cycle_slot(slot: String) -> void:
	if not SLOT_ORDER.has(slot) or _player_sprite == null:
		return
	var current_id := str(_selection[slot])
	var current_index := maxi(0, OUTFIT_ORDER.find(current_id))
	var next_id := OUTFIT_ORDER[(current_index + 1) % OUTFIT_ORDER.size()]
	var candidate := _selection.duplicate(true)
	candidate[slot] = next_id
	if _player_sprite.set_selection(candidate):
		_selection = candidate


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
		if imported != null:
			return imported
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _outfit_state_text() -> String:
	var first_id := str(_selection["head"])
	for slot in SLOT_ORDER:
		if str(_selection[slot]) != first_id:
			return "自由混搭"
	return str(OUTFIT_NAMES[first_id])


func _clamp_player_position() -> void:
	if _is_inside_interior():
		var definition := INTERIOR_DEFINITIONS[_active_interior_id] as Dictionary
		var origin := definition["origin"] as Vector2
		var local_bounds := definition["local_bounds"] as Rect2
		if (
			definition.has("geometry_path")
			and is_instance_valid(_interior_root)
			and _interior_root.has_method("get_floor_local_bounds")
		):
			var geometry_bounds: Rect2 = _interior_root.get_floor_local_bounds()
			if geometry_bounds.has_area():
				local_bounds = geometry_bounds
		var local_position := _player.position - origin
		local_position.x = clampf(
			local_position.x,
			local_bounds.position.x,
			local_bounds.end.x
		)
		local_position.y = clampf(
			local_position.y,
			local_bounds.position.y,
			local_bounds.end.y
		)
		_player.position = origin + local_position
		_clear_player_blocking_normals()
		return
	var body_bounds := OUTDOOR_MOVEMENT_CLEARANCE.BODY_ORIGIN_BOUNDS
	_player.position.x = clampf(
		_player.position.x,
		body_bounds.position.x,
		body_bounds.end.x,
	)
	_player.position.y = clampf(
		_player.position.y,
		body_bounds.position.y,
		body_bounds.end.y,
	)
	_clear_player_blocking_normals()


func _focus_player() -> void:
	_set_zoom_index(DEFAULT_ZOOM_INDEX)


func _set_zoom_index(value: int) -> void:
	var minimum_index := 1 if _is_inside_interior() else OVERVIEW_ZOOM_INDEX
	_zoom_index = clampi(value, minimum_index, ZOOM_LEVELS.size() - 1)
	_camera.zoom = Vector2.ONE * _zoom_value_for_index(_zoom_index)
	_update_camera_target(true)


func _zoom_value_for_index(index: int) -> float:
	if index == OVERVIEW_ZOOM_INDEX:
		return _overview_zoom_value()
	return ZOOM_LEVELS[index]


func _overview_zoom_value() -> float:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 0.25
	return minf(viewport_size.x / MAP_SIZE.x, viewport_size.y / MAP_SIZE.y) * OVERVIEW_ZOOM_MARGIN


func _update_camera_target(reset_smoothing := false) -> void:
	if _zoom_index == OVERVIEW_ZOOM_INDEX and not _is_inside_interior():
		_camera.position = MAP_SIZE * 0.5
	else:
		_camera.position = _player.position
	if reset_smoothing:
		_camera.reset_smoothing()


func _on_camera_viewport_size_changed() -> void:
	if _zoom_index != OVERVIEW_ZOOM_INDEX or _is_inside_interior():
		return
	_camera.zoom = Vector2.ONE * _overview_zoom_value()
	_update_camera_target(true)


func _rain_strength_name() -> String:
	if _weather_index != 2:
		return "无雨"
	if _rain_intensity < 0.48:
		return "小雨"
	if _rain_intensity < 0.80:
		return "中雨"
	return "暴雨"


func _wind_state_text() -> String:
	var arrow := "→" if _wind_strength >= 0.0 else "←"
	return "%s%d%%" % [arrow, int(absf(_wind_strength) * 100.0)]


func _refresh_control_panel() -> void:
	if _control_buttons.is_empty():
		return
	(_control_buttons["water"] as Button).text = "水面：%s" % ("开" if _water_overlay.visible else "关")
	(_control_buttons["collision"] as Button).text = "碰撞框：%s" % ("开" if _collision_debug_visible() else "关")
	(_control_buttons["overlays"] as Button).text = "地图标记：%s" % ("开" if _map_overlays_visible() else "关")
	(_control_buttons["weather"] as Button).text = "天气：%s" % WEATHER_NAMES[_weather_index]
	(_control_buttons["weather_auto"] as Button).text = "天气自动：%s" % ("开" if _weather_auto else "关")
	(_control_buttons["day_cycle"] as Button).text = "日夜：%s" % ("运行" if _environment_running else "暂停")
	(_control_buttons["lightning"] as Button).disabled = _weather_index != 2
	_control_state_label.text = "%s · %s · 风 %s · 缩放 %.1fx" % [
		_day_phase_name(),
		_rain_strength_name(),
		_wind_state_text(),
		_camera.zoom.x,
	]


func _update_status() -> void:
	if _is_inside_interior():
		var definition := INTERIOR_DEFINITIONS[_active_interior_id] as Dictionary
		var local_position := _player.position - (definition["origin"] as Vector2)
		var display_name := str(definition["display_name"])
		var interior_instructions := "走到下方门口会自动返回室外"
		if _inside_furniture_room:
			if _cafe_furniture_edit_mode:
				interior_instructions = "家具编辑模式：人物已暂停移动\n32px网格放置　通道禁放　椅子吸附桌边　R旋转　Esc完成"
			elif is_cafe_furniture_placed():
				interior_instructions = "家具按占格碰撞和脚点顺序运行\n走到下方门口会自动返回室外"
			else:
				interior_instructions = "点击右侧按钮摆放家具\n坐姿交互由角色动画系统统一接入"
		_status_label.text = (
			"%s  |  室内坐标 (%d, %d)  |  %s  |  zoom %.1fx\n"
			+ "%s"
		) % [
			display_name,
			local_position.x,
			local_position.y,
			_outfit_state_text(),
			_camera.zoom.x,
			interior_instructions,
		]
		_refresh_control_panel()
		return
	_status_label.text = (
		"HD TOWN  |  (%d, %d)  |  %s  |  %s / %s  |  zoom %.1fx  |  water %s  |  collision %s\n"
		+ "日夜循环 %s　天气自动 %s　风 %s　雨势 %s　|　B切天气　H自动天气　N暂停日夜　M闪电\n"
		+ "WASD移动　滚轮缩放　0地图全览　F跟随视角　1/2/3换装　C碰撞层　O三层地图标记"
	) % [
		_player.position.x,
		_player.position.y,
		_outfit_state_text(),
		_day_phase_name(),
		WEATHER_NAMES[_weather_index],
		_camera.zoom.x,
		"ON" if _water_overlay.visible else "OFF",
		"DEBUG" if _collision_debug_visible() else "ON",
		"ON" if _environment_running else "PAUSED",
		"ON" if _weather_auto else "OFF",
		_wind_state_text(),
		_rain_strength_name(),
	]
	_refresh_control_panel()
