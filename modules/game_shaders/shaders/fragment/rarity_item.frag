// Rarity items, "Reliquias Vivas" (design kit itens-reliquias-vivas, v1).
// One source for the 40 item shaders "Rarity - <Grade> - <Element>":
// shaders.lua puts "#define GRADE n" and "#define ELEMENT n" before it and
// registers each variant (registerRarityItemShaders). The server picks the
// name from the item's grade and its first element tag (Rarity.itemShaderName).
// MYTHOS / RELIQUIAS VIVAS — candidate v1, grade layer strengthened so the
// tier reads at a glance (tint, highlights, a reflection every 4 s, gold
// sparks on Legendarius, a stronger opal on Mythicus)
// One texture read; atlas-safe; alpha and dark ink preserved.
// GRADE 1..5; ELEMENT 0 none, 1 fire, 2 earth, 3 energy,
// 4 ice, 5 holy, 6 death, 7 physical. Patterns use screen pixels.
// The client supplies precision headers. No new uniforms required.
#ifndef GRADE
#define GRADE 5
#endif
#ifndef ELEMENT
#define ELEMENT 0
#endif
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec2 u_Resolution;
varying vec2 v_TexCoord;
const float TAU = 6.28318530718;
float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float wave(float x) { return 0.5 + 0.5 * sin(x); }
float line(float x, float width) {
    return 1.0 - smoothstep(width, width + 0.10, abs(sin(x)));
}
// Keeps luminance while adding colour; avoids bleaching coloured sprites.
vec3 pigment(vec3 c, vec3 hue, float weight) {
    vec3 target = hue * (lum(c) / max(lum(hue), 0.10));
    target /= max(1.0, max(target.r, max(target.g, target.b)));
    return mix(c, target, weight);
}
void main() {
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec2 p = gl_FragCoord.xy;
    float t = mod(u_Time, 600.0);
    float l = lum(col.rgb);
    float ink = smoothstep(0.08, 0.34, l);
    float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
    float protect = 1.0 - 0.30 * smoothstep(0.15, 0.65, sat);
    // the item's highlights: where the grade shows in every frame
    float hl = smoothstep(0.40, 0.90, l);
    float phase = p.x * 0.061 + p.y * 0.097;
    float sweep = pow(wave((p.x + p.y * 0.65) * 0.30 - t * TAU / 4.0), 8.0);
    float fine = line((p.x - p.y) * 0.61, 0.05);
    float facet = line((p.x + p.y) * 0.39, 0.07) * fine;
    vec3 jewel;
    float tint;
    float light;
    float accent;
    // the grade's own drawing in light (facets, engraving, threads, veins):
    // it reads on any item, coloured or not, where a tint alone fades
    float etch = 0.0;
#if GRADE == 1
    // CETIM DE JADE: soft polished surface, one quiet travelling reflection.
    jewel = vec3(0.388, 0.753, 0.541);
    tint = 0.34; light = 0.22 * sweep + 0.16 * hl; accent = 0.0;
#elif GRADE == 2
    // LAPIDACAO DE SAFIRA: fine crossed planes catch the blue reflection.
    jewel = vec3(0.310, 0.561, 0.910);
    tint = 0.46; light = 0.34 * sweep + 0.12 * fine + 0.22 * hl;
    accent = 0.12 * facet;
    etch = 0.42 * line((p.x - p.y) * 0.61, 0.30);
#elif GRADE == 3
    // GRAVURA DE AMETISTA: a crystalline engraving wakes beneath the surface.
    jewel = vec3(0.651, 0.475, 0.902);
    tint = 0.56; light = 0.44 * sweep + 0.18 * fine + 0.28 * hl;
    accent = 0.38 * facet * wave(t * TAU / 5.0 + phase);
    etch = 0.55 * max(line((p.x - p.y) * 0.61, 0.24), line((p.x + p.y) * 0.39, 0.24));
#elif GRADE == 4
    // FILIGRANA SOLAR: interlaced golden threads with breathing intersections.
    jewel = vec3(0.886, 0.643, 0.263);
    float thread = line(p.x * 0.54 + sin(p.y * 0.42) * 0.65, 0.07);
    tint = 0.64; light = 0.55 * sweep + 0.32 * thread + 0.34 * hl;
    // sparks: a few pixels flare gold, each at its own pace
    vec2 cell = floor(p / 2.0);
    float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
    float spark = step(0.975, seed) * pow(wave(t * TAU / 3.0 + seed * 50.0), 8.0);
    accent = 0.45 * facet * wave(t * TAU / 6.0 + phase) + 1.2 * spark * hl;
    etch = 0.62 * line(p.x * 0.54 + sin(p.y * 0.42) * 0.65, 0.30) + 0.9 * spark;
#else
    // OPALA VIVA: prismatic veins and tiny internal stars; never a white fill.
    vec3 opal = 0.62 + 0.32 * cos(vec3(0.0, 2.1, 4.2) + phase + t * TAU / 12.0);
    jewel = mix(vec3(0.910, 0.894, 1.0), opal, 0.70);
    float vein = line(p.x * 0.49 + sin(p.y * 0.37) * 0.9, 0.07);
    float star = line(p.x * 0.81, 0.045) * line(p.y * 0.73, 0.045);
    tint = 0.66; light = 0.70 * sweep + 0.42 * vein + 0.40 * hl;
    accent = 0.65 * max(facet, star) * (0.35 + 0.65 * wave(t * TAU / 5.0 + phase));
    etch = 0.66 * line(p.x * 0.49 + sin(p.y * 0.37) * 0.9, 0.30)
         + 0.80 * line(p.x * 0.81, 0.16) * line(p.y * 0.73, 0.16) * (0.5 + 0.5 * wave(t * TAU / 5.0 + phase));
#endif
    vec3 c = pigment(col.rgb, jewel, tint * ink * protect);
    c += (1.0 - c) * jewel * (light + accent) * ink;
    // engraved: deep jewel grooves on bright metal, glowing seams on dark parts
    vec3 etchColor = mix(mix(jewel, vec3(1.0), 0.45), jewel * 0.38, smoothstep(0.45, 0.75, l));
    c = mix(c, etchColor, clamp(etch, 0.0, 1.0) * ink);
    // Element signatures: spatial shapes differ as well as their hues.
    // All temporal frequencies divide 600 seconds, making the time wrap continuous.
    vec3 elementColor = jewel;
    float pattern = 0.0;
#if ELEMENT == 1
    // IGNEUS: staggered rising ember seams, keeping the sprite's native flame.
    elementColor = vec3(1.0, 0.416, 0.165);
    pattern = pow(wave(p.y * 0.8 - t * TAU / 3.0 + sin(p.x * 0.7) * 2.0), 7.0)
            * (0.3 + 0.7 * wave(p.x * 1.1));
#elif ELEMENT == 2
    // TERRENUS: fixed branching moss veins; a slow living pulse.
    elementColor = vec3(0.424, 0.820, 0.227);
    pattern = line(p.x * 0.55 + sin(p.y * 0.47) * 1.8, 0.16)
            * (0.55 + 0.45 * wave(t * TAU / 10.0 + phase));
#elif ELEMENT == 3
    // FULMINEUS: a fixed zigzag conductor with a soft, infrequent charge.
    elementColor = vec3(0.710, 0.420, 1.0);
    float zig = abs(fract(p.y / 9.0) * 2.0 - 1.0) * 3.0;
    pattern = line(p.x * 0.55 + zig, 0.07)
            * (0.2 + 0.8 * pow(wave(t * TAU / 4.0 + phase * 0.4), 6.0));
#elif ELEMENT == 4
    // GLACIALIS: stationary frost lattice, gently catching light.
    elementColor = vec3(0.322, 0.863, 1.0);
    pattern = max(line((p.x + p.y) * 0.62, 0.055), line((p.x - p.y) * 0.62, 0.055))
            * (0.50 + 0.50 * wave(t * TAU / 12.0 + phase));
#elif ELEMENT == 5
    // SACER: long oblique shafts, slow ceremonial movement.
    elementColor = vec3(1.0, 0.847, 0.290);
    pattern = pow(wave(p.x * 0.43 + p.y * 0.12 - t * TAU / 15.0), 9.0);
#elif ELEMENT == 6
    // MORTIFER: violet smoke enclosed in the material, never a black silhouette.
    elementColor = vec3(0.541, 0.239, 0.749);
    pattern = pow(wave(p.x * 0.29 + sin(p.y * 0.34 + t * TAU / 12.0) * 2.0
                     + t * TAU / 15.0), 3.0);
    c *= 1.0 - pattern * ink * 0.07;
#elif ELEMENT == 7
    // CORPORALIS: directional steel grain and a controlled cold reflection.
    elementColor = vec3(0.722, 0.745, 0.776);
    pattern = line((p.x + p.y * 0.23) * 1.2, 0.12)
            * (0.35 + 0.65 * sweep);
#endif
    float power = 0.14 + 0.075 * float(GRADE);
    c = pigment(c, elementColor, pattern * power * ink * protect);
    c += (1.0 - c) * elementColor * pattern * power * 0.68 * ink;
    gl_FragColor = vec4(clamp(c, 0.0, 1.0), col.a);
}
