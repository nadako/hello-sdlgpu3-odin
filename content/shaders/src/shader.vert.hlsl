cbuffer UBO : register(b0, space1) { // TODO: separate global and local UBOs
	float4x4 vp;
	float4x4 m;
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
	float4 worldPosition = mul(m, float4(input.position, 1));

	Output output;
	output.clipPosition = mul(vp, worldPosition);
	output.color = input.color;
	output.uv = input.uv;
	output.position = worldPosition.xyz;
	output.normal = normalize(mul(m, float4(input.normal, 0)).xyz); // TODO: use normal matrix to support non-uniform scales
	return output;
}
