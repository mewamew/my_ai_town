class_name TownEnvironmentRenderer
extends Node


const VISUAL_CONFIG_PATH := "res://world/presentation/environment/town_environment_visuals.json"
const FORMAL_SPACES_PATH := "res://world/data/town/source/spaces.json"
const MAP_TEXTURE_PATH := (
	"res://world/maps/town/assets/runtime/town_4k.png"
)
const SURFACE_MASK_PATH := (
	"res://world/presentation/environment/assets/town_surface_masks.png"
)
const AUXILIARY_MASK_PATH := (
	"res://world/presentation/environment/assets/town_auxiliary_masks.png"
)
const SNOWFLAKE_ATLAS_PATH := (
	"res://world/presentation/environment/assets/particles/snowflake_atlas_v1.png"
)
const REDUCED_FLASHING_SETTING := "application/accessibility/reduced_flashing"
const DEFAULT_SNOW_PARTICLE_AMOUNT := 2600
const COMPATIBILITY_SNOW_PARTICLE_AMOUNT := 1400
const MINUTES_PER_DAY := 1440
const PRESENTATION_TIME_CYCLE_SECONDS := 86_400.0
const SMOKE_FADE_IN_SECONDS := 1.2
const SMOKE_FADE_OUT_SECONDS := 1.8
const ZERO_CONTRIBUTION_EPSILON := 0.001
const WINDOW_FACADE_REGION_CAPACITY := 32
const WINDOW_FACADE_SPACE_IDS := {
	"cafe": "indoor_flower_cafe",
	"library": "indoor_library",
	"town_hall": "indoor_town_hall",
	"clinic": "indoor_clinic",
	"dining_hall": "indoor_dining_hall",
	"workshop": "indoor_workshop",
	"dock_warehouse": "indoor_dock_warehouse",
}
# Authored map occluders sit at z=100 and may rise to z=101 while a resident
# walks behind them. Ground light belongs below those foreground cutouts, while
# the lit window pixels must be composited above them or the facade consumes the
# entire emissive layer.
const WINDOW_GROUND_PROJECTION_Z_INDEX := 90
const WINDOW_EMISSIVE_Z_INDEX := 110
const OVERLAY_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float elapsed = 0.0;
uniform float cloud = 0.0;
uniform float rain = 0.0;
uniform float rain_density = 0.0;
uniform float rain_width = 0.0;
uniform float rain_length = 0.0;
uniform float snow = 0.0;
uniform float wind = 0.0;
uniform float lightning_flash = 0.0;
uniform vec2 viewport_size_px = vec2(1920.0, 1080.0);
uniform vec2 camera_world_origin_px = vec2(0.0);
uniform vec4 screen_to_world_basis = vec4(1.0, 0.0, 0.0, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
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

float rain_layer(
	vec2 pixel,
	vec2 cell_size,
	float speed,
	float density,
	float width_scale,
	float length_scale,
	float seed
) {
	float slope = 0.12 + wind * 0.16;
	vec2 space = vec2(pixel.x + pixel.y * slope, pixel.y) / cell_size;
	space += vec2(elapsed * (speed * 0.31 + wind * 0.16), -elapsed * speed);
	vec2 cell = floor(space);
	vec2 local = fract(space);
	float cell_seed = hash21(cell + seed);
	float gate = step(1.0 - density, cell_seed);
	float x_center = mix(0.18, 0.82, hash21(cell + seed * 3.17));
	float width = mix(0.032, 0.068, hash21(cell + seed * 5.73)) * width_scale;
	float start = mix(0.06, 0.54, hash21(cell + seed * 7.31));
	float length = mix(0.16, 0.48, hash21(cell + seed * 11.19)) * length_scale;
	local.y = fract(local.y + cell_seed * 0.73);
	float line = 1.0 - step(width, abs(local.x - x_center));
	float length_gate = step(start, local.y) * (1.0 - step(min(0.96, start + length), local.y));
	return line * length_gate * gate;
}

void fragment() {
	vec2 screen_pixel = UV * viewport_size_px;
	vec2 world_pixel = camera_world_origin_px + vec2(
		screen_pixel.x * screen_to_world_basis.x
			+ screen_pixel.y * screen_to_world_basis.z,
		screen_pixel.x * screen_to_world_basis.y
			+ screen_pixel.y * screen_to_world_basis.w
	);
	// Rain is calculated in world pixels. Moving or zooming the camera reveals
	// a different part of a fixed storm instead of dragging a screen overlay.
	vec2 pixel = floor(world_pixel / 3.0) * 3.0;
	vec2 uv = pixel / vec2(6688.0, 3764.0);
	vec2 cloud_uv = uv * vec2(3.2, 2.0) + vec2(
		elapsed * (0.012 + wind * 0.016),
		elapsed * 0.003
	);
	float cloud_shape = value_noise(cloud_uv) * 0.68
		+ value_noise(cloud_uv * 2.03 + vec2(7.1, 2.3)) * 0.32;
	float cloud_alpha = cloud * mix(0.035, 0.145, smoothstep(0.32, 0.78, cloud_shape));

	float rain_line = 0.0;
	if (rain > 0.0) {
		float near_rain = rain_layer(
			pixel,
			vec2(42.0, 78.0),
			7.8,
			rain_density * 0.34,
			rain_width,
			rain_length,
			3.0
		);
		float middle_rain = rain_layer(
			pixel,
			vec2(31.0, 58.0),
			5.9,
			rain_density * 0.27,
			rain_width * 0.88,
			rain_length * 0.90,
			19.0
		);
		float far_rain = rain_layer(
			pixel,
			vec2(23.0, 42.0),
			4.4,
			rain_density * 0.20,
			rain_width * 0.72,
			rain_length * 0.78,
			47.0
		);
		rain_line = max(
			near_rain,
			max(middle_rain * 0.72, far_rain * 0.48)
		) * rain;
	}

	vec3 color = vec3(0.20, 0.27, 0.34);
	float alpha = cloud_alpha;
	if (rain_line > 0.0) {
		color = vec3(0.62, 0.80, 0.94);
		alpha = max(alpha, rain_line * mix(0.30, 0.56, rain));
	}
	if (lightning_flash > 0.0) {
		color = vec3(0.92, 0.96, 1.0);
		alpha = max(alpha, lightning_flash * 0.58);
	}
	COLOR = vec4(color, clamp(alpha, 0.0, 0.82));
}
"""
const WATER_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float elapsed = 0.0;
uniform float wind = 0.0;
uniform float rain = 0.0;
uniform float world_per_screen_px = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	float tide_phase = sin(elapsed * 0.34) * 0.5 + 0.5;
	float water_mask = texture(TEXTURE, UV).r;
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE / 3.0) * 3.0;
	vec2 flow = pixel + vec2(
		elapsed * (6.0 + wind * 5.0),
		-elapsed * (10.0 + rain * 5.0)
	);
	vec2 cell = floor(flow / vec2(54.0, 27.0));
	vec2 local = fract(flow / vec2(54.0, 27.0));
	float seed = hash21(cell);
	float dash = step(0.58, seed);
	float dash_half_width = max(0.055, world_per_screen_px * 1.35 / 27.0);
	dash *= 1.0 - step(dash_half_width, abs(local.y - mix(0.28, 0.72, seed)));
	float dash_start = 0.16;
	float dash_end = min(0.78, max(0.62, dash_start + world_per_screen_px * 4.0 / 54.0));
	dash *= step(dash_start, local.x) * (1.0 - step(dash_end, local.x));
	float rain_ripple = 0.0;
	if (rain > 0.0) {
		vec2 ripple_cell = floor(pixel / vec2(48.0, 30.0));
		vec2 ripple_local = fract(pixel / vec2(48.0, 30.0)) - vec2(0.5);
		float ripple_seed = hash21(ripple_cell + floor(elapsed * 3.0));
		float ripple_radius = fract(elapsed * mix(0.65, 1.1, ripple_seed));
		float ripple_distance = length(ripple_local * vec2(1.0, 1.7));
		rain_ripple = rain * step(mix(0.96, 0.74, rain), ripple_seed);
		float ripple_half_width = max(
			0.042,
			world_per_screen_px * 1.10 / 30.0
		);
		rain_ripple *= 1.0 - step(
			ripple_half_width,
			abs(ripple_distance - ripple_radius * 0.34)
		);
	}

	float shore_sample_px = max(4.0, world_per_screen_px * 2.2);
	vec2 edge_step = TEXTURE_PIXEL_SIZE * shore_sample_px;
	float north_land = 1.0 - texture(TEXTURE, UV - vec2(0.0, edge_step.y)).r;
	float south_land = 1.0 - texture(TEXTURE, UV + vec2(0.0, edge_step.y)).r;
	float west_land = 1.0 - texture(TEXTURE, UV - vec2(edge_step.x, 0.0)).r;
	float east_land = 1.0 - texture(TEXTURE, UV + vec2(edge_step.x, 0.0)).r;
	float shore = water_mask * max(max(north_land, south_land), max(west_land, east_land));
	float shore_wave = 0.5 + 0.5 * sin(
		elapsed * 2.15 + pixel.x * 0.045 + pixel.y * 0.031
	);
	float shore_spark = step(0.48, shore_wave) * mix(0.055, 0.13, tide_phase);

	// A broad, low-contrast current band survives map overview zoom without
	// turning the river into a noisy screen-space pattern.
	float current_phase = sin(
		pixel.y * 0.026
		+ sin(pixel.x * 0.009 + elapsed * 0.34) * 1.25
		- elapsed * (0.72 + wind * 0.22)
	);
	float current_band = smoothstep(0.72, 0.94, current_phase);
	float lod_boost = clamp(1.0 + (world_per_screen_px - 1.0) * 0.16, 1.0, 1.70);
	float alpha = water_mask * max(
		dash * 0.13 * lod_boost,
		max(rain_ripple * 0.23 * lod_boost, current_band * 0.055 * lod_boost)
	);
	alpha = max(alpha, shore * shore_spark * min(lod_boost, 1.35));
	vec3 river_color = mix(vec3(0.46, 0.72, 0.90), vec3(0.66, 0.86, 0.96), shore);
	COLOR = vec4(river_color, min(alpha, 0.24));
}
"""
const SURFACE_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D auxiliary_masks : filter_nearest, repeat_disable;
uniform sampler2D town_texture : filter_nearest, repeat_disable;
uniform float elapsed = 0.0;
uniform float rain = 0.0;
uniform float rain_impact = 0.0;
uniform float puddle_strength = 0.0;
uniform float wetness = 0.0;
uniform float wind = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 masks = texture(TEXTURE, UV);
	float ground = masks.g;
	float puddle = texture(auxiliary_masks, UV).g;
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE / 3.0) * 3.0;

	vec3 color = vec3(0.0);
	float alpha = 0.0;

	float wet_noise = hash21(floor(pixel / vec2(36.0, 24.0)));
	float wet_alpha = ground * wetness * mix(0.08, 0.15, wet_noise);
	color = vec3(0.06, 0.12, 0.16);
	alpha = wet_alpha;

	vec2 puddle_uv = UV + vec2(
		sin(elapsed * 0.55 + pixel.y * 0.008) * TEXTURE_PIXEL_SIZE.x * 3.0,
		-cos(elapsed * 0.38 + pixel.x * 0.006) * TEXTURE_PIXEL_SIZE.y * 2.0
	);
	vec3 reflected = texture(town_texture, puddle_uv).rgb;
	float puddle_alpha = puddle * wetness * mix(0.08, 0.38, puddle_strength);
	color = mix(color, mix(vec3(0.10, 0.20, 0.28), reflected, 0.16), puddle_alpha);
	alpha = max(alpha, puddle_alpha);

	vec2 impact_cell = floor(pixel / vec2(72.0, 48.0));
	vec2 impact_local = fract(pixel / vec2(72.0, 48.0)) - vec2(0.5);
	float impact_seed = hash21(impact_cell + floor(elapsed * 4.0));
	float impact_phase = fract(elapsed * mix(0.75, 1.35, impact_seed) + impact_seed);
	float impact_distance = length(impact_local * vec2(1.0, 1.8));
	float impact_ring = 1.0 - step(0.045, abs(impact_distance - impact_phase * 0.30));
	impact_ring *= step(mix(0.985, 0.82, rain_impact), impact_seed);
	impact_ring *= rain_impact * max(puddle, ground * 0.62);
	if (impact_ring > 0.0) {
		color = vec3(0.58, 0.78, 0.90);
		alpha = max(alpha, impact_ring * 0.30);
	}

	COLOR = vec4(color, clamp(alpha, 0.0, 0.94));
}
"""
const DIRECTIONAL_SHADOW_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D surface_masks : filter_nearest, repeat_disable;
uniform float elapsed = 0.0;
uniform vec2 shadow_offset_px = vec2(18.0, 24.0);
uniform float shadow_strength = 0.0;
uniform float cloud_shadow = 0.0;
uniform float wind = 0.0;
uniform vec3 shadow_color = vec3(0.12, 0.16, 0.24);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
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
	float ground = texture(surface_masks, UV).g;
	float caster_here = texture(TEXTURE, UV).r;
	float cast_shadow = 0.0;
	for (int sample_index = 1; sample_index <= 8; sample_index++) {
		float progress = float(sample_index) / 8.0;
		vec2 sample_uv = UV
			- shadow_offset_px * progress * TEXTURE_PIXEL_SIZE;
		cast_shadow = max(cast_shadow, texture(TEXTURE, sample_uv).r);
	}
	cast_shadow *= (1.0 - caster_here) * ground;

	float moving_cloud = 0.0;
	if (cloud_shadow > 0.0) {
		vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE / 3.0) * 3.0;
		vec2 cloud_uv = pixel / vec2(420.0, 260.0);
		cloud_uv += vec2(
			elapsed * (0.010 + wind * 0.010),
			elapsed * 0.003
		);
		float cloud_shape = value_noise(cloud_uv)
			* 0.66
			+ value_noise(cloud_uv * 2.03 + vec2(4.2, 7.8)) * 0.34;
		moving_cloud = smoothstep(0.48, 0.72, cloud_shape) * ground;
	}

	float alpha = max(
		cast_shadow * shadow_strength,
		moving_cloud * cloud_shadow
	);
	COLOR = vec4(shadow_color, clamp(alpha, 0.0, 0.40));
}
"""
const WINDOW_EMISSIVE_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float night_factor = 0.0;
uniform vec4 light_regions[32];
uniform int light_region_count = 0;

float occupied_facade(vec2 pixel) {
	float active = 0.0;
	for (int index = 0; index < 32; index++) {
		if (index < light_region_count) {
			vec4 region = light_regions[index];
			float inside = step(region.x, pixel.x)
				* step(region.y, pixel.y)
				* step(pixel.x, region.z)
				* step(pixel.y, region.w);
			active = max(active, inside);
		}
	}
	return active;
}

void fragment() {
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;
	float glow_class = texture(TEXTURE, UV).a;
	float occupied = occupied_facade(pixel);
	float far_glow = step(0.16, glow_class);
	float near_glow = step(0.50, glow_class);
	float source = step(0.83, glow_class);
	float glow_strength = max(
		source * 0.68,
		max(near_glow * 0.12, far_glow * 0.03)
	);
	float alpha = occupied * night_factor * glow_strength;
	vec3 color = mix(vec3(1.0, 0.52, 0.16), vec3(1.0, 0.84, 0.46), source);
	COLOR = vec4(color, alpha);
}
"""
const WINDOW_GROUND_PROJECTION_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform sampler2D surface_masks : filter_nearest, repeat_disable;
uniform float night_factor = 0.0;
uniform vec4 light_regions[32];
uniform int light_region_count = 0;

float occupied_facade(vec2 pixel) {
	float active = 0.0;
	for (int index = 0; index < 32; index++) {
		if (index < light_region_count) {
			vec4 region = light_regions[index];
			float inside = step(region.x, pixel.x)
				* step(region.y, pixel.y)
				* step(pixel.x, region.z)
				* step(pixel.y, region.w);
			active = max(active, inside);
		}
	}
	return active;
}

void fragment() {
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;
	float ground = texture(surface_masks, UV).g;
	float beam = texture(TEXTURE, UV).b;
	float occupied = occupied_facade(pixel);
	float alpha = beam * ground * occupied * night_factor * 0.14;
	COLOR = vec4(vec3(1.0, 0.64, 0.24), alpha);
}
"""

var _config: Dictionary = {}
var _formal_space_ids: Dictionary = {}
var _canvas_modulate := CanvasModulate.new()
var _overlay_layer := CanvasLayer.new()
var _overlay := ColorRect.new()
var _material := ShaderMaterial.new()
var _water_overlay := Sprite2D.new()
var _water_material := ShaderMaterial.new()
var _surface_overlay := Sprite2D.new()
var _surface_material := ShaderMaterial.new()
var _directional_shadow_overlay := Sprite2D.new()
var _directional_shadow_material := ShaderMaterial.new()
var _window_emissive_overlay := Sprite2D.new()
var _window_emissive_material := ShaderMaterial.new()
var _window_ground_projection := Sprite2D.new()
var _window_ground_projection_material := ShaderMaterial.new()
var _outdoor_effect_root := Node2D.new()
var _light_root := Node2D.new()
var _smoke_root := Node2D.new()
var _snow_root := Node2D.new()
var _snow_particles := GPUParticles2D.new()
var _snow_particle_material := ParticleProcessMaterial.new()
var _lights: Array[PointLight2D] = []
var _light_base_energy: Array[float] = []
var _smoke_particles: Array[GPUParticles2D] = []
var _smoke_materials: Array[ParticleProcessMaterial] = []
var _smoke_space_ids: Array[String] = []
var _smoke_activity: Array[float] = []
var _occupied_spaces: Dictionary = {}
var _window_facade_regions: Array[Dictionary] = []
var _window_light_region_count := 0
var _ground_pool_light_texture: Texture2D
var _elapsed := 0.0
var _outdoor_visible := true
var _last_ambient_color := Color.WHITE
var _last_interior_ambient := Color(0.97, 0.97, 0.95)
var _last_visual_state_key := ""
var _last_visual_state: Dictionary = {}
var _last_weather_canvas_transform := Transform2D.IDENTITY
var _weather_canvas_transform_initialized := false
var _presentation_paused := false
var _lightning_wait := 0.65
var _lightning_flash := 0.0
var _lightning_strike_elapsed := -1.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VISUAL_CONFIG_PATH))
	_config = parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}
	_formal_space_ids = _load_formal_space_ids()
	_window_facade_regions = _load_window_facade_regions()
	_rng.seed = 0x71A0E


func _ready() -> void:
	_canvas_modulate.name = "FormalWorldDayNightTint"
	add_child(_canvas_modulate)
	_overlay_layer.name = "FormalWorldWeatherOverlay"
	_overlay_layer.layer = 30
	add_child(_overlay_layer)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = OVERLAY_SHADER
	_material.shader = shader
	_overlay.material = _material
	_overlay_layer.add_child(_overlay)
	get_viewport().size_changed.connect(_sync_viewport_size)
	_sync_viewport_size()
	_build_outdoor_effects()
	_weather_canvas_transform_initialized = false
	_sync_weather_world_coordinates()
	_sync_zero_contribution_layers({})


func _process(_delta: float) -> void:
	_sync_weather_world_coordinates()


func set_presentation_paused(paused: bool) -> void:
	if paused == _presentation_paused:
		return
	_presentation_paused = paused
	var speed_scale := 0.0 if paused else 1.0
	if is_instance_valid(_snow_particles):
		_snow_particles.speed_scale = speed_scale
	for smoke: GPUParticles2D in _smoke_particles:
		if is_instance_valid(smoke):
			smoke.speed_scale = speed_scale


func apply_world_state(
	time_value: Variant,
	weather_value: Variant,
	delta_value: Variant,
) -> bool:
	var input := _validated_visual_input(time_value, weather_value)
	if input.is_empty() or not _is_finite_number(delta_value):
		return false
	var delta := float(delta_value)
	if delta < 0.0:
		return false
	var time := input.get("time", {}) as Dictionary
	var weather := String(input.get("weather", ""))
	var bounded_delta := fposmod(delta, PRESENTATION_TIME_CYCLE_SECONDS)
	var next_elapsed := fposmod(
		_elapsed + bounded_delta,
		PRESENTATION_TIME_CYCLE_SECONDS,
	)
	var effect_delta := minf(delta, PRESENTATION_TIME_CYCLE_SECONDS)
	if (
		not is_finite(bounded_delta)
		or not is_finite(next_elapsed)
		or not is_finite(effect_delta)
	):
		return false
	var state_key := "%d|%s" % [
		int(input.get("minuteOfDay", 0)),
		weather,
	]
	var state_changed := (
		state_key != _last_visual_state_key
		or _last_visual_state.is_empty()
	)
	var state := (
		visual_state(time, weather)
		if state_changed
		else _last_visual_state
	)
	if state.is_empty():
		return false
	if state_changed:
		_last_visual_state_key = state_key
		_last_visual_state = state.duplicate(true)
	_elapsed = next_elapsed
	_material.set_shader_parameter("elapsed", _elapsed)
	_update_lightning(
		float(state.get("lightning", 0.0)),
		effect_delta,
	)
	_material.set_shader_parameter("lightning_flash", _lightning_flash)
	_water_material.set_shader_parameter("elapsed", _elapsed)
	_surface_material.set_shader_parameter("elapsed", _elapsed)
	_directional_shadow_material.set_shader_parameter("elapsed", _elapsed)
	if state_changed:
		_last_ambient_color = state.get("ambientColor", Color.WHITE) as Color
		_last_interior_ambient = _interior_ambient_for(state)
		_canvas_modulate.color = (
			_last_ambient_color
			if _outdoor_visible
			else _last_interior_ambient
		)
		_material.set_shader_parameter("cloud", float(state.get("cloud", 0.0)))
		_material.set_shader_parameter("rain", float(state.get("rain", 0.0)))
		_material.set_shader_parameter(
			"rain_density",
			float(state.get("rainDensity", 0.0)),
		)
		_material.set_shader_parameter(
			"rain_width",
			float(state.get("rainWidth", 0.0)),
		)
		_material.set_shader_parameter(
			"rain_length",
			float(state.get("rainLength", 0.0)),
		)
		_material.set_shader_parameter("snow", float(state.get("snow", 0.0)))
		_material.set_shader_parameter("wind", float(state.get("wind", 0.0)))
		_water_material.set_shader_parameter("wind", float(state.get("wind", 0.0)))
		_water_material.set_shader_parameter("rain", float(state.get("rain", 0.0)))
		_surface_material.set_shader_parameter("rain", float(state.get("rain", 0.0)))
		_surface_material.set_shader_parameter(
			"rain_impact",
			float(state.get("rainImpact", 0.0)),
		)
		_surface_material.set_shader_parameter(
			"puddle_strength",
			float(state.get("puddleStrength", 0.0)),
		)
		_surface_material.set_shader_parameter(
			"wetness",
			float(state.get("wetness", 0.0)),
		)
		_surface_material.set_shader_parameter("wind", float(state.get("wind", 0.0)))
		_window_emissive_material.set_shader_parameter(
			"night_factor",
			float(state.get("nightFactor", 0.0)),
		)
		_window_ground_projection_material.set_shader_parameter(
			"night_factor",
			float(state.get("nightFactor", 0.0)),
		)
		_update_directional_shadow(state)
		_update_snowfall(state)
	_update_local_effects(state, effect_delta)
	_sync_zero_contribution_layers(state)
	return true


func set_space_occupancy(occupancy_value: Variant) -> bool:
	if not occupancy_value is Dictionary:
		return false
	if _formal_space_ids.is_empty():
		return false
	var occupancy_by_space := occupancy_value as Dictionary
	var next_occupied_spaces: Dictionary = {}
	for space_id_value: Variant in occupancy_by_space:
		if not space_id_value is String:
			return false
		var space_id := String(space_id_value)
		if (
			not _is_canonical_identifier(space_id)
			or not _formal_space_ids.has(space_id)
		):
			return false
		var count_value: Variant = occupancy_by_space.get(space_id_value)
		if typeof(count_value) != TYPE_INT:
			return false
		var count := int(count_value)
		if count < 0 or count > 1000:
			return false
		if count > 0:
			next_occupied_spaces[space_id] = count
	if next_occupied_spaces == _occupied_spaces:
		return true
	_occupied_spaces = next_occupied_spaces
	_sync_window_light_regions()
	return true


func get_smoke_emitter_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in _smoke_particles.size():
		result.append({
			"id": _smoke_particles[index].name,
			"spaceId": _smoke_space_ids[index],
			"activity": _smoke_activity[index],
			"amountRatio": _smoke_particles[index].amount_ratio,
			"emitting": _smoke_particles[index].emitting,
			"speedScale": _smoke_particles[index].speed_scale,
		})
	return result


func set_outdoor_visible(outdoor_value: Variant) -> bool:
	if typeof(outdoor_value) != TYPE_BOOL:
		return false
	var outdoor_visible := bool(outdoor_value)
	if outdoor_visible == _outdoor_visible:
		return true
	_outdoor_visible = outdoor_visible
	_overlay_layer.visible = outdoor_visible
	_outdoor_effect_root.visible = outdoor_visible
	_canvas_modulate.color = (
		_last_ambient_color
		if outdoor_visible
		else _last_interior_ambient
	)
	return true


func is_outdoor_visible() -> bool:
	return _outdoor_visible


func visual_state(time_value: Variant, weather_value: Variant) -> Dictionary:
	var input := _validated_visual_input(time_value, weather_value)
	if input.is_empty():
		return {}
	var minute_of_day := int(input.get("minuteOfDay", 0))
	var weather := String(input.get("weather", ""))
	var keyframes := _config.get("timeKeyframes", []) as Array
	if keyframes.size() < 2:
		return {"ambientColor": Color.WHITE, "cloud": 0.0, "rain": 0.0, "snow": 0.0, "lightning": 0.0}
	var left := keyframes[0] as Dictionary
	var right := keyframes[-1] as Dictionary
	for index in keyframes.size() - 1:
		var candidate_left := keyframes[index] as Dictionary
		var candidate_right := keyframes[index + 1] as Dictionary
		if minute_of_day >= int(candidate_left.get("minute", 0)) and minute_of_day <= int(candidate_right.get("minute", MINUTES_PER_DAY)):
			left = candidate_left
			right = candidate_right
			break
	var left_minute := int(left.get("minute", 0))
	var right_minute := int(right.get("minute", MINUTES_PER_DAY))
	var weight := 0.0 if right_minute <= left_minute else float(minute_of_day - left_minute) / float(right_minute - left_minute)
	var ambient := Color.html(String(left.get("ambient", "ffffff"))).lerp(
		Color.html(String(right.get("ambient", "ffffff"))),
		clampf(weight, 0.0, 1.0),
	)
	var style := weather_style_for_accessibility(
		(_config.get("weather", {}) as Dictionary).get(weather, {}) as Dictionary,
	)
	var tint := Color.html(String(style.get("tint", "ffffff")))
	var night_factor := _night_factor(minute_of_day)
	var midnight_distance := minf(float(minute_of_day), float(MINUTES_PER_DAY - minute_of_day))
	var moon_peak := 1.0 - smoothstep(0.0, 360.0, midnight_distance)
	ambient = ambient.lerp(
		Color(0.58, 0.69, 0.88),
		night_factor * moon_peak * 0.18,
	)
	return {
		"ambientColor": ambient * tint,
		"cloud": float(style.get("cloud", 0.0)),
		"rain": float(style.get("rain", 0.0)),
		"snow": float(style.get("snow", 0.0)),
		"lightning": float(style.get("lightning", 0.0)),
		"reducedLightning": bool(style.get("reducedLightning", false)),
		"wind": float(style.get("wind", 0.0)),
		"wetness": float(style.get("wetness", 0.0)),
		"rainDensity": float(style.get("rainDensity", 0.0)),
		"rainWidth": float(style.get("rainWidth", 0.0)),
		"rainLength": float(style.get("rainLength", 0.0)),
		"rainImpact": float(style.get("rainImpact", 0.0)),
		"puddleStrength": float(style.get("puddleStrength", 0.0)),
		"cloudShadow": float(style.get("cloudShadow", 0.0)),
		"nightFactor": night_factor,
		"minuteOfDay": minute_of_day,
	}


func _night_factor(minute_of_day: int) -> float:
	var dusk := smoothstep(1080.0, 1260.0, float(minute_of_day))
	var dawn := smoothstep(300.0, 480.0, float(minute_of_day))
	return clampf(maxf(dusk, 1.0 - dawn), 0.0, 1.0)


func _interior_ambient_for(state: Dictionary) -> Color:
	var night := float(state.get("nightFactor", 0.0))
	var cloud := float(state.get("cloud", 0.0))
	var base := Color(0.97, 0.97, 0.95).lerp(
		Color(0.64, 0.70, 0.82),
		night * 0.72,
	)
	return base.lerp(Color(0.78, 0.82, 0.86), cloud * 0.10)


func _sync_viewport_size() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_material.set_shader_parameter("viewport_size_px", viewport_size)
	_sync_weather_world_coordinates()


func _sync_weather_world_coordinates() -> void:
	if _material.shader == null:
		return
	var canvas_transform := get_viewport().get_canvas_transform()
	if (
		_weather_canvas_transform_initialized
		and canvas_transform == _last_weather_canvas_transform
	):
		return
	_last_weather_canvas_transform = canvas_transform
	_weather_canvas_transform_initialized = true
	var inverse_canvas := canvas_transform.affine_inverse()
	_material.set_shader_parameter("camera_world_origin_px", inverse_canvas.origin)
	_material.set_shader_parameter(
		"screen_to_world_basis",
		Vector4(
			inverse_canvas.x.x,
			inverse_canvas.x.y,
			inverse_canvas.y.x,
			inverse_canvas.y.y,
		),
	)
	if _water_material.shader != null:
		_water_material.set_shader_parameter(
			"world_per_screen_px",
			maxf(inverse_canvas.x.length(), inverse_canvas.y.length()),
		)


func _build_outdoor_effects() -> void:
	_outdoor_effect_root.name = "FormalWorldLocalEnvironment"
	add_child(_outdoor_effect_root)
	_build_directional_shadow_overlay()
	_build_water_overlay()
	_build_surface_overlay()
	_build_window_emissive_overlay()
	_build_window_ground_projection()
	_build_local_lights()
	_build_pixel_smoke()
	_build_snowfall()
	_sync_window_light_regions()


func _build_snowfall() -> void:
	var atlas := load(SNOWFLAKE_ATLAS_PATH) as Texture2D
	if atlas == null:
		push_error("Formal environment could not load the authored snowflake atlas")
		return
	_snow_root.name = "FormalWorldSnowfall"
	_snow_root.z_index = 96
	_outdoor_effect_root.add_child(_snow_root)

	_snow_particles.name = "FormalWorldSnowParticles"
	_snow_particles.position = Vector2(3344.0, 1882.0)
	_snow_particles.amount = snow_particle_budget_for_rendering_method(
		RenderingServer.get_current_rendering_method(),
	)
	_snow_particles.amount_ratio = 0.0
	_snow_particles.lifetime = 32.0
	_snow_particles.preprocess = 32.0
	_snow_particles.randomness = 0.82
	_snow_particles.fixed_fps = 30
	_snow_particles.local_coords = false
	_snow_particles.texture = atlas
	_snow_particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_snow_particles.visibility_rect = Rect2(-3600.0, -2200.0, 7200.0, 4400.0)
	var atlas_material := CanvasItemMaterial.new()
	atlas_material.particles_animation = true
	atlas_material.particles_anim_h_frames = 2
	atlas_material.particles_anim_v_frames = 2
	atlas_material.particles_anim_loop = false
	_snow_particles.material = atlas_material

	_snow_particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Spawn across the whole town instead of from a camera-like strip. Snow then
	# exists in world space and drifts past the player rather than following them.
	_snow_particle_material.emission_box_extents = Vector3(3480.0, 1980.0, 0.0)
	_snow_particle_material.direction = Vector3(0.18, 1.0, 0.0).normalized()
	_snow_particle_material.spread = 34.0
	_snow_particle_material.initial_velocity_min = 12.0
	_snow_particle_material.initial_velocity_max = 26.0
	_snow_particle_material.gravity = Vector3(1.2, 0.8, 0.0)
	_snow_particle_material.angular_velocity_min = -18.0
	_snow_particle_material.angular_velocity_max = 18.0
	_snow_particle_material.scale_min = 0.88
	_snow_particle_material.scale_max = 1.20
	_snow_particle_material.anim_offset_min = 0.0
	_snow_particle_material.anim_offset_max = 0.74
	_snow_particle_material.anim_speed_min = 0.0
	_snow_particle_material.anim_speed_max = 0.0
	_snow_particle_material.color = Color(0.96, 0.98, 1.0, 0.90)
	_snow_particles.process_material = _snow_particle_material
	_snow_root.add_child(_snow_particles)


static func snow_particle_budget_for_rendering_method(
	rendering_method: String,
) -> int:
	return (
		COMPATIBILITY_SNOW_PARTICLE_AMOUNT
		if rendering_method == "gl_compatibility"
		else DEFAULT_SNOW_PARTICLE_AMOUNT
	)


func _build_directional_shadow_overlay() -> void:
	var shadow_casters := load(AUXILIARY_MASK_PATH) as Texture2D
	var surface_masks := load(SURFACE_MASK_PATH) as Texture2D
	if shadow_casters == null or surface_masks == null:
		push_error("Formal environment directional shadow masks are incomplete")
		return
	_directional_shadow_overlay.name = "FormalWorldDirectionalShadow"
	_directional_shadow_overlay.texture = shadow_casters
	_directional_shadow_overlay.centered = false
	_directional_shadow_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_directional_shadow_overlay.z_index = 9
	var shader := Shader.new()
	shader.code = DIRECTIONAL_SHADOW_SHADER
	_directional_shadow_material.shader = shader
	_directional_shadow_material.set_shader_parameter("surface_masks", surface_masks)
	_directional_shadow_overlay.material = _directional_shadow_material
	_outdoor_effect_root.add_child(_directional_shadow_overlay)


func _build_water_overlay() -> void:
	var texture := load(SURFACE_MASK_PATH) as Texture2D
	if texture == null:
		push_error("Formal environment could not load the authored town surface mask")
		return
	_water_overlay.name = "FormalWorldWaterMotion"
	_water_overlay.texture = texture
	_water_overlay.centered = false
	_water_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_water_overlay.z_index = 10
	var shader := Shader.new()
	shader.code = WATER_SHADER
	_water_material.shader = shader
	_water_overlay.material = _water_material
	_outdoor_effect_root.add_child(_water_overlay)


func _build_surface_overlay() -> void:
	var surface_masks := load(SURFACE_MASK_PATH) as Texture2D
	var auxiliary_masks := load(AUXILIARY_MASK_PATH) as Texture2D
	var town_texture := load(MAP_TEXTURE_PATH) as Texture2D
	if (
		surface_masks == null
		or auxiliary_masks == null
		or town_texture == null
	):
		push_error("Formal environment surface masks are incomplete")
		return
	_surface_overlay.name = "FormalWorldGroundWeather"
	_surface_overlay.texture = surface_masks
	_surface_overlay.centered = false
	_surface_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_surface_overlay.z_index = 11
	var shader := Shader.new()
	shader.code = SURFACE_SHADER
	_surface_material.shader = shader
	_surface_material.set_shader_parameter("auxiliary_masks", auxiliary_masks)
	_surface_material.set_shader_parameter("town_texture", town_texture)
	_surface_overlay.material = _surface_material
	_outdoor_effect_root.add_child(_surface_overlay)


func _build_window_emissive_overlay() -> void:
	var texture := load(AUXILIARY_MASK_PATH) as Texture2D
	if texture == null:
		push_error("Formal environment could not load the exact window emissive mask")
		return
	_window_emissive_overlay.name = "FormalWorldWindowEmissive"
	_window_emissive_overlay.texture = texture
	_window_emissive_overlay.centered = false
	_window_emissive_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_window_emissive_overlay.z_index = WINDOW_EMISSIVE_Z_INDEX
	var shader := Shader.new()
	shader.code = WINDOW_EMISSIVE_SHADER
	_window_emissive_material.shader = shader
	_window_emissive_overlay.material = _window_emissive_material
	_outdoor_effect_root.add_child(_window_emissive_overlay)


func _build_window_ground_projection() -> void:
	var window_mask := load(AUXILIARY_MASK_PATH) as Texture2D
	var surface_masks := load(SURFACE_MASK_PATH) as Texture2D
	if window_mask == null or surface_masks == null:
		push_error("Formal environment window ground projection masks are incomplete")
		return
	_window_ground_projection.name = "FormalWorldWindowGroundProjection"
	_window_ground_projection.texture = window_mask
	_window_ground_projection.centered = false
	_window_ground_projection.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_window_ground_projection.z_index = WINDOW_GROUND_PROJECTION_Z_INDEX
	var shader := Shader.new()
	shader.code = WINDOW_GROUND_PROJECTION_SHADER
	_window_ground_projection_material.shader = shader
	_window_ground_projection_material.set_shader_parameter("surface_masks", surface_masks)
	_window_ground_projection.material = _window_ground_projection_material
	_outdoor_effect_root.add_child(_window_ground_projection)


func _build_local_lights() -> void:
	_light_root.name = "FormalWorldLocalLights"
	_outdoor_effect_root.add_child(_light_root)
	var texture := _make_stepped_light_texture()
	for value in _config.get("localLights", []) as Array:
		var spec := value as Dictionary
		var light := PointLight2D.new()
		light.name = String(spec.get("id", "LocalLight"))
		light.position = _vector2(spec.get("position", [0, 0]))
		light.texture = texture
		light.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		light.texture_scale = float(spec.get("textureScale", 1.0))
		light.color = Color.html(String(spec.get("color", "ffc36b")))
		light.energy = 0.0
		light.shadow_enabled = false
		_light_root.add_child(light)
		_lights.append(light)
		_light_base_energy.append(float(spec.get("energy", 0.8)))
		var ground_pool := PointLight2D.new()
		ground_pool.name = "%sGroundPool" % light.name
		ground_pool.position = light.position + Vector2(0.0, 58.0)
		ground_pool.texture = _make_ground_pool_light_texture()
		ground_pool.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ground_pool.texture_scale = float(spec.get("textureScale", 1.0)) * 1.12
		ground_pool.color = Color.html(String(spec.get("color", "ffc36b")))
		ground_pool.energy = 0.0
		ground_pool.shadow_enabled = false
		_light_root.add_child(ground_pool)
		_lights.append(ground_pool)
		_light_base_energy.append(float(spec.get("energy", 0.8)) * 0.72)


func _build_pixel_smoke() -> void:
	_smoke_root.name = "FormalWorldChimneySmoke"
	_smoke_root.z_index = 80
	_outdoor_effect_root.add_child(_smoke_root)
	var texture := _make_pixel_smoke_texture()
	for value in _config.get("smokeEmitters", []) as Array:
		var spec := value as Dictionary
		var smoke := GPUParticles2D.new()
		smoke.name = String(spec.get("id", "Smoke"))
		smoke.position = _vector2(spec.get("position", [0, 0]))
		smoke.amount = int(spec.get("amount", 9))
		smoke.lifetime = float(spec.get("lifetime", 4.2))
		smoke.preprocess = 0.0
		smoke.randomness = 0.55
		smoke.emitting = false
		smoke.amount_ratio = 0.0
		smoke.texture = texture
		smoke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		smoke.visibility_rect = Rect2(-160.0, -240.0, 320.0, 300.0)
		var material := ParticleProcessMaterial.new()
		material.direction = Vector3(0.08, -1.0, 0.0).normalized()
		material.spread = 12.0
		material.initial_velocity_min = 15.0
		material.initial_velocity_max = 25.0
		material.gravity = Vector3(2.0, -1.0, 0.0)
		material.scale_min = 0.8
		material.scale_max = 1.45
		material.color = Color(0.69, 0.72, 0.75, 0.42)
		smoke.process_material = material
		_smoke_root.add_child(smoke)
		_smoke_particles.append(smoke)
		_smoke_materials.append(material)
		_smoke_space_ids.append(String(spec.get("spaceId", "")).strip_edges())
		_smoke_activity.append(0.0)


func _make_stepped_light_texture() -> Texture2D:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size - 1, size - 1) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x, y).distance_to(center) / (float(size) * 0.5)
			var continuous := pow(maxf(0.0, 1.0 - distance), 1.65) * 0.86
			var alpha := floorf(continuous * 12.0) / 12.0
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _make_ground_pool_light_texture() -> Texture2D:
	if _ground_pool_light_texture != null:
		return _ground_pool_light_texture
	var width := 180
	var height := 108
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var center := Vector2(width - 1, height - 1) * 0.5
	var radii := Vector2(float(width) * 0.5, float(height) * 0.5)
	for y in height:
		for x in width:
			var sample := Vector2(floori(x / 3) * 3 + 1, floori(y / 3) * 3 + 1)
			var normalized := (sample - center) / radii
			var distance := normalized.length()
			var continuous := pow(maxf(0.0, 1.0 - distance), 1.55) * 0.72
			var alpha := floorf(continuous * 10.0 + 0.5) / 10.0
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_ground_pool_light_texture = ImageTexture.create_from_image(image)
	return _ground_pool_light_texture


func _make_pixel_smoke_texture() -> Texture2D:
	var image := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var color := Color(0.78, 0.80, 0.82, 0.78)
	for y in range(3, 15):
		for x in range(3, 15):
			var cell := Vector2i(x / 3, y / 3)
			if (
				cell in [
					Vector2i(1, 2),
					Vector2i(2, 1),
					Vector2i(2, 2),
					Vector2i(2, 3),
					Vector2i(3, 2),
					Vector2i(3, 3),
				]
			):
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _update_lightning(
	flash_intensity: float,
	delta: float,
) -> void:
	if flash_intensity <= 0.0:
		_lightning_wait = 0.65
		_lightning_strike_elapsed = -1.0
		_lightning_flash = move_toward(_lightning_flash, 0.0, delta * 8.0)
		return
	if _lightning_strike_elapsed >= 0.0:
		_lightning_strike_elapsed += maxf(delta, 0.0)
		var strike_time := _lightning_strike_elapsed
		var reduced_flashing := bool(
			ProjectSettings.get_setting(REDUCED_FLASHING_SETTING, false),
		)
		if reduced_flashing and strike_time < 0.46:
			# Accessibility mode keeps one slow, low-luminance cloud flash so
			# thunderstorm remains readable without a strobing double pulse.
			_lightning_flash = (
				flash_intensity
				* (1.0 - smoothstep(0.0, 0.46, strike_time))
			)
		elif reduced_flashing:
			_lightning_flash = 0.0
			_lightning_strike_elapsed = -1.0
		elif strike_time < 0.07:
			_lightning_flash = flash_intensity
		elif strike_time < 0.14:
			_lightning_flash = flash_intensity * 0.16
		elif strike_time < 0.24:
			_lightning_flash = flash_intensity * 0.62
		elif strike_time < 0.52:
			_lightning_flash = (
				flash_intensity
				* 0.62
				* (1.0 - smoothstep(0.24, 0.52, strike_time))
			)
		else:
			_lightning_flash = 0.0
			_lightning_strike_elapsed = -1.0
	_lightning_wait -= maxf(delta, 0.0)
	if _lightning_wait <= 0.0:
		_lightning_flash = flash_intensity
		_lightning_strike_elapsed = 0.0
		_lightning_wait = _rng.randf_range(3.2, 6.5)


func _update_snowfall(state: Dictionary) -> void:
	if _snow_particles == null or _snow_particle_material == null:
		return
	var snow := float(state.get("snow", 0.0))
	var wind := float(state.get("wind", 0.0))
	_snow_particles.amount_ratio = clampf(snow, 0.0, 1.0)
	_snow_particles.emitting = snow > 0.01
	_snow_particles.modulate.a = clampf(snow, 0.0, 1.0)
	_snow_particle_material.direction = Vector3(
		wind * 0.62,
		1.0,
		0.0,
	).normalized()
	_snow_particle_material.gravity = Vector3(wind * 3.5, 0.8, 0.0)


func get_lightning_flash() -> float:
	return _lightning_flash


func get_effect_activity_snapshot() -> Dictionary:
	return {
		"weatherOverlay": _overlay.visible,
		"water": _water_overlay.visible,
		"groundWeather": _surface_overlay.visible,
		"directionalShadow": _directional_shadow_overlay.visible,
		"windowEmissive": _window_emissive_overlay.visible,
		"windowEmissiveZIndex": _window_emissive_overlay.z_index,
		"windowGroundProjection": _window_ground_projection.visible,
		"windowGroundProjectionZIndex": _window_ground_projection.z_index,
		"localLights": _light_root.visible,
		"snow": _snow_root.visible,
	}


func _sync_zero_contribution_layers(state: Dictionary) -> void:
	var cloud := float(state.get("cloud", 0.0))
	var rain := float(state.get("rain", 0.0))
	var snow := float(state.get("snow", 0.0))
	var wetness := float(state.get("wetness", 0.0))
	var rain_impact := float(state.get("rainImpact", 0.0))
	var night := float(state.get("nightFactor", 0.0))
	var weather_overlay_active := (
		cloud > ZERO_CONTRIBUTION_EPSILON
		or rain > ZERO_CONTRIBUTION_EPSILON
		or _lightning_flash > ZERO_CONTRIBUTION_EPSILON
	)
	var ground_weather_active := (
		wetness > ZERO_CONTRIBUTION_EPSILON
		or rain_impact > ZERO_CONTRIBUTION_EPSILON
	)
	var window_light_active := (
		night > ZERO_CONTRIBUTION_EPSILON
		and _window_light_region_count > 0
	)
	var light_strength := clampf(
		night + cloud * 0.24,
		0.0,
		1.0,
	)
	_overlay.visible = weather_overlay_active
	_surface_overlay.visible = ground_weather_active
	_window_emissive_overlay.visible = window_light_active
	_window_ground_projection.visible = window_light_active
	_light_root.visible = light_strength > ZERO_CONTRIBUTION_EPSILON
	_snow_root.visible = snow > ZERO_CONTRIBUTION_EPSILON


func _update_directional_shadow(state: Dictionary) -> void:
	if _directional_shadow_material.shader == null:
		return
	var minute := float(state.get("minuteOfDay", 720))
	var night := float(state.get("nightFactor", 0.0))
	var cloud := float(state.get("cloud", 0.0))
	var wind := float(state.get("wind", 0.0))
	var day_phase := clampf((minute - 360.0) / 720.0, 0.0, 1.0)
	var solar_height := sin(day_phase * PI)
	var day_offset := Vector2(
		lerpf(-54.0, 54.0, day_phase),
		lerpf(42.0, 15.0, maxf(solar_height, 0.0)),
	)
	var moon_phase := (
		(minute - 1260.0) / 480.0
		if minute >= 1260.0
		else (minute + 180.0) / 480.0
	)
	moon_phase = clampf(moon_phase, 0.0, 1.0)
	var moon_offset := Vector2(
		lerpf(38.0, -38.0, moon_phase),
		lerpf(34.0, 20.0, sin(moon_phase * PI)),
	)
	var shadow_offset := day_offset.lerp(moon_offset, night)
	var day_strength := (1.0 - night) * 0.29 * (1.0 - cloud * 0.82)
	var moon_strength := night * 0.17 * (1.0 - cloud * 0.68)
	var shadow_tint := Color(0.19, 0.14, 0.11).lerp(
		Color(0.10, 0.15, 0.27),
		night,
	)
	_directional_shadow_material.set_shader_parameter("elapsed", _elapsed)
	_directional_shadow_material.set_shader_parameter("shadow_offset_px", shadow_offset)
	_directional_shadow_material.set_shader_parameter(
		"shadow_strength",
		day_strength + moon_strength,
	)
	_directional_shadow_material.set_shader_parameter(
		"cloud_shadow",
		float(state.get("cloudShadow", 0.0)),
	)
	_directional_shadow_material.set_shader_parameter("wind", wind)
	_directional_shadow_material.set_shader_parameter(
		"shadow_color",
		Vector3(shadow_tint.r, shadow_tint.g, shadow_tint.b),
	)


func _update_local_effects(state: Dictionary, delta: float) -> void:
	var night := float(state.get("nightFactor", 0.0))
	var cloud := float(state.get("cloud", 0.0))
	var wind := float(state.get("wind", 0.0))
	var light_strength := clampf(night + cloud * 0.24, 0.0, 1.0)
	if light_strength > ZERO_CONTRIBUTION_EPSILON:
		for index in _lights.size():
			var flicker := (
				0.98
				+ sin(_elapsed * 3.7 + float(index) * 1.41) * 0.02
			)
			_lights[index].energy = (
				_light_base_energy[index]
				* light_strength
				* flicker
			)
	for index in _smoke_materials.size():
		var material := _smoke_materials[index]
		material.direction = Vector3(wind * 0.48, -1.0, 0.0).normalized()
		material.gravity = Vector3(wind * 8.0, -1.0, 0.0)
		var occupied := int(_occupied_spaces.get(_smoke_space_ids[index], 0)) > 0
		var target := 1.0 if occupied else 0.0
		var fade_seconds := SMOKE_FADE_IN_SECONDS if occupied else SMOKE_FADE_OUT_SECONDS
		_smoke_activity[index] = move_toward(
			_smoke_activity[index],
			target,
			maxf(delta, 0.0) / fade_seconds,
		)
		var smoke := _smoke_particles[index]
		smoke.amount_ratio = _smoke_activity[index]
		if occupied and not smoke.emitting:
			smoke.emitting = true
			smoke.restart()
		elif not occupied and is_zero_approx(_smoke_activity[index]):
			smoke.emitting = false


func _vector2(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _load_window_facade_regions() -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	var hints_value: Variant = _config.get("windowFacadeHints", [])
	if not hints_value is Array:
		return regions
	for hint_value: Variant in hints_value as Array:
		if not hint_value is Dictionary:
			continue
		var hint := hint_value as Dictionary
		var hint_id := String(hint.get("id", "")).strip_edges()
		var space_id := String(
			WINDOW_FACADE_SPACE_IDS.get(
				hint_id,
				hint_id if hint_id.begins_with("home_") else "",
			)
		).strip_edges()
		var door_value: Variant = hint.get("door")
		if (
			space_id.is_empty()
			or not _formal_space_ids.has(space_id)
			or not door_value is Array
			or (door_value as Array).size() < 2
		):
			continue
		var door := door_value as Array
		var half_width := float(hint.get("halfWidth", 0.0))
		var top_offset := float(hint.get("topOffset", 0.0))
		var bottom_offset := float(hint.get("bottomOffset", 0.0))
		if half_width <= 0.0 or top_offset <= 0.0 or bottom_offset < 0.0:
			continue
		var door_position := Vector2(float(door[0]), float(door[1]))
		regions.append({
			"spaceId": space_id,
			"rect": Rect2(
				door_position.x - half_width,
				door_position.y - top_offset,
				half_width * 2.0,
				top_offset + bottom_offset,
			),
		})
	return regions


func _sync_window_light_regions() -> void:
	if (
		_window_emissive_material.shader == null
		or _window_ground_projection_material.shader == null
	):
		return
	var regions := PackedVector4Array()
	for _index in WINDOW_FACADE_REGION_CAPACITY:
		regions.append(Vector4(-1.0, -1.0, -1.0, -1.0))
	var active_count := 0
	for facade_value: Variant in _window_facade_regions:
		if active_count >= WINDOW_FACADE_REGION_CAPACITY:
			break
		var facade := facade_value as Dictionary
		var space_id := String(facade.get("spaceId", ""))
		if int(_occupied_spaces.get(space_id, 0)) <= 0:
			continue
		var rect_value: Variant = facade.get("rect")
		if not rect_value is Rect2:
			continue
		var rect := rect_value as Rect2
		regions[active_count] = Vector4(
			rect.position.x,
			rect.position.y,
			rect.end.x,
			rect.end.y,
		)
		active_count += 1
	_window_light_region_count = active_count
	_window_emissive_material.set_shader_parameter("light_regions", regions)
	_window_emissive_material.set_shader_parameter("light_region_count", active_count)
	_window_ground_projection_material.set_shader_parameter("light_regions", regions)
	_window_ground_projection_material.set_shader_parameter(
		"light_region_count",
		active_count,
	)
	var window_light_active := (
		_window_light_region_count > 0
		and float(_last_visual_state.get("nightFactor", 0.0))
			> ZERO_CONTRIBUTION_EPSILON
	)
	_window_emissive_overlay.visible = window_light_active
	_window_ground_projection.visible = window_light_active


func _load_formal_space_ids() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(FORMAL_SPACES_PATH),
	)
	if not parsed is Dictionary:
		return {}
	var spaces_value: Variant = (parsed as Dictionary).get("spaces")
	if not spaces_value is Array:
		return {}
	var formal_space_ids: Dictionary = {}
	for space_value: Variant in spaces_value as Array:
		if not space_value is Dictionary:
			return {}
		var space_id_value: Variant = (space_value as Dictionary).get("id")
		if not space_id_value is String:
			return {}
		var space_id := String(space_id_value)
		if (
			not _is_canonical_identifier(space_id)
			or formal_space_ids.has(space_id)
		):
			return {}
		formal_space_ids[space_id] = true
	return formal_space_ids


static func weather_style_for_accessibility(configured_value: Variant) -> Dictionary:
	if not configured_value is Dictionary:
		return {}
	var configured_style := configured_value as Dictionary
	var lightning_value: Variant = configured_style.get("lightning", 0.0)
	if not _is_finite_number(lightning_value):
		return {}
	var style := configured_style.duplicate(true)
	if bool(ProjectSettings.get_setting(REDUCED_FLASHING_SETTING, false)):
		# 雷暴的暗色、云雨和声音仍由各自的正式表现 owner 保留；这里只关闭
		# 高亮双脉冲，保留一次较弱、较慢的环境亮度变化。
		style["lightning"] = float(style.get("lightning", 0.0)) * 0.28
		style["reducedLightning"] = true
	return style


func _validated_visual_input(
	time_value: Variant,
	weather_value: Variant,
) -> Dictionary:
	if not time_value is Dictionary or not weather_value is String:
		return {}
	var time := time_value as Dictionary
	var clock_value: Variant = time.get("clock")
	if not clock_value is String:
		return {}
	var minute_of_day := _clock_minute(String(clock_value))
	if minute_of_day < 0:
		return {}
	var weather := String(weather_value)
	var weather_config := _config.get("weather", {}) as Dictionary
	if not weather_config.has(weather):
		return {}
	return {
		"time": time,
		"weather": weather,
		"minuteOfDay": minute_of_day,
	}


func _clock_minute(clock: String) -> int:
	if clock.length() != 5 or clock[2] != ":":
		return -1
	for index in [0, 1, 3, 4]:
		var code := clock.unicode_at(index)
		if code < 48 or code > 57:
			return -1
	var hour := int(clock.substr(0, 2))
	var minute := int(clock.substr(3, 2))
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return -1
	return hour * 60 + minute


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return is_finite(float(value))


static func _is_canonical_identifier(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if (
			(code < 97 or code > 122)
			and (code < 48 or code > 57)
			and code != 95
		):
			return false
	return true
