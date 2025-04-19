#include "common.hlsl"

struct Input {
	uint vertexId : SV_VertexID;
};

struct Output {
	float4 clipPosition : SV_Position;
	float3 texCoords : TEXCOORD0;
};

Output main(Input input) {
	//float2 vertices[] = {
	//	float2(-1, -1),
	//	float2( 3, -1),
	//	float2(-1,  3),
	//};
	//float2 vertexPosition = vertices[input.vertexId];

	// or the same without an array
	float2 vertexPosition = float2(
		-1 + float((input.vertexId & 1) << 2), // for vertex 0 and 2 we get -1 + 0, because bit 1 isn't set. for vertex 1 we get -1 + 4, because 1 << 2 is 4
		-1 + float((input.vertexId & 2) << 1) // for vertex 0 and 1 we get -1 + 0, because bit 2 isn't set. for vertex 2 we get -1 + 4, because 2 << 1 is 4
	);

	float4 clipSpacePosition = float4(vertexPosition, 1, 1);

	float4 viewSpacePosition = mul(invProjectionMat, clipSpacePosition);

	float4 viewDir = mul(invViewMat, float4(viewSpacePosition.xyz, 0));

	Output output;
	output.clipPosition = clipSpacePosition;
	output.texCoords = viewDir;
	return output;
}
