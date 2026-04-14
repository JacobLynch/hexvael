shader_type canvas_item;

uniform float speed : hint_range(1.0, 30.0) = 12.0;
uniform float min_intensity : hint_range(0.0, 1.0) = 0.8;
uniform vec4 glow_color : source_color = vec4(0.55, 0.63, 1.0, 1.0);

void fragment() {
    float pulse = min_intensity + (1.0 - min_intensity) * (0.5 + 0.5 * sin(TIME * speed));
    vec4 col = texture(TEXTURE, UV);
    COLOR = vec4(col.rgb * glow_color.rgb * pulse, col.a * glow_color.a);
}
