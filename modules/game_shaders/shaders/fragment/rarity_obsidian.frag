// Baiak Rarity System - Obsidian Tier
// Blue-Violet Obsidian
//
// Dark obsidian creature with internal blue/purple cursed energy.
// Mostly black body, with glowing violet-blue fire trapped inside.
// Elegant, arcane, and threatening.

uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;

    float lum = dot(c, vec3(0.299, 0.587, 0.114));

    // ==================================================
    // BODY BASE
    // ==================================================

    vec3 abyss = vec3(
        0.001,
        0.002,
        0.008
    );

    vec3 obsidian = vec3(
        0.010,
        0.010,
        0.040
    );

    vec3 obsidianHighlight = vec3(
        0.030,
        0.022,
        0.105
    );

    vec3 result =
        mix(
            abyss,
            obsidian,
            pow(lum, 0.72)
        );

    result =
        mix(
            result,
            obsidianHighlight,
            pow(lum, 2.0) * 0.28
        );

    // Preserve a little original structure
    result += c * 0.030;


    // ==================================================
    // INTERNAL SHADOWFIRE PATTERN
    // ==================================================

    vec2 p = gl_FragCoord.xy;

    float rise =
        p.y * 0.14 -
        u_Time * 3.5;

    float wobble =
        sin(p.x * 0.18 + u_Time * 1.8) * 1.3 +
        sin(p.x * 0.09 - u_Time * 2.5) * 0.9;

    float f1 = sin(rise + wobble);
    float f2 = sin(p.y * 0.20 - u_Time * 4.2 + sin(p.x * 0.20) * 1.8);
    float f3 = sin(p.x * 0.28 + p.y * 0.08 - u_Time * 2.6);

    float energy =
        f1 * 0.50 +
        f2 * 0.30 +
        f3 * 0.20;

    energy = energy * 0.5 + 0.5;

    // Narrower internal flame presence
    energy = smoothstep(0.56, 0.88, energy);


    // ==================================================
    // BLUE + PURPLE OBSIDIAN PALETTE
    // ==================================================

    vec3 deepBlue = vec3(
        0.004,
        0.010,
        0.095
    );

    vec3 abyssPurple = vec3(
        0.055,
        0.006,
        0.140
    );

    vec3 violet = vec3(
        0.180,
        0.018,
        0.360
    );

    vec3 electricBlue = vec3(
        0.025,
        0.180,
        0.620
    );

    vec3 arcaneCore = vec3(
        0.230,
        0.080,
        0.720
    );

    float hot =
        smoothstep(0.77, 1.00, energy);

    // Slow moving blue-purple variation
    float colorShift =
        0.5 +
        0.5 *
        sin(
            p.x * 0.055 +
            p.y * 0.035 +
            u_Time * 0.85
        );

    vec3 darkEnergy =
        mix(
            deepBlue,
            abyssPurple,
            colorShift
        );

    vec3 energyColor =
        mix(
            darkEnergy,
            violet,
            smoothstep(0.58, 0.84, energy)
        );

    energyColor =
        mix(
            energyColor,
            electricBlue,
            hot * (0.35 + colorShift * 0.30)
        );

    energyColor =
        mix(
            energyColor,
            arcaneCore,
            pow(hot, 2.6) * 0.35
        );


    // ==================================================
    // APPLY FIRE
    // ==================================================

    float bodyMask =
        smoothstep(0.02, 0.28, lum);

    result =
        mix(
            result,
            energyColor,
            energy * bodyMask * 0.55
        );


    // ==================================================
    // DEMONIC / ARCANE HEARTBEAT
    // ==================================================

    float pulse =
        0.5 + 0.5 * sin(u_Time * 2.0);

    pulse = pow(pulse, 3.2);

    result +=
        vec3(
            0.045,
            0.010,
            0.260
        ) *
        energy *
        pulse *
        bodyMask *
        0.50;


    // ==================================================
    // OCCASIONAL THIN HOT STREAKS
    // ==================================================

    float streak =
        sin(p.x * 0.36 - p.y * 0.22 + u_Time * 4.5);

    streak = smoothstep(0.88, 0.98, streak);

    result +=
        vec3(
            0.120,
            0.030,
            0.340
        ) *
        streak *
        energy *
        bodyMask *
        0.24;


    // ==================================================
    // OBSIDIAN FRACTURES / CRACKS
    // ==================================================

    float crack1 =
        sin(
            p.x * 0.38 -
            p.y * 0.25 +
            u_Time * 2.7
        );

    crack1 =
        smoothstep(
            0.91,
            0.985,
            crack1
        );

    float crack2 =
        sin(
            p.x * 0.19 +
            p.y * 0.33 -
            u_Time * 2.0
        );

    crack2 =
        smoothstep(
            0.94,
            0.993,
            crack2
        );

    float cracks =
        max(
            crack1,
            crack2 * 0.65
        );

    vec3 crackBlue =
        vec3(
            0.015,
            0.130,
            0.520
        );

    vec3 crackPurple =
        vec3(
            0.260,
            0.025,
            0.620
        );

    vec3 crackColor =
        mix(
            crackBlue,
            crackPurple,
            colorShift
        );

    result +=
        crackColor *
        cracks *
        energy *
        bodyMask *
        0.45;


    // ==================================================
    // CRUSH DARK AREAS MORE
    // ==================================================

    float darkMask =
        1.0 - smoothstep(0.08, 0.25, lum);

    result =
        mix(
            result,
            vec3(0.001, 0.000, 0.006),
            darkMask * 0.68
        );


    // ==================================================
    // FINAL COLOR BALANCE
    // ==================================================

    // Keep the shader colder and more magical
    result.r *= 0.92;
    result.g *= 0.95;
    result.b *= 1.08;

    gl_FragColor =
        vec4(
            clamp(result, 0.0, 1.0),
            col.a
        );
}