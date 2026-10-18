// Rarity revive - Pale, waking: the corpse of a monster that is about to come
// back as Pale. It takes the tier's colour and beats like a heart, twice
// every 1.4 s, while bands of light climb up through it. Set on the corpse by
// the server (scripts/rarity/revive.lua) for the first seconds of the revive.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

const vec3 TINT = vec3(0.86, 0.88, 0.92);
const vec3 GLOW = vec3(0.95, 0.97, 1.00);

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float lum = dot(c, vec3(0.299, 0.587, 0.114));

    // the tier's colour at the corpse's own light and shade
    vec3 result = mix(c, TINT * (0.45 + lum), 0.60);

    // heartbeat: a strong beat and a softer one
    float t = mod(u_Time, 1.4);
    float beat = exp(-pow((t - 0.10) * 14.0, 2.0)) + 0.65 * exp(-pow((t - 0.40) * 14.0, 2.0));

    // light climbing up the body (screen space, so it does not jump between
    // sprite frames)
    float band = smoothstep(0.80, 1.0, sin(gl_FragCoord.y * 0.11 - u_Time * 5.0));

    float body = smoothstep(0.02, 0.45, lum + 0.15);
    result += GLOW * (0.55 * beat + 0.30 * band) * body;

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
