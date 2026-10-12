// Rarity item tint - Mythicus (living pearl and opal)
// The item turns a bright pearl while its dark lines and a trace of its own
// colour stay, so it is still recognisable. Over it:
//  - the whole surface plays like mother of pearl, its hue drifting with
//    brightness and time
//  - a band of light crosses it with prismatic, rainbow edges
//  - a quick white glint every few seconds
//  - four point stars that flare and fade
//  - a double heartbeat of light now and then
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

const vec3 PEARL = vec3(0.945, 0.937, 1.000);

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// full colour of hue h (0..1)
vec3 hue(float h)
{
    return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

// soft pastel of hue h, for the opal play of colour
vec3 opal(float h)
{
    return mix(vec3(1.0), hue(h), 0.42);
}

float rand(vec2 p)
{
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float lum = luma(c);
    vec2 p = gl_FragCoord.xy;

    // pearl body: most of the colour drains, the light parts go white
    vec3 result = mix(c, vec3(lum), 0.55);
    float bright = smoothstep(0.10, 0.80, lum);
    result = mix(result, PEARL, bright * 0.70);
    // dark lines stay dark: the item's drawing
    float dark = 1.0 - smoothstep(0.06, 0.26, lum);
    result = mix(result, c * 0.80, dark * 0.75);

    // living opal: like mother of pearl, several soft hues at once across
    // the item (by brightness and place), slowly drifting
    float film = fract(lum * 2.6 + (p.x - p.y) * 0.035 + u_Time * 0.05);
    result = mix(result, result * opal(film) * 1.06, smoothstep(0.20, 0.70, lum) * 0.38);

    // prism band: white in the middle, a full rainbow spread across its
    // edges (narrow enough that the item never turns one colour)
    float across = (p.x * 0.80 + p.y) * 0.060 - u_Time * 2.4;
    float wave = sin(across);
    float core = smoothstep(0.90, 1.0, wave);
    float edge = smoothstep(0.62, 0.90, wave) * (1.0 - core);
    float lit = smoothstep(0.08, 0.60, lum);
    result = mix(result, vec3(1.0), core * lit * 0.70);
    float spectrum = fract((wave - 0.62) / 0.28 * 0.85 + (p.x - p.y) * 0.01);
    result = mix(result, mix(vec3(1.0), hue(spectrum), 0.70), edge * lit * 0.40);

    // a second, slower pearl reflection the other way
    float wave2 = sin(p.x * 0.036 - p.y * 0.054 - u_Time * 1.3);
    result = mix(result, vec3(1.0), smoothstep(0.86, 1.0, wave2) * smoothstep(0.25, 0.80, lum) * 0.35);

    // quick thin glint every few seconds
    float glint = sin((p.x + p.y) * 0.090 - u_Time * 4.2);
    result = mix(result, vec3(1.0), smoothstep(0.985, 1.0, glint) * smoothstep(0.10, 0.50, lum) * 0.90);

    // four point stars: one may live in each 9x9 pixel cell
    vec2 cell = floor(p / 9.0);
    float seed = rand(cell);
    if (seed > 0.86) {
        vec2 centre = cell * 9.0 + 4.5 + (vec2(rand(cell + 1.7), rand(cell + 3.1)) - 0.5) * 3.0;
        vec2 d = abs(p - centre);
        float flare = pow(max(0.0, sin(u_Time * 2.2 + seed * 40.0)), 10.0);
        float arms = max((1.0 - smoothstep(0.0, 4.5, d.x)) * (1.0 - smoothstep(0.4, 1.1, d.y)),
                         (1.0 - smoothstep(0.0, 4.5, d.y)) * (1.0 - smoothstep(0.4, 1.1, d.x)));
        float glow = 1.0 - smoothstep(0.0, 2.0, length(d));
        float star = clamp(max(arms, glow), 0.0, 1.0) * flare * smoothstep(0.08, 0.40, lum);
        result = mix(result, mix(vec3(1.0), opal(seed * 3.0), 0.45), star);
    }

    // heartbeat: two quick pulses of light every 3.2 seconds
    float beat = mod(u_Time, 3.2);
    float pulse = exp(-pow((beat - 0.25) * 9.0, 2.0)) + 0.7 * exp(-pow((beat - 0.60) * 9.0, 2.0));
    result += vec3(0.95, 0.93, 1.0) * 0.16 * pulse * bright;

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
