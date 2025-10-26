//
//  FragmentShaders.metal
//  lab9
//
//  Created by Jose Ordoñez on 25/10/25.
//

#include "Common.metal"
using namespace metal;

fragment float4 f_main(Varyings fin [[stage_in]],
                       constant Uniforms& u [[buffer(1)]],
                       texture2d<float> baseTex [[texture(0)]],
                       sampler samp [[sampler(0)]],
                       bool isFrontFace [[front_facing]])
{
#if DEBUG_UV
    return float4(fin.uv, 0.0, 1.0);
#endif

    float3 N = normalize(fin.normalWS);
#if TWOSIDED_NORMALS
    if (!isFrontFace) N = -N;
#endif

    float3 L = normalize(-u.lightDir);
    float lambert = max(dot(N, L), 0.0f);
    // clamp en lugar de saturate por portabilidad
    float shade = clamp(u.ambient + lambert, 0.0f, 1.0f);

    float3 albedo = float3(0.8, 0.85, 0.9);
    if (baseTex.get_width() > 0 && baseTex.get_height() > 0) {
        float3 c = baseTex.sample(samp, fin.uv).rgb;
    #if FORCE_GAMMA_DECODE
        c = pow(c, float3(2.2));
    #endif
        albedo = c;
    }

    return float4(albedo * shade, 1.0);
}

// Fragment “creativo” de ejemplo (bandas y gradiente)
fragment float4 f_creative(Varyings fin [[stage_in]])
{
    float stripes = step(0.5, fract(fin.uv.x * 10.0));
    float3 col = mix(float3(0.1, 0.2, 0.8), float3(1.0, 0.8, 0.2), fin.uv.y);
    col *= mix(0.25, 1.0, stripes);
    return float4(col, 1.0);
}
