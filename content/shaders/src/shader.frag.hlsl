#include "common.hlsl"

cbuffer Local : register(b1, space3) {
	float3 materialSpecularColor;
	float materialShininess;
};

struct Input {
	float4 color : TEXCOORD0;
	float2 uv : TEXCOORD1;
	float3 position : TEXCOORD2;
	float3 normal : TEXCOORD3;
};

Texture2D<float4> diffuseMap : register(t0, space2);
SamplerState smp : register(s0, space2);

float3 blinnPhongBRDF(float3 dirToLight, float3 dirToView, float3 surfaceNormal, float3 materialDiffuseReflection) {
	float3 halfWayDir = normalize(dirToLight + dirToView);
	float specularDot = max(0, dot(halfWayDir, surfaceNormal));
	float specularFactor = pow(specularDot, materialShininess);
	float3 specularReflection = materialSpecularColor * specularFactor;

	return materialDiffuseReflection + specularReflection; // TODO: energy conservation / normalization?
}

float4 main(Input input) : SV_Target0 {
	float3 vecToLight = lightPosition - input.position;
	float distToLight = length(vecToLight);
	float3 dirToLight = vecToLight / distToLight;

	float3 dirToView = normalize(viewPosition - input.position);

	float3 surfaceNormal = normalize(input.normal);

	float3 materialDiffuseReflection = diffuseMap.Sample(smp, input.uv).rgb;

	float3 ambientIrradiance = ambientLightColor;

	float3 reflectedRadiance = ambientIrradiance * materialDiffuseReflection;

	float incidenceAngleFactor = dot(dirToLight, surfaceNormal); // 1 direct incidence, 0 - no incidence, -1 incidence from the other side
	if (incidenceAngleFactor > 0) {
		float attenuationFactor = 1 / (distToLight * distToLight); // TODO: add more control variables
		float3 incomingRadiance = lightColor * lightIntensity;
		float3 irradiance = incomingRadiance * incidenceAngleFactor * attenuationFactor;
		float3 brdf = blinnPhongBRDF(dirToLight, dirToView, surfaceNormal, materialDiffuseReflection);
		reflectedRadiance += irradiance * brdf;
	}

	float3 emittedRadiance = float3(0, 0, 0);

	float3 outRadiance = emittedRadiance + reflectedRadiance;

	return float4(outRadiance, 1);
}
