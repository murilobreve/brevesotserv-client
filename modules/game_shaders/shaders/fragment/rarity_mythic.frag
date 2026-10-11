// Baiak Rarity System - Mythic
// Diamond White Mythic
//
// No hue rotation.
// No rainbow colors.
// Original item remains recognizable.
// Permanent white / silver theme, 40% whiter than the first version.
// Animated white crystalline shine, a fast glint and twinkling sparkles.

uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;

    // --------------------------------------------------
    // Original brightness
    // --------------------------------------------------

    float lum = dot(c, vec3(0.299, 0.587, 0.114));


    // --------------------------------------------------
    // Preserve original item, but desaturate slightly
    // --------------------------------------------------

    vec3 gray = vec3(lum);

    // Keep most of the original color.
    vec3 result = mix(
        c,
        gray,
        0.25
    );


    // --------------------------------------------------
    // Permanent white / pearl tone
    // --------------------------------------------------

    // Slightly cold diamond white.
    vec3 diamondWhite = vec3(
        0.96,
        0.975,
        1.00
    );

    // Brighter original pixels become more white.
    float whiteMask =
        smoothstep(0.18, 0.88, lum);

    result = mix(
        result,
        diamondWhite,
        whiteMask * 0.94
    );


    // --------------------------------------------------
    // Keep dark details
    // --------------------------------------------------

    // Prevent black outlines and dark materials
    // from becoming washed out.
    float darkMask =
        1.0 - smoothstep(0.08, 0.30, lum);

    result = mix(
        result,
        c * 0.78,
        darkMask * 0.70
    );


    // --------------------------------------------------
    // 40% whiter
    // --------------------------------------------------

    // The whole item moves 40% of the way to diamond white; the darkest
    // pixels (outlines) keep most of their value so the shape still reads.
    float whiter =
        0.40 * smoothstep(0.04, 0.22, lum);

    result = mix(
        result,
        diamondWhite,
        whiter
    );


    // --------------------------------------------------
    // Moving diamond shine
    // --------------------------------------------------

    // Diagonal white reflection travelling across item.
    // screen-space (see rarity_pale.frag): v_TexCoord is an atlas position
    float wave =
        sin(
            gl_FragCoord.x * 0.060 +
            gl_FragCoord.y * 0.045 -
            u_Time * 2.3
        );

    // Bright band (wider than before: more shine).
    float sheen =
        smoothstep(0.60, 0.97, wave);

    // Don't strongly affect completely black pixels.
    sheen *=
        smoothstep(0.08, 0.55, lum);

    vec3 pureWhite = vec3(
        1.0,
        1.0,
        1.0
    );

    result = mix(
        result,
        pureWhite,
        sheen * 1.48
    );


    // --------------------------------------------------
    // Secondary soft pearl reflection
    // --------------------------------------------------

    float wave2 =
        sin(
            gl_FragCoord.x * 0.036 -
            gl_FragCoord.y * 0.054 -
            u_Time * 1.5
        );

    float pearlSheen =
        smoothstep(0.82, 1.0, wave2);

    pearlSheen *=
        smoothstep(0.25, 0.80, lum);

    vec3 pearl = vec3(
        0.88,
        0.92,
        1.00
    );

    result = mix(
        result,
        pearl,
        pearlSheen * 0.30
    );


    // --------------------------------------------------
    // Fast glint
    // --------------------------------------------------

    // A thin, quick flash that crosses the item every few seconds.
    float glintWave =
        sin(
            gl_FragCoord.x * 0.090 +
            gl_FragCoord.y * 0.090 -
            u_Time * 4.2
        );

    float glint =
        smoothstep(0.985, 1.0, glintWave) *
        smoothstep(0.10, 0.50, lum);

    result = mix(
        result,
        pureWhite,
        glint * 0.85
    );


    // --------------------------------------------------
    // Twinkling sparkles
    // --------------------------------------------------

    // A few 2x2 pixel spots light up and fade, each at its own pace.
    vec2 cell =
        floor(gl_FragCoord.xy / 2.0);

    float seed =
        fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);

    float twinkle =
        step(0.965, seed) *
        pow(max(0.0, sin(u_Time * 3.1 + seed * 60.0)), 6.0) *
        smoothstep(0.10, 0.45, lum);

    result = mix(
        result,
        pureWhite,
        twinkle
    );


    // --------------------------------------------------
    // Gentle white breathing glow
    // --------------------------------------------------

    float pulse =
        0.5 +
        0.5 * sin(u_Time * 1.2);

    result +=
        vec3(0.06) *
        pulse *
        whiteMask;


    gl_FragColor = vec4(
        clamp(result, 0.0, 1.0),
        col.a
    );
}