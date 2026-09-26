// Baiak Rarity System - item rarity tint: Epic (purple).
// hue-rotate(280deg) - see rarity_uncommon.frag for context.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
  vec4 col = texture2D(u_Tex0, v_TexCoord);
  vec3 c = col.rgb;
  vec3 r;
  r.r = 0.559 * c.r + 1.295 * c.g - 0.855 * c.b;
  r.g = 0.035 * c.r + 0.627 * c.g + 0.338 * c.b;
  r.b = 0.951 * c.r - 0.113 * c.g + 0.162 * c.b;
  gl_FragColor = vec4(clamp(r, 0.0, 1.0), col.a);
}
