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

fragment float4 f_creative(Varyings fin [[stage_in]])
{
    float stripes = step(0.5, fract(fin.uv.x * 10.0));
    float3 col = mix(float3(0.1, 0.2, 0.8), float3(1.0, 0.8, 0.2), fin.uv.y);
    col *= mix(0.25, 1.0, stripes);
    return float4(col, 1.0);
}

// 1) "Metal" avanzado
fragment float4 f_metal(Varyings fin [[stage_in]],
                        constant Uniforms& u [[buffer(1)]],
                        texture2d<float> baseTex [[texture(0)]],
                        sampler samp [[sampler(0)]],
                        bool isFrontFace [[front_facing]])
{
    const float  roughness   = 0.15;
    const float  metalness   = 1.0;
    const float3 metalTint   = float3(0.78,0.82,0.90);
    const float  ambientBoost= 0.06;

    float3 N = normalize(fin.normalWS);
#if TWOSIDED_NORMALS
    if (!isFrontFace) N = -N;
#endif
    float3 Lws = normalize(-u.lightDir);

    float3 Nvs = normal_to_view(N, u);
    float3 Lvs = normal_to_view(Lws, u);
    float3 Vvs = float3(0,0,1);

    float NdotL = max(dot(Nvs, Lvs), 0.0);
    float NdotV = max(dot(Nvs, Vvs), 0.0);
    float3 H    = normalize(Lvs + Vvs);
    float NdotH = max(dot(Nvs, H), 0.0);
    float VdotH = max(dot(Vvs, H), 0.0);

    float3 baseCol = metalTint;
    if (baseTex.get_width() > 0 && baseTex.get_height() > 0) {
        baseCol = baseTex.sample(samp, fin.uv).rgb;
    }
    float3 F0 = mix(float3(0.04), baseCol, metalness);

    float3 F  = F0 + (1.0 - F0) * pow(clamp(1.0 - VdotH, 0.0, 1.0), 5.0);

    float a   = max(0.045, roughness);
    float a2  = a * a;
    float d   = (NdotH*NdotH) * (a2 - 1.0) + 1.0;
    float  D  = a2 / max(3.14159265 * d * d, 1e-5);

    auto G1 = [&](float NdX) {
        float k = (a + 1.0);
        k = (k*k) * 0.125;
        return NdX / max(NdX*(1.0 - k) + k, 1e-5);
    };
    float G = G1(NdotL) * G1(NdotV);

    float3 spec = (D * G * F) / max(4.0 * NdotL * NdotV + 1e-5, 1e-5);

    float3 kd    = (1.0 - metalness) * (1.0 - F);
    float3 diffuse = kd * baseCol * (NdotL / 3.14159265);

    float3 color = diffuse + spec;
    color += baseCol * (u.ambient + ambientBoost) * (1.0 - metalness);

    return float4(clamp(color, 0.0, 1.0), 1.0);
}

// 2) Toon
fragment float4 f_toon_rim(Varyings fin [[stage_in]],
                           constant Uniforms& u [[buffer(1)]],
                           texture2d<float> baseTex [[texture(0)]],
                           sampler samp [[sampler(0)]],
                           bool isFrontFace [[front_facing]])
{
    const float steps        = 4.0;
    const float rimPower     = 3.0;
    const float rimStrength  = 0.55;
    const float specCutoff   = 0.85;
    const float specBoost    = 0.8; 
    const float ditherScale  = 180.0;

    float3 coolColor = float3(0.30, 0.40, 0.80);
    float3 warmColor = float3(1.00, 0.85, 0.55);
    float3 rimColor  = float3(1.00, 1.00, 1.00);

    float3 N = normalize(fin.normalWS);
#if TWOSIDED_NORMALS
    if (!isFrontFace) N = -N;
#endif
    float3 L = normalize(-u.lightDir);
    float NdotL = max(dot(N, L), 0.0);

    float3 baseCol = float3(0.75, 0.78, 0.85);
    if (baseTex.get_width() > 0 && baseTex.get_height() > 0) {
        baseCol = baseTex.sample(samp, fin.uv).rgb;
    }

    float t = floor(NdotL * steps) / (steps - 1.0);
    t = clamp(t, 0.0, 1.0);
    float3 toonRamp = mix(coolColor, warmColor, t);

    float3 V = normalize(- ( (float3)( (u.view * float4(0,0,0,1)).xyz ) ));
    float3 H = normalize(L + V);
    float NdotH = max(dot(N, H), 0.0);
    float spec  = NdotH;
    spec = (spec > specCutoff) ? specBoost : 0;

    float3 Nvs = normal_to_view(N, u);
    float rim  = pow(clamp(1.0 - fabs(Nvs.z), 0.0, 1.0), rimPower);

    float dither = (sin(fin.uv.x * ditherScale) * cos(fin.uv.y * ditherScale)) * 0.03;
    float3 shaded = (baseCol * (u.ambient * 0.4 + 0.6 * t + dither)) * toonRamp;

    float3 color = shaded
                 + rimColor * rim * rimStrength
                 + float3(spec, spec, spec);

    return float4(clamp(color, 0.0, 1.0), 1.0);
}

// 3) Matcap procedural

fragment float4 f_matcap_solid(Varyings fin [[stage_in]],
                               constant Uniforms& u [[buffer(1)]],
                               bool isFrontFace [[front_facing]])
{
    float3 N = normalize(fin.normalWS);
#if TWOSIDED_NORMALS
    if (!isFrontFace) N = -N;
#endif

    float3 Nvs = normal_to_view(N, u);

    float t = clamp(Nvs.z * 0.5 + 0.5, 0.0, 1.0);
    float3 low  = float3(0.10, 0.12, 0.16);
    float3 high = float3(0.80, 0.85, 0.95);
    float3 base = mix(low, high, t);

    float crossX = exp(-20.0 * Nvs.x * Nvs.x);
    float crossY = exp(-20.0 * Nvs.y * Nvs.y);
    float highlight = clamp(crossX + crossY, 0.0, 1.0) * 0.4;

    float3 color = base + highlight;

    float NdotL = max(dot(N, normalize(-u.lightDir)), 0.0);
    color *= (0.4 + 0.6 * NdotL);

    color *= (0.5 + 0.5 * clamp(u.ambient, 0.0, 1.0));

    return float4(clamp(color, 0.0, 1.0), 1.0);
}
