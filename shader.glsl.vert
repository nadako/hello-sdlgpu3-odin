#version 460

layout(set=1, binding=0) uniform UBO {
	mat4 mvp;
};

void main() {
	vec4 position;
	if (gl_VertexIndex == 0) {
		position = vec4(-0.5, -0.5, 0, 1);
	} else  if (gl_VertexIndex == 1) {
		position = vec4(0, 0.5, 0, 1);
	} else if (gl_VertexIndex == 2) {
		position = vec4(0.5, -0.5, 0, 1);
	}
	gl_Position = mvp * position;
}