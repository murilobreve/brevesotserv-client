// Rarity revive - Pale, waking: the corpse turns into a ghost of itself. It
// goes cold and pale, fades in and out like a spirit that cannot hold its
// shape, and white mist climbs through it. Everything stays on the body's
// own pixels: the empty pixels around a sprite hold whatever the client's
// texture cache left there, and painting them showed as a rectangle of
// garbage over the floor.
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
    vec2 fc = gl_FragCoord.xy;
    float lum = luma(col.rgb);

    // cold, drained body
    vec3 body = mix(col.rgb, vec3(0.80, 0.86, 0.95) * (0.55 + lum), 0.70);
    // it breathes in and out of sight
    float fade = 0.55 + 0.35 * (0.5 + 0.5 * sin(u_Time * 2.2)) + 0.10 * noise(fc * 0.05 + u_Time);
    vec4 result = vec4(body, col.a * fade);

    // mist rising through the body
    float mist = noise(vec2(fc.x * 0.045, fc.y * 0.030 - u_Time * 1.6));
    mist *= noise(vec2(fc.x * 0.09 + 3.0, fc.y * 0.06 - u_Time * 2.4));
    float wisp = smoothstep(0.30, 0.62, mist);
    result.rgb = mix(result.rgb, vec3(0.95, 0.97, 1.0), wisp * 0.6 * result.a);

    gl_FragColor = vec4(clamp(result.rgb, 0.0, 1.0), clamp(result.a, 0.0, 1.0));
}
