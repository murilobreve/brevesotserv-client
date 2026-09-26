// Baiak Rarity System - item rarity tint: Rare (blue).
// hue-rotate(210deg) - see rarity_uncommon.frag for context.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
  vec4 col = texture2D(u_Tex0, v_TexCoord);
  vec3 c = col.rgb;
  vec3 r;
  r.r = -0.362 * c.r + 1.692 * c.g - 0.330 * c.b;
  r.g = 0.326 * c.r + 0.398 * c.g + 0.276 * c.b;
  r.b = 0.791 * c.r + 0.977 * c.g - 0.768 * c.b;
  gl_FragColor = vec4(clamp(r, 0.0, 1.0), col.a);
}
