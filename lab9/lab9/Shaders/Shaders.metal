//
//  Shaders.metal
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

#include <metal_stdlib>
using namespace metal;

#ifndef FLIP_V
#define FLIP_V             1
#endif
#ifndef FLIP_U
#define FLIP_U             0
#endif
#ifndef SWAP_UV
#define SWAP_UV            0
#endif
#ifndef TWOSIDED_NORMALS
#define TWOSIDED_NORMALS   1
#endif
#ifndef DEBUG_UV
#define DEBUG_UV           0
#endif
#ifndef FORCE_GAMMA_DECODE
#define FORCE_GAMMA_DECODE 0
#endif
#ifndef USE_NORMAL_MATRIX
#define USE_NORMAL_MATRIX  1
#endif

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

static inline float2 fixUV(float2 uv)
{
#if SWAP_UV
    uv = uv.yx;
#endif
#if FLIP_U
    uv.x = 1.0 - uv.x;
#endif
#if FLIP_V
    uv.y = 1.0 - uv.y;
#endif
    return uv;
}

static inline float3x3 inverse3x3(float3x3 m)
{
    float a=m[0][0], b=m[0][1], c=m[0][2];
    float d=m[1][0], e=m[1][1], f=m[1][2];
    float g=m[2][0], h=m[2][1], i=m[2][2];

    float A =  (e*i - f*h);
    float B = -(d*i - f*g);
    float C =  (d*h - e*g);
    float D = -(b*i - c*h);
    float E =  (a*i - c*g);
    float F = -(a*h - b*g);
    float G =  (b*f - c*e);
    float H = -(a*f - c*d);
    float I =  (a*e - b*d);

    float det = a*A + b*B + c*C;
    if (fabs(det) < 1e-8f) {
        return float3x3(float3(1,0,0), float3(0,1,0), float3(0,0,1));
    }
    float invDet = 1.0f / det;
    return float3x3(float3(A,B,C)*invDet,
                    float3(D,E,F)*invDet,
                    float3(G,H,I)*invDet);
}

vertex VOut v_main(VertexIn vin [[stage_in]],
                   constant Uniforms& u [[buffer(1)]])
{
    VOut out;

    float4 posWS = u.model * float4(vin.position, 1.0);
    out.position = u.proj * (u.view * posWS);

#if USE_NORMAL_MATRIX
    float3x3 M    = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    float3x3 Nmat = transpose(inverse3x3(M));
    out.normalWS  = normalize(Nmat * vin.normal);
#else
    float3x3 M3 = float3x3(u.model[0].xyz, u.model[1].xyz, u.model[2].xyz);
    out.normalWS = normalize(M3 * vin.normal);
#endif

    out.uv = fixUV(vin.uv);
    return out;
}

fragment float4 f_main(VOut fin [[stage_in]],
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
    const float ambient = 0.15f;
    float diff = max(dot(N, L), 0.0f) + ambient;

    float3 albedo = float3(0.8, 0.85, 0.9);
    if (baseTex.get_width() > 0 && baseTex.get_height() > 0) {
        float3 c = baseTex.sample(samp, fin.uv).rgb;
    #if FORCE_GAMMA_DECODE
        c = pow(c, float3(2.2));
    #endif
        albedo = c;
    }

    return float4(albedo * diff, 1.0);
}
