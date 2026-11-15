// Contorno: what a player wearing Mythicus items looks like. Inside the
// silhouette the outfit keeps its colours and takes the drawing its items
// carry (rarity_item.frag: embers, frost lattice, moss veins...) in the
// element's colour, with a reflection that crosses it every few seconds;
// round it runs a line of light with a glow past it. The server picks the
// variant (scripts/rarity/outline.lua); modules/game_shaders/shaders.lua
// builds one per grade and colour by defining:
//   GRADE   1 = a light drawing and the line; 2 = stronger, with the glow;
//           3 = stronger still, sparks, and the line flowing in two colours
//   ELEMENT 0 none, 1 fire, 2 earth, 3 energy, 4 ice, 5 holy, 6 death,
//           7 physical (as rarity_item.frag)
//   COLOR2  the second colour of GRADE 3
// It runs on the framebuffer the whole outfit is drawn to (useFramebuffer),
// so it sees the outfit with its colours and has room round it for the glow.
// Patterns use screen pixels, like the items'.
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
const float TAU = 6.28318530718;
float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float wave(float x) { return 0.5 + 0.5 * sin(x); }
float line(float x, float width) {
    return 1.0 - smoothstep(width, width + 0.10, abs(sin(x)));
}
float solid(vec2 px, float dx, float dy) {
    return step(0.5, texture2D(u_Tex0, v_TexCoord + vec2(dx, dy) * px).a);
}
// 1 when a solid pixel lies `r` steps away in one of eight directions
float near(vec2 px, float r) {
    float d = r * 0.7071;
    return max(max(max(solid(px, r, 0.0), solid(px, -r, 0.0)), max(solid(px, 0.0, r), solid(px, 0.0, -r))),
               max(max(solid(px, d, d), solid(px, -d, d)), max(solid(px, d, -d), solid(px, -d, -d))));
}
void main() {
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec2 p = gl_FragCoord.xy;
    // all temporal frequencies divide 600 seconds: the time wrap is continuous
    float t = mod(u_Time, 600.0);
    float phase = p.x * 0.061 + p.y * 0.097;
    float sweep = pow(wave((p.x + p.y * 0.65) * 0.22 - t * TAU / 5.0), 12.0);
    vec3 elementColor = vec3(0.910, 0.894, 1.0);
    float pattern = 0.0;
#if ELEMENT == 0
    // no element: the opal's slow veins
    elementColor = mix(vec3(0.910, 0.894, 1.0), 0.62 + 0.32 * cos(vec3(0.0, 2.1, 4.2) + phase + t * TAU / 12.0), 0.7);
    pattern = line(p.x * 0.49 + sin(p.y * 0.37) * 0.9, 0.12) * (0.5 + 0.5 * wave(t * TAU / 6.0 + phase));
#elif ELEMENT == 1
    // IGNEUS: staggered rising ember seams
    elementColor = vec3(1.0, 0.416, 0.165);
    pattern = pow(wave(p.y * 0.8 - t * TAU / 3.0 + sin(p.x * 0.7) * 2.0), 5.0) * (0.3 + 0.7 * wave(p.x * 1.1));
#elif ELEMENT == 2
    // TERRENUS: branching moss veins with a slow pulse
    elementColor = vec3(0.424, 0.820, 0.227);
    pattern = line(p.x * 0.55 + sin(p.y * 0.47) * 1.8, 0.20) * (0.55 + 0.45 * wave(t * TAU / 10.0 + phase));
#elif ELEMENT == 3
    // FULMINEUS: a zigzag conductor that charges now and then
    elementColor = vec3(0.710, 0.420, 1.0);
    float zig = abs(fract(p.y / 9.0) * 2.0 - 1.0) * 3.0;
    pattern = line(p.x * 0.55 + zig, 0.12) * (0.35 + 0.65 * pow(wave(t * TAU / 4.0 + phase * 0.4), 4.0));
#elif ELEMENT == 4
    // GLACIALIS: a frost lattice catching the light
    elementColor = vec3(0.322, 0.863, 1.0);
    pattern = max(line((p.x + p.y) * 0.62, 0.09), line((p.x - p.y) * 0.62, 0.09)) * (0.55 + 0.45 * wave(t * TAU / 12.0 + phase));
#elif ELEMENT == 5
    // SACER: long oblique shafts of light
    elementColor = vec3(1.0, 0.847, 0.290);
    pattern = pow(wave(p.x * 0.43 + p.y * 0.12 - t * TAU / 15.0), 6.0);
#elif ELEMENT == 6
    // MORTIFER: violet smoke
    elementColor = vec3(0.541, 0.239, 0.749);
    pattern = pow(wave(p.x * 0.29 + sin(p.y * 0.34 + t * TAU / 12.0) * 2.0 + t * TAU / 15.0), 3.0) * 0.8;
#elif ELEMENT == 7
    // CORPORALIS: steel grain and a cold reflection
    elementColor = vec3(0.722, 0.745, 0.776);
    pattern = line((p.x + p.y * 0.23) * 1.2, 0.16) * (0.40 + 0.60 * sweep);
#endif
    if (col.a > 0.5) {
        float l = lum(col.rgb);
        // dark cloth and armour still take a good part of the light
        float ink = 0.55 + 0.45 * smoothstep(0.08, 0.34, l);
        float hl = smoothstep(0.40, 0.90, l);
        float power = 0.40 + 0.20 * float(GRADE);
        vec3 c = col.rgb;
        c += (1.0 - c) * elementColor * pattern * power * ink;
        // the reflection: strongest on what already shines
        c += (1.0 - c) * mix(elementColor, vec3(1.0), 0.55) * sweep * (0.25 + 0.15 * float(GRADE)) * (0.45 + 0.55 * hl) * ink;
#if GRADE >= 3
        // sparks: a few pixels flare, each at its own pace
        vec2 cell = floor(p / 2.0);
        float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
        float spark = step(0.965, seed) * pow(wave(t * TAU / 3.0 + seed * 50.0), 8.0);
        c += (1.0 - c) * mix(COLOR2, vec3(1.0), 0.5) * spark;
#endif
        gl_FragColor = vec4(clamp(c, 0.0, 1.0), col.a);
        return;
    }
    vec2 px = abs(vec2(u_TextureMatrix[0][0], u_TextureMatrix[1][1]));
    float breath = 0.86 + 0.14 * sin(t * TAU / 4.0);
    vec3 tone = elementColor;
#if GRADE >= 3
    tone = mix(elementColor, COLOR2, 0.5 + 0.5 * sin((p.x - p.y) * 0.06 + t * TAU / 6.0));
#endif
    vec3 c = tone;
    float a = 0.0;
    // the nearest ring that touches the silhouette decides: the line, then
    // the glow fading outwards (no ring further out is read once one hits)
    if (near(px, 1.0) > 0.5) {
        c = mix(mix(tone, vec3(1.0), 0.5), vec3(1.0), sweep);
#if GRADE >= 2
        a = 0.95 * breath + 0.05;
#else
        a = 0.85;
#endif
    } else if (near(px, 2.0) > 0.5) {
#if GRADE >= 2
        a = 0.55 * breath;
#else
        a = 0.30;
#endif
    }
#if GRADE >= 2
    else if (near(px, 3.0) > 0.5) {
        a = 0.34 * breath;
    } else if (near(px, 4.0) > 0.5) {
        a = 0.16 * breath;
    }
#endif
#if GRADE >= 3
    else if (near(px, 5.0) > 0.5) {
        a = 0.10 * breath;
    }
#endif
    gl_FragColor = vec4(c * a, a);
}
