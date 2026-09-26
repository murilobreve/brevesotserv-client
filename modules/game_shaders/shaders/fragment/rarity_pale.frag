// Baiak Rarity System - Pale Tier
// Ghostly White / Pale Pearl
//
// Permanent white/pale theme.
// Original monster remains recognizable.
// Dark areas remain dark.
// Light areas become pale white.
// Soft white sheen moves across the monster.

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
    vec3 gray = vec3(lum);


    // --------------------------------------------------
    // Drain most of the original color
    // --------------------------------------------------

    // Still preserves a little of the original material.
    vec3 result = mix(
        c,
        gray,
        0.62
    );


    // --------------------------------------------------
    // Pale white base
    // --------------------------------------------------

    // Slightly cold/off-white.
    // Avoid pure white so the monster doesn't look glowing.
    vec3 paleWhite = vec3(
        0.86,
        0.87,
        0.89
    );

    // Light pixels become considerably paler.
    float whiteMask =
        smoothstep(0.28, 0.88, lum);

    result = mix(
        result,
        paleWhite,
        whiteMask * 0.46
    );


    // --------------------------------------------------
    // Dead/pale midtones
    // --------------------------------------------------

    vec3 deadPale = vec3(
        0.66,
        0.67,
        0.68
    );

    float midMask =
        smoothstep(0.18, 0.45, lum) *
        (1.0 - smoothstep(0.60, 0.84, lum));

    result = mix(
        result,
        deadPale,
        midMask * 0.22
    );


    // --------------------------------------------------
    // Preserve dark parts
    // --------------------------------------------------

    // Belts, outlines, dark armor, etc. should remain dark.
    float darkMask =
        1.0 - smoothstep(0.08, 0.30, lum);

    result = mix(
        result,
        c * 0.72,
        darkMask * 0.80
    );


    // --------------------------------------------------
    // Soft moving white sheen
    // --------------------------------------------------

    float wave =
        sin(
            v_TexCoord.x * 18.0 +
            v_TexCoord.y * 12.0 -
            u_Time * 1.5
        );

    // Wider and softer than Mythic.
    float sheen =
        smoothstep(0.72, 0.98, wave);

    // Mostly visible on lighter areas.
    sheen *=
        smoothstep(0.28, 0.80, lum);

    vec3 shineWhite = vec3(
        0.96,
        0.97,
        1.00
    );

    result = mix(
        result,
        shineWhite,
        sheen * 3.22
    );


    // --------------------------------------------------
    // Very gentle breathing brightness
    // --------------------------------------------------

    float pulse =
        0.5 +
        0.5 * sin(u_Time * 0.9);

    result +=
        vec3(0.012) *
        pulse *
        whiteMask;


    gl_FragColor = vec4(
        clamp(result, 0.0, 1.0),
        col.a
    );
}