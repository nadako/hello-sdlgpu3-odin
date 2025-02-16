#version 460

layout(set=1, binding=0) uniform UBO {
	mat4 mvp;
};

layout(location=0) in vec3 position;
layout(location=1) in vec4 color;

layout(location=0) out vec4 out_color;

void main() {
	gl_Position = mvp * vec4(position, 1);
	out_color = color;
}