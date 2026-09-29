#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace {
  float hash(float2 cell, float seed) {
    float3 p = fract(float3(cell.x, cell.y, cell.x + seed) * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
  }

  float ease(float value) {
    return value * value * (3.0 - 2.0 * value);
  }

  // Maps a coordinate so that `pivot` lands on the middle row or column of the 3x3 mesh.
  float meshCoordinate(float value, float pivot) {
    return value < pivot
      ? 0.5 * value / max(pivot, 0.0001)
      : 0.5 + 0.5 * (value - pivot) / max(1.0 - pivot, 0.0001);
  }

  float3 meshColor(float2 uv, float2 center, float3 base, float3 primary, float3 secondary) {
    // Column colors follow the mesh layout: primary, base, secondary; the bottom row ends in
    // secondary twice.
    float3 grid[3][3] = {
      { primary, base, secondary },
      { primary, base, secondary },
      { primary, secondary, secondary },
    };
    float rowPivot = uv.y < 0.5 ? mix(0.54, center.x, uv.y * 2.0) : mix(center.x, 0.42, uv.y * 2.0 - 1.0);
    float columnPivot = uv.x < 0.5 ? mix(0.48, center.y, uv.x * 2.0) : mix(center.y, 0.55, uv.x * 2.0 - 1.0);
    float2 gridPosition = float2(meshCoordinate(uv.x, rowPivot), meshCoordinate(uv.y, columnPivot)) * 2.0;
    int2 cell = int2(min(floor(gridPosition), float2(1.0)));
    float2 local = float2(ease(gridPosition.x - cell.x), ease(gridPosition.y - cell.y));
    float3 top = mix(grid[cell.y][cell.x], grid[cell.y][cell.x + 1], local.x);
    float3 bottom = mix(grid[cell.y + 1][cell.x], grid[cell.y + 1][cell.x + 1], local.x);
    return mix(top, bottom, local.y);
  }

  float radialAlpha(float distance, float startRadius, float endRadius, float inner, float middle) {
    float t = clamp((distance - startRadius) / (endRadius - startRadius), 0.0, 1.0);
    return t < 0.5 ? mix(inner, middle, t * 2.0) : mix(middle, 0.0, t * 2.0 - 1.0);
  }
}

/// A receipt's ink-wash backdrop in one pass: a 3x3 mesh, two drifting color washes, a corner
/// highlight and bloom, a bottom vignette, and film grain.
[[ stitchable ]] half4 receiptInkWash(
  float2 position,
  half4 unused,
  float2 size,
  half4 baseColor,
  half4 primaryColor,
  half4 secondaryColor,
  half4 highlightColor,
  half4 bloomColor,
  float2 meshCenter,
  float2 leadingCenter,
  float2 trailingCenter,
  float4 washOpacities,
  float2 highlightCenter,
  float2 bloomCenter,
  float2 glowOpacities,
  float vignette,
  float isDark,
  float grainSeed
) {
  float2 uv = position / max(size, float2(1.0));
  float3 base = float3(baseColor.rgb);
  float3 primary = float3(primaryColor.rgb);
  float3 secondary = float3(secondaryColor.rgb);

  float3 color = meshColor(uv, meshCenter, base, primary, secondary);

  float leading = radialAlpha(distance(position, leadingCenter * size), 20.0, 900.0, washOpacities.x, washOpacities.y);
  color = mix(color, primary, leading);
  float trailing = radialAlpha(distance(position, trailingCenter * size), 20.0, 900.0, washOpacities.z, washOpacities.w);
  color = mix(color, secondary, trailing);

  float highlightT = clamp((distance(position, highlightCenter * size) - 10.0) / 420.0, 0.0, 1.0);
  color = mix(color, float3(highlightColor.rgb), glowOpacities.x * (1.0 - highlightT));
  float bloomT = clamp(distance(position, bloomCenter * size) / 360.0, 0.0, 1.0);
  color = mix(color, float3(bloomColor.rgb), glowOpacities.y * (1.0 - bloomT));

  float shade = clamp((uv.y - 0.48) / 0.52, 0.0, 1.0);
  color = mix(color, float3(0.0), vignette * shade);

  float2 cell = floor(position);
  float grain = hash(cell, grainSeed);
  if (grain < 0.012) {
    float strength = grain < 0.0024 ? 0.12 : 0.075;
    float3 lifted = isDark > 0.5 ? sqrt(max(color, 0.0)) : color * color;
    color = mix(color, lifted, strength);
  }

  return half4(half3(color), 1.0h);
}
