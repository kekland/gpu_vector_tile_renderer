#version 460 core

#pragma prelude: interpolation
#pragma prelude: tile

in highp vec2 position;
in highp vec2 anchor;
in highp vec2 uv;

out highp vec2 v_uv;

#pragma prop: declare(sampler2D glyph_sdf_texture)
#pragma prop: declare(highp vec4 color)
#pragma prop: declare(float opacity)

void main() {
  #pragma prop: resolve(...)

  v_uv = uv;
  
  float scale = tile.extent / tile.size;
  gl_Position = project_tile_position((position * scale) + anchor);
}
