//
//  Skybox.metal
//  lab9
//
//  Created by Jose Ordoñez on 25/10/25.
//

#include <metal_stdlib>
using namespace metal;

#ifndef SKYBOX_FORCE_GAMMA_DECODE
#define SKYBOX_FORCE_GAMMA_DECODE 0
#endif

struct SkyboxUniforms {
    float4x4 viewProjNoTrans;
};

struct VSOut {
    float4 position [[position]];
    float3 dirWS;
};

vertex VSOut skybox_v_main(const device float3* positions [[buffer(0)]],
                           uint vid [[vertex_id]],
                           constant SkyboxUniforms& u [[buffer(1)]])
{
    VSOut o;
    float3 dir = positions[vid];
    o.dirWS = dir;

    o.position = u.viewProjNoTrans * float4(dir, 1.0);

    return o;
}

fragment float4 skybox_f_main(VSOut in [[stage_in]],
                              texturecube<float> skyTex [[texture(0)]],
                              sampler samp [[sampler(0)]])
{
    float3 col = skyTex.sample(samp, normalize(in.dirWS)).rgb;

#if SKYBOX_FORCE_GAMMA_DECODE
    col = pow(col, float3(2.2));
#endif

    return float4(col, 1.0);
}
