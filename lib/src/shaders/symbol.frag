#version 460 core

#pragma prelude: interpolation
#pragma prelude: tile

in highp vec2 v_uv;

#pragma prop: declare(sampler2D glyph_sdf_texture)
#pragma prop: declare(highp vec4 color)
#pragma prop: declare(float opacity)

out highp vec4 f_color;

const float inner_edge = 0.75;
const float smoothing = 1.0 / 16.0;

void main() {
  #pragma prop: resolve(...)
  
  float dist = texture(glyph_sdf_texture, v_uv).r;
  float alpha = smoothstep(inner_edge - smoothing, inner_edge + smoothing, dist);

  f_color = vec4(1.0, 0.0, 0.0, 1.0) * alpha;
}
