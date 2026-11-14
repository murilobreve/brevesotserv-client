// Hunt Board - a very strong monster (experience rate 4x or more: it has
// more health and hits harder). The monster in blood red, with a heartbeat:
// two quick beats and a rest. Set by the client itself (game_huntboard,
// Creature::setStrongShader); a rare tier's shader always comes before it.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    float t = mod(u_Time, 1.5);
    float beat = exp(-9.0 * t) + 0.7 * exp(-9.0 * abs(t - 0.28));
    beat = clamp(beat, 0.0, 1.0);
    float l = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    // the monster in blood red: dark crimson shadows, hot red lights
    vec3 hot = mix(vec3(0.30, 0.0, 0.02), vec3(1.0, 0.36, 0.22), smoothstep(0.03, 0.8, l));
    vec3 result = mix(col.rgb, hot, 0.58 + 0.30 * beat);
    result += vec3(0.22, 0.04, 0.0) * beat * smoothstep(0.1, 0.7, l);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
