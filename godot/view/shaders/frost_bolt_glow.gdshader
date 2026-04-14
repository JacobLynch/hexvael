shader_type canvas_item;

// Frost bolt outer glow - soft pulsing aura
// Uses VERTEX position since Polygon2D has no auto UVs

uniform float pulse_speed : hint_range(1.0, 30.0) = 10.0;
uniform float pulse_min : hint_range(0.0, 1.0) = 0.6;
uniform float glow_width : hint_range(5.0, 30.0) = 12.0;
uniform vec4 glow_color : source_color = vec4(0.4, 0.6, 1.0, 0.5);

varying vec2 vert_pos;

void vertex() {
    vert_pos = VERTEX;
}

void fragment() {
    // Pulse animation (slightly offset from core for visual interest)
    float pulse = pulse_min + (1.0 - pulse_min) * (0.5 + 0.5 * sin(TIME * pulse_speed + 0.5));

    // Soft edge falloff based on Y distance from center
    float edge_y = abs(vert_pos.y) / glow_width;
    edge_y = clamp(edge_y, 0.0, 1.0);
    float falloff = 1.0 - pow(edge_y, 1.5);

    // Apply color with falloff and pulse
    vec3 col = glow_color.rgb * pulse * (1.0 + falloff * 0.3);
    float alpha = glow_color.a * falloff * pulse;

    COLOR = vec4(col, alpha);
}
