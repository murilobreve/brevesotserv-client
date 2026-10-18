// Rarity revive - Obsidian, rising: the glass is about to shatter. The
// facets flash violet one by one and the seams burn bright.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    // the facets are cut at a slant, like broken glass, not on a square grid
    vec2 fc = mat2(0.82, 0.57, -0.57, 0.82) * gl_FragCoord.xy * vec2(1.0, 1.6);
    float lum = luma(col.rgb);
    vec2 cellId = floor(fc / 9.0);
    float facet = hash(cellId);
    float flash = step(0.55, fract(facet * 7.0 + u_Time * 3.0));
    vec3 glass = mix(vec3(0.08, 0.04, 0.12), vec3(0.75, 0.45, 1.0), flash * 0.8 + lum * 0.3);
    vec3 result = mix(col.rgb, glass, 0.80);
    vec2 inCell = fract(fc / 9.0);
    float seam = 1.0 - smoothstep(0.0, 0.18, min(min(inCell.x, 1.0 - inCell.x), min(inCell.y, 1.0 - inCell.y)));
    result = mix(result, vec3(0.85, 0.60, 1.0), seam * 0.8);
    float rim = step(0.01, col.a) * (1.0 - smoothstep(0.0, 0.7, col.a));
    result += vec3(0.7, 0.4, 1.0) * rim;
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
