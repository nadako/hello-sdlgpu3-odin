cbuffer Global : register(b0, space3) {
	float3 lightPosition;
	float3 lightColor;
	float lightIntensity;
	float3 viewPosition;
	float3 ambientLightColor;
};

struct Input {
};

float4 main(Input input) : SV_Target0 {
	float3 outRadiance = lightColor * lightIntensity;
	return float4(outRadiance, 1);
}
