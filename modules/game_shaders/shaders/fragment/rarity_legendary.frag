// Baiak Rarity System - item rarity tint: Legendary (gold/orange).
// hue-rotate(35deg) - see rarity_uncommon.frag for context.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
  vec4 col = texture2D(u_Tex0, v_TexCoord);
  vec3 c = col.rgb;
  vec3 r;
  r.r = 0.736 * c.r - 0.281 * c.g + 0.545 * c.b;
  r.g = 0.121 * c.r + 1.029 * c.g - 0.149 * c.b;
  r.b = -0.413 * c.r + 0.539 * c.g + 0.874 * c.b;
  gl_FragColor = vec4(clamp(r, 0.0, 1.0), col.a);
}
