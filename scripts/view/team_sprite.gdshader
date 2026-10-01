shader_type canvas_item;
// Unit sprites: tints the pixels the mask marks with the owner's colour (the sheet renders those
// parts in shaded white, so multiplying keeps the shading) and adds a thin outline for contrast
// against busy terrain. The mask sheet has the same layout as the colour sheet.

uniform sampler2D mask_tex : filter_linear_mipmap;
uniform vec4 team_color : source_color = vec4(1.0);
uniform vec4 outline_color : source_color = vec4(0.07, 0.08, 0.1, 0.9);
uniform float outline_px = 1.0;
uniform float flash = 0.0;   // 0..1 white flash, e.g. when hit

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = texture(mask_tex, UV).r;
	c.rgb = mix(c.rgb, c.rgb * team_color.rgb, m);
	if (outline_px > 0.0 && c.a < 1.0) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_px;
		float a = max(max(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
				max(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
		float edge = a * (1.0 - c.a) * outline_color.a;
		c = vec4(mix(c.rgb, outline_color.rgb, edge / max(c.a + edge, 0.001)), c.a + edge);
	}
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	COLOR = c;
}
