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

// 1) v_noise_deform
vertex Varyings v_noise_deform(VertexIn vin [[stage_in]],
                               constant Uniforms& u [[buffer(1)]])
{
    const float freq = 3.0;
    const float amp  = 0.08;
    const float oct2 = 0.5;

    float3 pObj = vin.position;
    float3 nObj = normalize(vin.normal);

    float n1 = hash3(pObj * freq);
    float n2 = hash3(pObj * (freq * 2.07));
    float noise = (n1 - 0.5) + oct2 * (n2 - 0.5);

    pObj += nObj * (noise * amp);

    float4 posWS = u.model * float4(pObj, 1.0);

    Varyings out;
    out.position = u.proj * (u.view * posWS);

#if USE_NORMAL_MATRIX
    float3x3 M    = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    float3x3 Nmat = transpose(inverse3x3(M));
    out.normalWS  = normalize(Nmat * nObj);
#else
    float3x3 M3   = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    out.normalWS  = normalize(M3 * nObj);
#endif

    out.uv = fixUV(vin.uv);
    return out;
}

// 2) v_thin_shrink
vertex Varyings v_thin_shrink(VertexIn vin [[stage_in]],
                              constant Uniforms& u [[buffer(1)]])
{
    const float shrink    = 0.55;
    const float centerY   = 0.0;
    const float hourglass = 0.0;

    float3 pObj = vin.position;
    float3 nObj = vin.normal;

    float yAbs = fabs(pObj.y - centerY);
    float t    = clamp(hourglass * yAbs, 0.0, 1.0);
    float s    = mix(shrink, 1.0, t);

    pObj.x *= s;
    pObj.z *= s;

    float3 nDeformed = normalize(float3(nObj.x / s, nObj.y, nObj.z / s));

    float4 posWS = u.model * float4(pObj, 1.0);

    Varyings out;
    out.position = u.proj * (u.view * posWS);

#if USE_NORMAL_MATRIX
    float3x3 M    = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    float3x3 Nmat = transpose(inverse3x3(M));
    out.normalWS  = normalize(Nmat * nDeformed);
#else
    float3x3 M3   = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    out.normalWS  = normalize(M3 * nDeformed);
#endif

    out.uv = fixUV(vin.uv);
    return out;
}

// 3) v_twist_y
vertex Varyings v_twist_y(VertexIn vin [[stage_in]],
                          constant Uniforms& u [[buffer(1)]])
{
    const float twistStrength = 0.9;
    const float yCenter       = 0.0;

    float3 pObj = vin.position;
    float3 nObj = normalize(vin.normal);

    float yRel  = pObj.y - yCenter;
    float angle = twistStrength * yRel;

    pObj = rotateY(pObj, angle);
    nObj = normalize(rotateY(nObj, angle));

    float4 posWS = u.model * float4(pObj, 1.0);

    Varyings out;
    out.position = u.proj * (u.view * posWS);

#if USE_NORMAL_MATRIX
    float3x3 M    = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    float3x3 Nmat = transpose(inverse3x3(M));
    out.normalWS  = normalize(Nmat * nObj);
#else
    float3x3 M3   = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    out.normalWS  = normalize(M3 * nObj);
#endif

    out.uv = fixUV(vin.uv);
    return out;
}
