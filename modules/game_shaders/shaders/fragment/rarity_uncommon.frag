// Baiak Rarity System - item rarity tint: Uncommon (green).
// hue-rotate(110deg) - see rarity_pale.frag (monster tiers) for the general
// approach; this file and its 4 siblings tint by the ITEM's own rarity
// grade instead, assigned server-side in scripts/rarity/loot.lua via
// item:setShader(RarityConfig.rarityShaders[rarity.key]).
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
  vec4 col = texture2D(u_Tex0, v_TexCoord);
  vec3 c = col.rgb;
  vec3 r;
  r.r = -0.256 * c.r + 0.288 * c.g + 0.969 * c.b;
  r.g = 0.420 * c.r + 0.749 * c.g - 0.169 * c.b;
  r.b = -0.454 * c.r + 1.631 * c.g - 0.178 * c.b;
  gl_FragColor = vec4(clamp(r, 0.0, 1.0), col.a);
}
