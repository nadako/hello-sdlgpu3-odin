#include "common.hlsl"

cbuffer Local : register(b1, space1) {
	float4x4 modelMat;
};

struct Input {
	float3 position : TEXCOORD0;
};

struct Output {
	float4 clipPosition : SV_Position;
};

Output main(Input input) {
	float4 worldPosition = mul(modelMat, float4(input.position, 1));

	Output output;
	output.clipPosition = mul(viewProjectionMat, worldPosition);
	return output;
}
