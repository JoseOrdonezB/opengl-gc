//
//  FragmentShaders.metal
//  lab9
//
//  Created by Jose Ordoñez on 25/10/25.
//

#include "Common.metal"
using namespace metal;

static inline float3 normal_to_view(float3 N, constant Uniforms& u)
{
    float3x3 V3 = float3x3(u.view[0].xyz, u.view[1].xyz, u.view[2].xyz);
    return normalize(V3 * N);
}

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
    float shade   = clamp(u.ambient + lambert, 0.0f, 1.0f);

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

static inline float3 party_neon(float3 baseCol,
                                float3 Nvs,
                                float t)
{
    float3 neonBase   = float3(0.3, 0.0, 0.6);
    float3 neonAccent = float3(0.1, 0.8, 1.0);

    float rim   = pow(clamp(1.0 - fabs(Nvs.z), 0.0, 1.0), 3.0);
    float pulse = 0.5 + 0.5 * sin(t * 4.0);

    float3 col = mix(baseCol, neonBase, 0.5)
               + neonAccent * rim * (0.5 + 0.5 * pulse);

    return clamp(col, 0.0, 1.0);
}

static inline float3 party_strobe(float3 baseCol,
                                  float t)
{
    float speed = 8.0;
    float s = 0.5 + 0.5 * sin(t * speed);
    float hard = s > 0.7 ? 1.0 : 0.0;

    float3 flash = float3(1.5, 1.5, 1.5) * hard;
    float3 col   = baseCol * (0.6 + 0.4 * s) + flash * 0.4;
    return clamp(col, 0.0, 1.0);
}

static inline float3 party_lasers(float3 baseCol,
                                  float2 uv,
                                  float t)
{
    float2 p = uv * 4.0;
    p.x += t * 2.0;

    float stripe1 = smoothstep(0.05, 0.0, fabs(fract(p.x + p.y) - 0.5));
    float stripe2 = smoothstep(0.08, 0.0, fabs(fract(p.x * 1.3 - p.y) - 0.5));

    float3 c1 = float3(0.0, 1.0, 0.4);
    float3 c2 = float3(1.0, 0.1, 0.6);

    float3 glow = c1 * stripe1 + c2 * stripe2;
    float3 col  = baseCol * 0.5 + glow * 1.3;
    return clamp(col, 0.0, 1.0);
}

static inline float3 party_stage_glow(float3 baseCol,
                                      float2 uv,
                                      float t)
{
    float topGlow = clamp(uv.y * 1.5, 0.0, 1.0);
    float pulse   = 0.5 + 0.5 * sin(t * 3.0 + uv.x * 6.0);

    float3 warm = float3(1.0, 0.7, 0.3);
    float3 cool = float3(0.2, 0.2, 0.6);

    float3 grad = mix(cool, warm, topGlow);
    float3 col  = baseCol * (0.5 + 0.5 * topGlow) + grad * (0.6 + 0.4 * pulse);
    return clamp(col, 0.0, 1.0);
}

static inline float3 party_rainbow(float3 baseCol,
                                   float2 uv,
                                   float t)
{
    float u = uv.x + 0.1 * sin(t * 2.0 + uv.y * 6.0);
    u = fract(u);

    float3 colorA = float3(1.0, 0.0, 0.3);
    float3 colorB = float3(1.0, 0.8, 0.0);
    float3 colorC = float3(0.0, 1.0, 0.4);
    float3 colorD = float3(0.2, 0.4, 1.0);

    float3 c;
    if (u < 0.25) {
        float k = u / 0.25;
        c = mix(colorA, colorB, k);
    } else if (u < 0.5) {
        float k = (u - 0.25) / 0.25;
        c = mix(colorB, colorC, k);
    } else if (u < 0.75) {
        float k = (u - 0.5) / 0.25;
        c = mix(colorC, colorD, k);
    } else {
        float k = (u - 0.75) / 0.25;
        c = mix(colorD, colorA, k);
    }

    float brightness = 0.7 + 0.3 * sin(t * 5.0 + uv.y * 10.0);
    c *= brightness;

    float3 col = baseCol * 0.4 + c * 1.3;
    return clamp(col, 0.0, 1.0);
}

fragment float4 f_party_mix(Varyings fin [[stage_in]],
                            constant Uniforms& u [[buffer(1)]],
                            texture2d<float> baseTex [[texture(0)]],
                            sampler samp [[sampler(0)]],
                            bool isFrontFace [[front_facing]])
{
    float time = u.time;

    float3 N = normalize(fin.normalWS);
#if TWOSIDED_NORMALS
    if (!isFrontFace) N = -N;
#endif

    float3 L = normalize(-u.lightDir);
    float lambert = max(dot(N, L), 0.0f);

    float3 baseTexColor = float3(0.8, 0.85, 0.9);
    if (baseTex.get_width() > 0 && baseTex.get_height() > 0) {
        float3 texCol = baseTex.sample(samp, fin.uv).rgb;
    #if FORCE_GAMMA_DECODE
        texCol = pow(texCol, float3(2.2));
    #endif
        baseTexColor = texCol;
    }

    float shade = clamp(u.ambient * 0.5 + lambert * 0.8, 0.0f, 1.0f);
    float3 baseLit = baseTexColor * shade;

    float3 Nvs = normal_to_view(N, u);
    float2 uv  = fin.uv;

    int idx = (int)round(u.modelIndex);

    float3 partyColor;

    if (idx == 0) {
        partyColor = party_neon(baseLit, Nvs, time);
    }
    else if (idx == 1) {
        partyColor = party_lasers(baseLit, uv, time);
    }
    else if (idx == 2) {
        partyColor = party_rainbow(baseLit, uv, time);
    }
    else if (idx == 3) {
        float3 ncol = party_neon(baseLit, Nvs, time);
        float3 stro = party_strobe(ncol, time);
        partyColor  = mix(ncol, stro, 0.5);
    }
    else if (idx == 4) {
        partyColor = party_stage_glow(baseLit, uv, time);
    }
    else {
        partyColor = baseLit;
    }

    float rim = pow(clamp(1.0 - fabs(Nvs.z), 0.0, 1.0), 2.5);
    float3 rimCol = float3(1.0, 1.0, 1.0) * rim * 0.35;

    float3 finalColor = partyColor + rimCol;

    return float4(clamp(finalColor, 0.0, 1.0), 1.0);
}
