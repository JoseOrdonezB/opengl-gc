//
//  Common.metal
//  lab9
//
//  Created by Jose Ordoñez on 24/10/25.
//

#ifndef COMMON_METAL_INCLUDED
#define COMMON_METAL_INCLUDED

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
    float    ambient;
    float time;
    float3 _pad0;
};

struct Varyings {
    float4 position [[position]];
    float3 normalWS;
    float2 uv;
    float3 normalVS;
    float3 viewDirVS;
};

static inline __attribute__((unused))
float2 fixUV(float2 uv) {
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

static inline __attribute__((unused))
float3x3 inverse3x3(float3x3 m) {
    float a=m[0][0], b=m[0][1], c=m[0][2];
    float d=m[1][0], e=m[1][1], f=m[1][2];
    float g=m[2][0], h=m[2][1], i=m[2][2];

    float A=(e*i - f*h), B=-(d*i - f*g), C=(d*h - e*g);
    float D=-(b*i - c*h), E=(a*i - c*g), F=-(a*h - b*g);
    float G=(b*f - c*e), H=-(a*f - c*d), I=(a*e - b*d);

    float det = a*A + b*B + c*C;
    if (fabs(det) < 1e-8f) {
        return float3x3(float3(1,0,0), float3(0,1,0), float3(0,0,1));
    }
    float invDet = 1.0f / det;
    return float3x3(float3(A,B,C)*invDet,
                    float3(D,E,F)*invDet,
                    float3(G,H,I)*invDet);
}

#endif // COMMON_METAL_INCLUDED
