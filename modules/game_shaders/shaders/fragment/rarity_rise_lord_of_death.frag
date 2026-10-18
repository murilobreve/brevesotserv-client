// Rarity revive - Lord of Death, rising: the last moment before the monster stands up,
// on the corpse, and the first moment of the monster itself, made of light.
// Fast flicker towards the tier's glow; the server swaps it for the tier's
// own shader (rarity_lord_of_death.frag) once the monster is up.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

const vec3 TINT = vec3(0.18, 0.04, 0.06);
const vec3 GLOW = vec3(0.95, 0.15, 0.12);

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float lum = dot(c, vec3(0.299, 0.587, 0.114));

    vec3 tinted = mix(c, TINT * (0.45 + lum), 0.60);
    float flicker = 0.5 + 0.5 * sin(u_Time * 24.0);
    float surge = 0.5 + 0.5 * sin(u_Time * 7.0);
    float body = smoothstep(0.02, 0.45, lum + 0.15);
    vec3 result = mix(tinted, GLOW, (0.35 + 0.45 * flicker * surge) * body);

    // a bright rim where the sprite meets the background
    float edge = smoothstep(0.0, 0.6, 1.0 - col.a) * step(0.01, col.a);
    result += GLOW * edge;

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
