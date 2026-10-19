// Rarity revive - Pale, rising: the ghost pulls itself together. Strong
// white flashes, the shape shivering, a glowing outline.
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
    // no texture-coordinate shake: the sprite sits in a shared atlas and a
    // shifted lookup reads the pixels of its neighbours; it shivers in light
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    float lum = luma(col.rgb);
    float shiver = 0.5 + 0.5 * sin(u_Time * 40.0 + gl_FragCoord.y * 0.3);
    float flash = (0.5 + 0.5 * sin(u_Time * 18.0)) * (0.8 + 0.2 * shiver);
    vec3 body = mix(col.rgb, vec3(0.96, 0.98, 1.0), 0.35 + 0.45 * flash * smoothstep(0.05, 0.6, lum + 0.2));
    float alpha = col.a * (0.75 + 0.25 * flash);
    float rim = step(0.01, col.a) * (1.0 - smoothstep(0.0, 0.7, col.a));
    body += vec3(0.9, 0.95, 1.0) * rim;
    gl_FragColor = vec4(clamp(body, 0.0, 1.0), alpha);
}
