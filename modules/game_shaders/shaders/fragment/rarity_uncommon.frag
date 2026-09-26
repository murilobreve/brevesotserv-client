// Baiak Rarity System - item rarity tint: Uncommon (green).
// Colors the item by its rarity grade. A plain hue rotation (the previous
// version) left grey/steel items - most weapons and armor - almost
// unchanged, so the item is now tinted by luminance instead, which works on
// any sprite, plus a slow sheen. The sheen is computed in screen space
// (gl_FragCoord): v_TexCoord points into the shared sprite atlas, so any
// pattern built from it jumps whenever the sprite changes.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
  vec4 col = texture2D(u_Tex0, v_TexCoord);
  vec3 c = col.rgb;
  float lum = dot(c, vec3(0.299, 0.587, 0.114));

  vec3 tint = vec3(0.30, 1.00, 0.30);
  vec3 tinted = tint * (lum * 1.35 + 0.06);
  vec3 result = mix(c, tinted, 0.55);

  float wave = sin((gl_FragCoord.x + gl_FragCoord.y) * 0.05 - u_Time * 1.6);
  float sheen = smoothstep(0.90, 1.0, wave) * smoothstep(0.15, 0.6, lum);
  result += tint * sheen * 0.20;

  gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
