#include "common.hlsl"

struct Input {
};

float4 main(Input input) : SV_Target0 {
	float3 outRadiance = lightColor * lightIntensity;
	return float4(outRadiance, 1);
}
