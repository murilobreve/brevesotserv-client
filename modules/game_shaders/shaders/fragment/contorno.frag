// Contorno: a thin line of light round the silhouette of a player wearing
// Mythicus items, in the colour of their element. The server picks the
// variant (scripts/rarity/outline.lua); modules/game_shaders/shaders.lua
// builds one per grade and colour by defining:
//   GRADE  1 = the line alone, steady; 2 = line, a soft glow past it and a
//          glint that crosses it now and then; 3 = the same in two colours
//          that flow along the line
//   COLOR  the element's colour; COLOR2 the second colour of GRADE 3
// The steps are pixels of the sprite (the texture matrix turns pixels into
// texture coordinates), so the line is one sprite pixel wide at any zoom.
uniform float u_Time;
uniform mat3 u_TextureMatrix;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float solid(vec2 px, float dx, float dy) {
    return step(0.5, texture2D(u_Tex0, v_TexCoord + vec2(dx, dy) * px).a);
}

// 1 when a solid pixel lies `r` steps away in one of eight directions
float near(vec2 px, float r) {
    float d = r * 0.7071;
    return max(max(max(solid(px, r, 0.0), solid(px, -r, 0.0)), max(solid(px, 0.0, r), solid(px, 0.0, -r))),
               max(max(solid(px, d, d), solid(px, -d, d)), max(solid(px, d, -d), solid(px, -d, -d))));
}

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a > 0.5) {
        gl_FragColor = col;
        return;
    }
    vec2 px = abs(vec2(u_TextureMatrix[0][0], u_TextureMatrix[1][1]));
    float line = near(px, 1.0);
    float halo1 = near(px, 2.0);
    float halo2 = near(px, 3.0);

    // a slow breath, and a glint that crosses the character every few seconds
    float breath = 0.86 + 0.14 * sin(u_Time * 1.7);
    float sweep = (gl_FragCoord.x + gl_FragCoord.y) * 0.035 - u_Time * 2.2;
    float glint = pow(max(0.0, sin(sweep)), 24.0) * step(0.0, sin(sweep * 0.25 + 1.0));

    vec3 tone = COLOR;
#if GRADE >= 3
    float flow = 0.5 + 0.5 * sin((gl_FragCoord.x - gl_FragCoord.y) * 0.06 + u_Time * 1.1);
    tone = mix(COLOR, COLOR2, flow);
#endif
    vec3 lineColor = mix(tone, vec3(1.0), 0.5);
    float a = 0.0;
    vec3 c = tone;
#if GRADE >= 2
    a = max(halo1 * 0.40, halo2 * 0.18) * breath;
    lineColor = mix(lineColor, vec3(1.0), glint);
#endif
    if (line > 0.5) {
        c = lineColor;
#if GRADE >= 2
        a = 0.86 * breath + 0.14 * glint;
#else
        a = 0.8;
#endif
    }
    gl_FragColor = vec4(c * a, a);
}
