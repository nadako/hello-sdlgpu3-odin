#include "common.hlsl"

cbuffer Local : register(b1, space1) {
	float4x4 modelMat;
	float4x4 normalMat;
};

struct Input {
	float3 position : TEXCOORD0;
	float4 color : TEXCOORD1;
	float2 uv : TEXCOORD2;
	float3 normal : TEXCOORD3;
};

struct Output {
	float4 clipPosition : SV_Position;
	float4 color : TEXCOORD0;
	float2 uv : TEXCOORD1;
	float3 position : TEXCOORD2;
	float3 normal : TEXCOORD3;
};

Output main(Input input) {
	float4 worldPosition = mul(modelMat, float4(input.position, 1));

	Output output;
	output.clipPosition = mul(viewProjectionMat, worldPosition);
	output.color = input.color;
	output.uv = input.uv;
	output.position = worldPosition.xyz;
	output.normal = normalize(mul(normalMat, float4(input.normal, 0)).xyz);
	return output;
}
