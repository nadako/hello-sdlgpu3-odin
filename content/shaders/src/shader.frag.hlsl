cbuffer Global : register(b0, space3) {
	float3 lightPosition;
	float3 lightColor;
	float lightIntensity;
};

struct Input {
	float4 color : TEXCOORD0;
	float2 uv : TEXCOORD1;
	float3 position : TEXCOORD2;
	float3 normal : TEXCOORD3;
};

Texture2D<float4> tex : register(t0, space2);
SamplerState smp : register(s0, space2);

float4 main(Input input) : SV_Target0 {
	float3 vecToLight = lightPosition - input.position;
	float distToLight = length(vecToLight);
	float3 dirToLight = vecToLight / distToLight;

	float3 surfaceNormal = normalize(input.normal);

	float incidenceAngleFactor = dot(dirToLight, surfaceNormal); // 1 direct incidence, 0 - no incidence, -1 incidence from the other side
	float3 reflectedRadiance;
	if (incidenceAngleFactor > 0) {
		float attenuationFactor = 1 / (distToLight * distToLight); // TODO: add more control variables
		float3 incomingRadiance = lightColor * lightIntensity;
		float3 irradiance = incomingRadiance * incidenceAngleFactor * attenuationFactor;
		float3 brdf = 1;
		reflectedRadiance = irradiance * brdf;
	} else {
		reflectedRadiance = float3(0, 0, 0);
	}

	float3 emittedRadiance = float3(0, 0, 0);
	float3 outRadiance = emittedRadiance + reflectedRadiance;

	return float4(outRadiance, 1);
}
