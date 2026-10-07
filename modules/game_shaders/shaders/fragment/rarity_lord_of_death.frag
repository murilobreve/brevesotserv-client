// Baiak Rarity System - Lord of Death Tier
// All black: a silhouette of pure darkness. Only a faint cold edge on the
// brightest parts keeps the shape readable, and a slow shadow ripple moves
// over it. No colour at all.
// The ripple is keyed by the pixel's own colour, not by v_TexCoord (a place
// in the sprite atlas that changes every animation frame), so it does not
// jump around while the monster walks.

uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));

    // black body, a little structure left in the bright parts
    float shade = pow(lum, 1.6) * 0.16;

    // slow shadow ripple
    float ripple = sin(lum * 22.0 + u_Time * 1.6) * 0.5 + 0.5;
    shade += ripple * smoothstep(0.35, 0.85, lum) * 0.035;

    // breathing: the whole body dims and recovers
    float breath = 0.85 + 0.15 * sin(u_Time * 1.2);

    vec3 result = vec3(shade * breath);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
