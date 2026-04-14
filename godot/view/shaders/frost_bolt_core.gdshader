shader_type canvas_item;

// Frost bolt core shader - creates icy crystalline effect on Polygon2D
// Uses VERTEX position (passed to fragment) since Polygon2D has no auto UVs

uniform float pulse_speed : hint_range(1.0, 30.0) = 12.0;
uniform float pulse_min : hint_range(0.0, 1.0) = 0.8;
uniform float frost_scale : hint_range(0.01, 0.2) = 0.08;
uniform float frost_intensity : hint_range(0.0, 1.0) = 0.35;
uniform vec4 core_color : source_color = vec4(0.8, 0.95, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.4, 0.65, 1.0, 1.0);
uniform float bolt_width : hint_range(5.0, 30.0) = 14.0;

varying vec2 vert_pos;

void vertex() {
    // Pass vertex position to fragment shader
    vert_pos = VERTEX;
}

// Simple hash for noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal noise for frost pattern
float frost_noise(vec2 pos, float time) {
    float n = 0.0;
    float amp = 0.5;
    vec2 p = pos * frost_scale;

    for (int i = 0; i < 3; i++) {
        n += amp * noise(p + time * 2.0);
        p *= 2.0;
        amp *= 0.5;
    }
    return n;
}

void fragment() {
    // Pulse animation
    float pulse = pulse_min + (1.0 - pulse_min) * (0.5 + 0.5 * sin(TIME * pulse_speed));

    // Use Y position for edge detection (how far from center line)
    float edge_y = abs(vert_pos.y) / bolt_width;
    edge_y = clamp(edge_y, 0.0, 1.0);

    // Frost crystalline pattern based on world position
    float frost = frost_noise(vert_pos, TIME);
    frost = smoothstep(0.3, 0.7, frost) * frost_intensity;

    // Mix core and edge colors - brighter in center
    vec4 base_color = mix(core_color, edge_color, edge_y);

    // Add frost pattern as brightness variation
    base_color.rgb += frost * vec3(0.15, 0.2, 0.25);

    // Bright core streak
    float core_glow = 1.0 - edge_y;
    core_glow = pow(core_glow, 1.5) * 0.4;
    base_color.rgb += vec3(core_glow);

    // Apply pulse
    base_color.rgb *= pulse;

    // Slight blue shift at edges for icy feel
    base_color.b += edge_y * 0.1;

    COLOR = vec4(base_color.rgb, base_color.a);
}
