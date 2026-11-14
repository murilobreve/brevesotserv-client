// Hunt Board - a very strong monster (experience rate 4x or more: it has
// more health and hits harder). Its own colours run hot, with a red
// heartbeat: two quick beats and a rest. Set by the client itself
// (game_huntboard, Creature::setStrongShader); a rare tier's shader always
// comes before it.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    float t = mod(u_Time, 1.5);
    float beat = exp(-11.0 * t) + 0.65 * exp(-11.0 * abs(t - 0.26));
    beat = clamp(beat, 0.0, 1.0);
    float l = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    // shadows go to a dark red, lights to ember orange
    vec3 hot = mix(vec3(0.34, 0.03, 0.03), vec3(1.0, 0.56, 0.30), smoothstep(0.05, 0.85, l));
    vec3 result = mix(col.rgb, hot, 0.38 + 0.34 * beat);
    result += vec3(0.16, 0.03, 0.0) * beat;
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
