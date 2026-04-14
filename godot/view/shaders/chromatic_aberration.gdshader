shader_type canvas_item;

uniform float offset : hint_range(0.0, 10.0) = 2.0;
uniform float strength : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    vec2 dir = normalize(UV - center);
    float edge = length(UV - center) * 2.0;

    vec4 col = texture(TEXTURE, UV);
    vec4 r = texture(TEXTURE, UV - dir * offset * TEXTURE_PIXEL_SIZE * edge);
    vec4 b = texture(TEXTURE, UV + dir * offset * TEXTURE_PIXEL_SIZE * edge);

    COLOR = vec4(
        mix(col.r, r.r, strength * edge),
        col.g,
        mix(col.b, b.b, strength * edge),
        col.a
    );
}
