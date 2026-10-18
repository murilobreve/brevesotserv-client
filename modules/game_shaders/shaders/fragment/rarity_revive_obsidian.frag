// Rarity revive - Obsidian, waking: the corpse crystallises into volcanic
// glass. Black facets with violet depth, a glint that sweeps across the
// edges, and violet light leaking from the seams between the facets.
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

    // facets: the body cut into flat cells of glass
    vec2 cellId = floor(fc / 9.0);
    float facet = hash(cellId);
    vec3 glass = mix(vec3(0.06, 0.03, 0.10), vec3(0.42, 0.20, 0.70), facet * 0.6 + lum * 0.5);
    vec3 result = mix(col.rgb, glass, 0.82);

    // the seams between facets glow violet, slowly
    vec2 inCell = fract(fc / 9.0);
    float seam = 1.0 - smoothstep(0.0, 0.12, min(min(inCell.x, 1.0 - inCell.x), min(inCell.y, 1.0 - inCell.y)));
    float glowPulse = 0.5 + 0.5 * sin(u_Time * 2.5 + facet * 6.0);
    result = mix(result, vec3(0.70, 0.40, 1.0), seam * 0.55 * glowPulse);

    // a glint sweeping diagonally across the glass
    float sweep = fract((fc.x + fc.y) * 0.004 - u_Time * 0.45);
    float glint = 1.0 - smoothstep(0.0, 0.035, abs(sweep - 0.5));
    result = mix(result, vec3(0.95, 0.90, 1.0), glint * (0.4 + 0.6 * facet));

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
