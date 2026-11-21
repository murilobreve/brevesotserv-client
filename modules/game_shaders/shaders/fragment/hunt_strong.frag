// Hunt Board - a very strong monster (experience rate 4x or more: it has
// more health and hits harder): the monster on fire. It keeps its own
// colours, only warmer and darker in the shadows (the first version washed
// it all into one flat red), and tongues of flame climb over it, red at the
// root, orange, then yellow at the tip, with a slow glow underneath.
// The flames are drawn in screen space (gl_FragCoord), not in v_TexCoord:
// the sprite sheet's coordinates change with every animation frame, and the
// fire would jump as the monster walks. Set by the client itself
// (game_huntboard, Creature::setStrongShader); a rare tier's shader always
// comes before it.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    float l = dot(col.rgb, vec3(0.299, 0.587, 0.114));

    // the monster itself: its colours, warmer, with deeper shadows
    vec3 base = col.rgb * vec3(1.18, 0.88, 0.72);
    base = mix(base, vec3(0.34, 0.05, 0.02), 0.30 * (1.0 - smoothstep(0.0, 0.5, l)));

    // flames climbing: two layers of noise moving up at different speeds,
    // squeezed sideways so they read as tongues
    vec2 p = gl_FragCoord.xy;
    float n = noise(vec2(p.x * 0.085, p.y * 0.045 - u_Time * 2.6));
    n += 0.5 * noise(vec2(p.x * 0.19 + 7.0, p.y * 0.10 - u_Time * 4.1));
    n /= 1.5;
    float flame = smoothstep(0.50, 0.82, n);
    float core = smoothstep(0.70, 0.92, n);

    vec3 fire = mix(vec3(0.86, 0.13, 0.02), vec3(1.0, 0.50, 0.05), flame);
    fire = mix(fire, vec3(1.0, 0.90, 0.38), core);

    // a slow glow, so the monster is never plain between two tongues
    float glow = 0.5 + 0.5 * sin(u_Time * 3.0);
    vec3 result = mix(base, fire, flame * 0.72);
    result += vec3(0.20, 0.06, 0.0) * (0.35 + 0.65 * glow) * smoothstep(0.15, 0.8, l);

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
