//
//  VertexShaders.metal
//  lab9
//
//  Created by Jose Ordoñez on 25/10/25.
//

#include "Common.metal"
using namespace metal;

static inline float fractf(float x) { return x - floor(x); }

static inline float hash3(float3 p) {
    float n = sin(dot(p, float3(12.9898, 78.233, 37.719))) * 43758.5453;
    return fractf(n);
}

static inline float3 rotateY(float3 v, float a) {
    float c = cos(a), s = sin(a);
    return float3(c*v.x + s*v.z, v.y, -s*v.x + c*v.z);
}

vertex Varyings v_main(VertexIn vin [[stage_in]],
                       constant Uniforms& u [[buffer(1)]])
{
    Varyings out;

    float3 p = vin.position;
    float3 n = normalize(vin.normal);

    float4 posWS = u.model * float4(p, 1.0);
    float4 posVS = u.view * posWS;
    out.position = u.proj * posVS;

    float3x3 M = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);

#if USE_NORMAL_MATRIX
    float3x3 Nmat = transpose(inverse3x3(M));
    float3 nWS = normalize(Nmat * n);
#else
    float3 nWS = normalize(M * n);
#endif

    out.normalWS = nWS;
    out.uv       = fixUV(vin.uv);

    float3x3 V3  = float3x3(u.view[0].xyz, u.view[1].xyz, u.view[2].xyz);
    out.normalVS = normalize(V3 * nWS);
    out.viewDirVS = normalize(-posVS.xyz);

    return out;
}

static inline Varyings vert_plant_sway(VertexIn vin,
                                       constant Uniforms& u)
{
    Varyings out;

    float3 p = vin.position;
    float3 n = normalize(vin.normal);
    float  t = u.time;

    float heightMask = clamp((p.y + 1.5f) * 0.5f, 0.0f, 1.0f);

    float sway    = sin(t * 1.5f + p.y * 0.7f) * 0.15f * heightMask;
    float forward = cos(t * 1.2f + p.x * 0.8f) * 0.08f * heightMask;

    p.x += sway;
    p.z += forward;

    float4 posWS = u.model * float4(p, 1.0);
    float4 posVS = u.view * posWS;
    out.position = u.proj * posVS;

    float3x3 M = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);

#if USE_NORMAL_MATRIX
    float3x3 Nmat = transpose(inverse3x3(M));
    float3 nWS = normalize(Nmat * n);
#else
    float3 nWS = normalize(M * n);
#endif

    out.normalWS = nWS;
    out.uv       = fixUV(vin.uv);

    float3x3 V3  = float3x3(u.view[0].xyz, u.view[1].xyz, u.view[2].xyz);
    out.normalVS = normalize(V3 * nWS);
    out.viewDirVS = normalize(-posVS.xyz);

    return out;
}

static inline Varyings vert_breath_pulse(VertexIn vin,
                                         constant Uniforms& u)
{
    Varyings out;

    float3 p = vin.position;
    float3 n = normalize(vin.normal);
    float  t = u.time;

    float beat  = sin(t * 3.0f) * 0.06f;
    float scale = 1.0f + beat;
    p *= scale;

    float topMask = clamp((p.y + 1.0f) * 0.5f, 0.0f, 1.0f);
    p.y += sin(t * 4.0f + p.x * 2.0f) * 0.05f * topMask;

    float4 posWS = u.model * float4(p, 1.0);
    float4 posVS = u.view * posWS;
    out.position = u.proj * posVS;

    float3x3 M = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);

#if USE_NORMAL_MATRIX
    float3x3 Nmat = transpose(inverse3x3(M));
    float3 nWS = normalize(Nmat * n);
#else
    float3 nWS = normalize(M * n);
#endif

    out.normalWS = nWS;
    out.uv       = fixUV(vin.uv);

    float3x3 V3  = float3x3(u.view[0].xyz, u.view[1].xyz, u.view[2].xyz);
    out.normalVS = normalize(V3 * nWS);
    out.viewDirVS = normalize(-posVS.xyz);

    return out;
}

static inline Varyings vert_electric_wobble(VertexIn vin,
                                            constant Uniforms& u)
{
    Varyings out;

    float3 p = vin.position;
    float3 n = normalize(vin.normal);
    float  t = u.time;

    float mainWave = sin(p.y * 6.0f + t * 8.0f) * 0.04f;
    float jitter   = (hash3(float3(p.x * 4.0f, p.y * 4.0f, t * 2.0f)) - 0.5f) * 0.04f;

    p.x += mainWave + jitter;
    p.z += -mainWave * 0.6f;
    p.y += sin(p.x * 4.0f + t * 5.0f) * 0.02f;

    float4 posWS = u.model * float4(p, 1.0);
    float4 posVS = u.view * posWS;
    out.position = u.proj * posVS;

    float3x3 M = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);

#if USE_NORMAL_MATRIX
    float3x3 Nmat = transpose(inverse3x3(M));
    float3 nWS = normalize(Nmat * n);
#else
    float3 nWS = normalize(M * n);
#endif

    out.normalWS = nWS;
    out.uv       = fixUV(vin.uv);

    float3x3 V3  = float3x3(u.view[0].xyz, u.view[1].xyz, u.view[2].xyz);
    out.normalVS = normalize(V3 * nWS);
    out.viewDirVS = normalize(-posVS.xyz);

    return out;
}

static inline Varyings vert_head_bob(VertexIn vin,
                                     constant Uniforms& u)
{
    Varyings out;

    float3 p = vin.position;
    float3 n = normalize(vin.normal);
    float  t = u.time;

    float topMask = clamp((p.y + 0.5f) * 0.6f, 0.0f, 1.0f);

    float bob   = sin(t * 3.0f) * 0.12f * topMask;
    p.y += bob;

    float angle = sin(t * 2.5f) * 0.35f * topMask;
    p = rotateY(p, angle);
    n = normalize(rotateY(n, angle));

    float4 posWS = u.model * float4(p, 1.0);
    float4 posVS = u.view * posWS;
    out.position = u.proj * posVS;

    float3x3 M = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);

#if USE_NORMAL_MATRIX
    float3x3 Nmat = transpose(inverse3x3(M));
    float3 nWS = normalize(Nmat * n);
#else
    float3 nWS = normalize(M * n);
#endif

    out.normalWS = nWS;
    out.uv       = fixUV(vin.uv);

    float3x3 V3  = float3x3(u.view[0].xyz, u.view[1].xyz, u.view[2].xyz);
    out.normalVS = normalize(V3 * nWS);
    out.viewDirVS = normalize(-posVS.xyz);

    return out;
}

static inline Varyings vert_stage_wave(VertexIn vin,
                                       constant Uniforms& u)
{
    Varyings out;

    float3 p = vin.position;
    float3 n = normalize(vin.normal);
    float  t = u.time;

    float2 xz = p.xz;
    float  r  = length(xz);

    float fade = 1.0f - clamp(r / 6.0f, 0.0f, 1.0f);
    float wave = sin(r * 4.5f - t * 3.0f) * 0.08f * fade;

    p.y += wave;

    float4 posWS = u.model * float4(p, 1.0);
    float4 posVS = u.view * posWS;
    out.position = u.proj * posVS;

    float3x3 M = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);

#if USE_NORMAL_MATRIX
    float3x3 Nmat = transpose(inverse3x3(M));
    float3 nWS = normalize(Nmat * n);
#else
    float3 nWS = normalize(M * n);
#endif

    out.normalWS = nWS;
    out.uv       = fixUV(vin.uv);

    float3x3 V3  = float3x3(u.view[0].xyz, u.view[1].xyz, u.view[2].xyz);
    out.normalVS = normalize(V3 * nWS);
    out.viewDirVS = normalize(-posVS.xyz);

    return out;
}

vertex Varyings v_party_mix(VertexIn vin [[stage_in]],
                            constant Uniforms& u [[buffer(1)]])
{
    float idx = u.modelIndex;

    if (idx < 0.5f) {
        return vert_plant_sway(vin, u);
    } else if (idx < 1.5f) {
        return vert_breath_pulse(vin, u);
    } else if (idx < 2.5f) {
        return vert_electric_wobble(vin, u);
    } else if (idx < 3.5f) {
        return vert_head_bob(vin, u);
    } else {
        return vert_stage_wave(vin, u);
    }
}
