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
    float2 uv;
};

vertex VOut v_main(VertexIn vin [[stage_in]],
                   constant Uniforms& u [[buffer(1)]])
{
    VOut out;
    float4 posWS = u.model * float4(vin.position, 1.0);
    out.position = u.proj * u.view * posWS;

    // 3x3 de la model matrix para normales (sirve si no hay escalado no uniforme)
    float3x3 M = float3x3(u.model[0].xyz,
                          u.model[1].xyz,
                          u.model[2].xyz);
    out.normalWS = normalize(M * vin.normal);
    out.uv = float2(vin.uv.x, 1.0 - vin.uv.y);
    return out;
}

fragment float4 f_main(VOut fin [[stage_in]],
                       constant Uniforms& u [[buffer(1)]],
                       texture2d<float> baseTex [[texture(0)]],
                       sampler samp [[sampler(0)]])
{
    float3 N = normalize(fin.normalWS);
    float3 L = normalize(-u.lightDir);
    float diff = max(dot(N, L), 0.1);

    float3 albedo = float3(0.8, 0.85, 0.9);
    if (baseTex.get_width() > 0 && baseTex.get_height() > 0) {
        albedo = baseTex.sample(samp, fin.uv).rgb;
    }

    return float4(albedo * diff, 1.0);
}
