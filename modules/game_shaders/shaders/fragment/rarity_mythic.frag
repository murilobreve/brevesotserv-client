// Baiak Rarity System - Mythic
// Diamond White Mythic
//
// No hue rotation.
// No rainbow colors.
// Original item remains recognizable.
// Permanent white / silver theme.
// Animated white crystalline shine.

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

    // Narrow bright band.
    float sheen =
        smoothstep(0.72, 0.98, wave);

    // Don't strongly affect completely black pixels.
    sheen *=
        smoothstep(0.12, 0.65, lum);

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
        pearlSheen * 0.18
    );


    // --------------------------------------------------
    // Gentle white breathing glow
    // --------------------------------------------------

    float pulse =
        0.5 +
        0.5 * sin(u_Time * 1.2);

    result +=
        vec3(0.025) *
        pulse *
        whiteMask;


    gl_FragColor = vec4(
        clamp(result, 0.0, 1.0),
        col.a
    );
}