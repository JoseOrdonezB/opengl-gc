//
//  Shaders.metal
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct Uniforms {
    float4x4 model;
    float4x4 view;
    float4x4 proj;
    float3   lightDir;
};

struct VOut {
    float4 position [[position]];
    float3 normalWS;
    float3 posWS;
};

vertex VOut v_main(VertexIn in [[stage_in]],
                   constant Uniforms& u [[buffer(1)]])
{
    VOut out;
    float4 posWS = u.model * float4(in.position, 1.0);
    out.position = u.proj * u.view * posWS;
    out.posWS = posWS.xyz;

    float3x3 M = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    out.normalWS = normalize(M * in.normal);
    return out;
}

fragment float4 f_main(VOut in [[stage_in]],
                       constant Uniforms& u [[buffer(1)]])
{
    float3 N = normalize(in.normalWS);
    float3 L = normalize(-u.lightDir);
    float diff = max(dot(N, L), 0.1);
    float3 base = float3(0.8, 0.85, 0.9);
    return float4(base * diff, 1.0);
}
