#version 460 core

#pragma prelude: interpolation
#pragma prelude: tile

in highp vec2 v_uv;

#pragma prop: declare(sampler2D glyph_sdf_texture)
#pragma prop: declare(highp vec4 color)
#pragma prop: declare(float opacity)

out highp vec4 f_color;

void main() {
  #pragma prop: resolve(...)
  
  // Sample the glyph texture
  float dist = texture(glyph_sdf_texture, v_uv).r;
  if (dist < 0.75) discard;

  f_color = vec4(color.rgb, color.a * opacity);
}
