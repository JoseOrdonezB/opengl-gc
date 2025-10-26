//
//  VertexShaders.metal
//  lab9
//
//  Created by Jose Ordoñez on 25/10/25.
//

#include "Common.metal"
using namespace metal;

vertex Varyings v_main(VertexIn vin [[stage_in]],
                       constant Uniforms& u [[buffer(1)]])
{
    Varyings out;
    float4 posWS = u.model * float4(vin.position, 1.0);
    out.position = u.proj * (u.view * posWS);

#if USE_NORMAL_MATRIX
    float3x3 M    = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    float3x3 Nmat = transpose(inverse3x3(M));
    out.normalWS  = normalize(Nmat * vin.normal);
#else
    float3x3 M3   = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    out.normalWS  = normalize(M3 * vin.normal);
#endif

    out.uv = fixUV(vin.uv);
    return out;
}

// ===== Creative variant (vertex) =====
struct VaryingsC {
    float4 position [[position]];
    float2 uv;
};

vertex VaryingsC v_creative(VertexIn vin [[stage_in]],
                            constant Uniforms& u [[buffer(1)]])
{
    VaryingsC o;
    float4 posWS = u.model * float4(vin.position, 1.0);
    o.position   = u.proj * (u.view * posWS);
    // Para la demo creativa, no alteramos UV (si quieres flip, usa fixUV):
    o.uv = vin.uv;
    return o;
}

// (Opcional) Fragment que hace match con VaryingsC
fragment float4 f_creative_simple(VaryingsC fin [[stage_in]])
{
    // Bandas + gradiente simple con UV sin corregir
    float stripes = step(0.5, fract(fin.uv.x * 10.0));
    float3 col = mix(float3(0.1, 0.2, 0.8), float3(1.0, 0.8, 0.2), fin.uv.y);
    col *= mix(0.25, 1.0, stripes);
    return float4(col, 1.0);
}
