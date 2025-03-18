# shaders

Outdated! Rewrite sometime soon.

Pre-compiled versions of shaders. These shaders will be used as a template for the `style_compiler` to generate the final shaders for a given style.

Paint properties are added to the shaders as follows:
- `constant` - a constant value, baked into the shader.
- `data-constant` - a value that's not dependent on the feature data. passed into the shader as a uniform.
- `color-ramp` - TODO
- `cross-faded-data-driven` - value is data-driven, but the shader will interpolate between two values based on the zoom level. shader will receive the two values as vertex attributes.
- `cross-faded` - value is not data-driven, but the shader will interpolate between two values based on the zoom level.  shader will receive the two values as uniforms.
- `data-driven` - value is data driven. depending on whether it uses zoom or not, two things can happen:
  - if it uses zoom (and subsequently an interpolation above it), the shader will receive the interpolation values (for the two nearest zoom levels) as vertex attributes, and the interpolation code is baked into the shader (since the stops are constant).
  - if it doesn't use zoom, the shader will receive the final value as a vertex attribute.

Various pragmas are used in the shaders to allow the usage of data-driven properties in the shaders (and some other things):

- `#pragma prelude` - insert the `_prelude.glsl` file
- `#pragma prelude(x)` - insert the `_prelude_x.glsl` file
