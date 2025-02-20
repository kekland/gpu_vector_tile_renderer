#version 320 es
#define data_crossfade(a, b) mix(a, b, camera.zoom - floor(camera.zoom))

#define data_step(start_value, end_value, start_stop, end_stop) \
  mix(start_value, end_value, step(end_stop, camera.zoom))

#define data_interpolate(start_value, end_value, start_stop, end_stop) \
  mix(start_value, end_value, data_interpolate_factor(1.0, start_stop, end_stop, camera.zoom))

#define data_interpolate_exponential(base, start_value, end_value, start_stop, end_stop) \
  mix(start_value, end_value, data_interpolate_factor(base, start_stop, end_stop, camera.zoom))

float data_interpolate_factor(
  float base,
  float start_stop,
  float end_stop,
  float t
) {
  float difference = end_stop - start_stop;
  float progress = t - start_stop;

  if (difference == 0.0) return 0.0;
  else if (base == 1.0) return progress / difference;
  else return (pow(base, progress) - 1.0) / (pow(base, difference) - 1.0);
}

uniform RoadUnderConstructionUbo {
  float width_start_stop;
  float width_end_stop;
} road_under_construction_ubo;


precision highp float;

uniform Tile {
  highp mat4 local_to_world;
  highp float size;
  highp float extent;
  highp float opacity;
} tile;


uniform Camera {
  highp mat4 world_to_gl;
  highp float zoom;
} camera;


vec4 project_tile_position(vec2 position) {
  return camera.world_to_gl * tile.local_to_world * (vec4(position * (tile.size / tile.extent), 0.0, 1.0));
}


in highp vec4 v_color;
const float opacity = 1;
in float v_width;

out highp vec4 f_color;

void main() {
highp vec4 color = v_color;
float width = v_width;
  f_color = color * (opacity * tile.opacity);
}


