#include "common.hlsl"

struct Input {
	float3 texCoords : TEXCOORD0;
};

TextureCube<float4> cubeMap : register(t0, space2);
SamplerState smp : register(s0, space2);

float4 main(Input input) : SV_Target0 {
	return cubeMap.Sample(smp, input.texCoords);
}
