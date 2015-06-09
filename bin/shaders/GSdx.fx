/*===============================================================================*\
|########################      [GSdx FX Suite v2.20]      ########################|
|##########################        By Asmodean          ##########################|
||                                                                               ||
||          This program is free software; you can redistribute it and/or        ||
||          modify it under the terms of the GNU General Public License          ||
||          as published by the Free Software Foundation; either version 2       ||
||          of the License, or (at your option) any later version.               ||
||                                                                               ||
||          This program is distributed in the hope that it will be useful,      ||
||          but WITHOUT ANY WARRANTY; without even the implied warranty of       ||
||          MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        ||
||          GNU General Public License for more details. (c)2014                 ||
||                                                                               ||
|#################################################################################|
\*===============================================================================*/

#ifndef SHADER_MODEL
#define GLSL 1
#extension GL_ARB_gpu_shader5 : enable
#else
#define GLSL 0
#endif

#if defined(SHADER_MODEL) && (SHADER_MODEL <= 0x300)
#error GSdx FX requires shader model 4.0(Direct3D10) or higher. Use GSdx DX10/11.
#endif

#ifdef SHADER_MODEL
#include "GSdx_FX_Settings.ini"
#endif

/*------------------------------------------------------------------------------
                             [GLOBALS|FUNCTIONS]
------------------------------------------------------------------------------*/
#if (GLSL == 1)

#define int2 ivec2
#define float2 vec2
#define float3 vec3
#define float4 vec4
#define float3x3 mat3
#define float4x4 mat4
#define static
#define frac fract
#define mul(x, y) x * y
#define lerp(x,y,s) mix(x,y,s)
#define saturate(x) clamp(x, 0.0, 1.0)
#define SamplerState sampler2D

#define matrix4(a0, a1, a2, a3, b0, b1, b2, b3, c0, c1, c2, c3, d0, d1, d2, d3) \
           mat4(a0, b0, c0, d0, a1, b1, c1, d1, a2, b2, c2, d2, a3, b3, c3, d3);

#define matrix3(a0, a1, a2, b0, b1, b2, c0, c1, c2) \
           mat3(a0, b0, c0, a1, b1, c1, a2, b2, c2);

// Yes it sucks!
#define matrix4x3(v0, v1, v2, v3) \
    mat3x4(v0.x, v1.x, v2.x, v3.x, v0.y, v1.y, v2.y, v3.y, v0.z, v1.z, v2.z, v3.z);

struct vertex_basic
{
    vec4 p;
    vec2 t;
};

#ifdef ENABLE_BINDLESS_TEX
layout(bindless_sampler, location = 0) uniform sampler2D TextureSampler;
#else
layout(binding = 0) uniform sampler2D TextureSampler;
#endif

in SHADER
{
    vec4 p;
    vec2 t;
} PSin;

layout(location = 0) out vec4 SV_Target0;

layout(std140, binding = 14) uniform cb10
{
    vec2 _xyFrame;
    vec4 _rcpFrame;
};

#else

#define matrix4(a0, a1, a2, a3, b0, b1, b2, b3, c0, c1, c2, c3, d0, d1, d2, d3) \
       float4x4(a0, a1, a2, a3, b0, b1, b2, b3, c0, c1, c2, c3, d0, d1, d2, d3);

#define matrix3(a0, a1, a2, b0, b1, b2, c0, c1, c2) \
       float3x3(a0, a1, a2, b0, b1, b2, c0, c1, c2);

#define matrix4x3(v0, v1, v2, v3) \
         float4x3(v0, v1, v2, v3);

Texture2D Texture : register(t0);
SamplerState TextureSampler : register(s0);

cbuffer cb0
{
    float2 _xyFrame;
    float4 _rcpFrame;
};

struct VS_INPUT
{
    float4 p : POSITION;
    float2 t : TEXCOORD0;
};

struct VS_OUTPUT
{
    float4 p : SV_Position;
    float2 t : TEXCOORD0;
};

struct PS_OUTPUT
{
    float4 c : SV_Target0;
};
#endif

static float2 screenSize = _xyFrame;
static float2 pixelSize = _rcpFrame.xy;
static float2 invDefocus = float2(1.0 / 3840.0, 1.0 / 2160.0);
static const float3 lumCoeff = float3(0.2126729, 0.7151522, 0.0721750);

float RGBLuminance(float3 color)
{
    return dot(color.rgb, lumCoeff);
}

float4 sample_tex(SamplerState texSample, float2 t)
{
#if (GLSL == 1)
    return texture(texSample, t);
#else
    return Texture.Sample(texSample, t);
#endif
}

float4 sample_texLevel(SamplerState texSample, float2 t, float lod)
{
#if (GLSL == 1)
    return textureLod(texSample, t, lod);
#else
    return Texture.SampleLevel(texSample, t, lod);
#endif
}

/*------------------------------------------------------------------------------
                            [FXAA CODE SECTION]
------------------------------------------------------------------------------*/

#if (UHQ_FXAA == 1)
#if (SHADER_MODEL >= 0x500)
#define FXAA_HLSL_5 1
#define FXAA_GATHER4_ALPHA 1
#elif (GLSL == 1)
#define FXAA_GATHER4_ALPHA 1
#else
#define FXAA_HLSL_4 1
#define FXAA_GATHER4_ALPHA 0
#endif

#if (FxaaQuality == 4)
#define FxaaEdgeThreshold 0.063
#define FxaaEdgeThresholdMin 0.000
#elif (FxaaQuality == 3)
#define FxaaEdgeThreshold 0.125
#define FxaaEdgeThresholdMin 0.0312
#elif (FxaaQuality == 2)
#define FxaaEdgeThreshold 0.166
#define FxaaEdgeThresholdMin 0.0625
#elif (FxaaQuality == 1)
#define FxaaEdgeThreshold 0.250
#define FxaaEdgeThresholdMin 0.0833
#endif

#if (FXAA_HLSL_5 == 1)
struct FxaaTex { SamplerState smpl; Texture2D tex; };
#define FxaaTexTop(t, p) t.tex.SampleLevel(t.smpl, p, 0.0)
#define FxaaTexOff(t, p, o, r) t.tex.SampleLevel(t.smpl, p, 0.0, o)
#define FxaaTexAlpha4(t, p) t.tex.GatherAlpha(t.smpl, p)
#define FxaaTexOffAlpha4(t, p, o) t.tex.GatherAlpha(t.smpl, p, o)
#define FxaaDiscard clip(-1)
#define FxaaSat(x) saturate(x)

#elif (FXAA_HLSL_4 == 1)
struct FxaaTex { SamplerState smpl; Texture2D tex; };
#define FxaaTexTop(t, p) t.tex.SampleLevel(t.smpl, p, 0.0)
#define FxaaTexOff(t, p, o, r) t.tex.SampleLevel(t.smpl, p, 0.0, o)
#define FxaaDiscard clip(-1)
#define FxaaSat(x) saturate(x)
#endif

#if (GLSL == 1)
#define FxaaBool bool
#define FxaaDiscard discard
#define FxaaSat(x) clamp(x, 0.0, 1.0)
#define FxaaTex sampler2D
#define FxaaTexTop(t, p) textureLod(t, p, 0.0)
#define FxaaTexOff(t, p, o, r) textureLodOffset(t, p, 0.0, o)
#if (FXAA_GATHER4_ALPHA == 1)
// use #extension GL_ARB_gpu_shader5 : enable
#define FxaaTexAlpha4(t, p) textureGather(t, p, 3)
#define FxaaTexOffAlpha4(t, p, o) textureGatherOffset(t, p, o, 3)
#define FxaaTexGreen4(t, p) textureGather(t, p, 1)
#define FxaaTexOffGreen4(t, p, o) textureGatherOffset(t, p, o, 1)
#endif
#endif

#define FXAA_QUALITY__P0 1.0
#define FXAA_QUALITY__P1 1.0
#define FXAA_QUALITY__P2 1.0
#define FXAA_QUALITY__P3 1.0
#define FXAA_QUALITY__P4 1.0
#define FXAA_QUALITY__P5 1.5
#define FXAA_QUALITY__P6 2.0
#define FXAA_QUALITY__P7 2.0
#define FXAA_QUALITY__P8 2.0
#define FXAA_QUALITY__P9 2.0
#define FXAA_QUALITY__P10 4.0
#define FXAA_QUALITY__P11 8.0
#define FXAA_QUALITY__P12 8.0

float FxaaLuma(float4 rgba)
{
    rgba.w = RGBLuminance(rgba.xyz);
    return rgba.w;
}

float4 FxaaPixelShader(float2 pos, FxaaTex tex, float2 fxaaRcpFrame, float fxaaSubpix, float fxaaEdgeThreshold, float fxaaEdgeThresholdMin)
{
    float2 posM;
    posM.x = pos.x;
    posM.y = pos.y;

    #if (FXAA_GATHER4_ALPHA == 1)
    float4 rgbyM = FxaaTexTop(tex, posM);
    float4 luma4A = FxaaTexAlpha4(tex, posM);
    float4 luma4B = FxaaTexOffAlpha4(tex, posM, int2(-1, -1));
    rgbyM.w = RGBLuminance(rgbyM.xyz);

    #define lumaM rgbyM.w
    #define lumaE luma4A.z
    #define lumaS luma4A.x
    #define lumaSE luma4A.y
    #define lumaNW luma4B.w
    #define lumaN luma4B.z
    #define lumaW luma4B.x
    
    #else
    float4 rgbyM = FxaaTexTop(tex, posM);
    rgbyM.w = RGBLuminance(rgbyM.xyz);
    #define lumaM rgbyM.w

    float lumaS = FxaaLuma(FxaaTexOff(tex, posM, int2( 0, 1), fxaaRcpFrame.xy));
    float lumaE = FxaaLuma(FxaaTexOff(tex, posM, int2( 1, 0), fxaaRcpFrame.xy));
    float lumaN = FxaaLuma(FxaaTexOff(tex, posM, int2( 0,-1), fxaaRcpFrame.xy));
    float lumaW = FxaaLuma(FxaaTexOff(tex, posM, int2(-1, 0), fxaaRcpFrame.xy));
    #endif

    float maxSM = max(lumaS, lumaM);
    float minSM = min(lumaS, lumaM);
    float maxESM = max(lumaE, maxSM);
    float minESM = min(lumaE, minSM);
    float maxWN = max(lumaN, lumaW);
    float minWN = min(lumaN, lumaW);

    float rangeMax = max(maxWN, maxESM);
    float rangeMin = min(minWN, minESM);
    float range = rangeMax - rangeMin;
    float rangeMaxScaled = rangeMax * fxaaEdgeThreshold;
    float rangeMaxClamped = max(fxaaEdgeThresholdMin, rangeMaxScaled);

    bool earlyExit = range < rangeMaxClamped;
    #if (FxaaEarlyExit == 1)
    if(earlyExit) { return rgbyM; }
    #endif

    #if (FXAA_GATHER4_ALPHA == 0)
    float lumaNW = FxaaLuma(FxaaTexOff(tex, posM, int2(-1,-1), fxaaRcpFrame.xy));
    float lumaSE = FxaaLuma(FxaaTexOff(tex, posM, int2( 1, 1), fxaaRcpFrame.xy));
    float lumaNE = FxaaLuma(FxaaTexOff(tex, posM, int2( 1,-1), fxaaRcpFrame.xy));
    float lumaSW = FxaaLuma(FxaaTexOff(tex, posM, int2(-1, 1), fxaaRcpFrame.xy));
    #else
    float lumaNE = FxaaLuma(FxaaTexOff(tex, posM, int2( 1,-1), fxaaRcpFrame.xy));
    float lumaSW = FxaaLuma(FxaaTexOff(tex, posM, int2(-1, 1), fxaaRcpFrame.xy));
    #endif

    float lumaNS = lumaN + lumaS;
    float lumaWE = lumaW + lumaE;
    float subpixRcpRange = 1.0/range;
    float subpixNSWE = lumaNS + lumaWE;
    float edgeHorz1 = (-2.0 * lumaM) + lumaNS;
    float edgeVert1 = (-2.0 * lumaM) + lumaWE;
    float lumaNESE = lumaNE + lumaSE;
    float lumaNWNE = lumaNW + lumaNE;
    float edgeHorz2 = (-2.0 * lumaE) + lumaNESE;
    float edgeVert2 = (-2.0 * lumaN) + lumaNWNE;

    float lumaNWSW = lumaNW + lumaSW;
    float lumaSWSE = lumaSW + lumaSE;
    float edgeHorz4 = (abs(edgeHorz1) * 2.0) + abs(edgeHorz2);
    float edgeVert4 = (abs(edgeVert1) * 2.0) + abs(edgeVert2);
    float edgeHorz3 = (-2.0 * lumaW) + lumaNWSW;
    float edgeVert3 = (-2.0 * lumaS) + lumaSWSE;
    float edgeHorz = abs(edgeHorz3) + edgeHorz4;
    float edgeVert = abs(edgeVert3) + edgeVert4;

    float subpixNWSWNESE = lumaNWSW + lumaNESE;
    float lengthSign = fxaaRcpFrame.x;
    bool horzSpan = edgeHorz >= edgeVert;
    float subpixA = subpixNSWE * 2.0 + subpixNWSWNESE;
    if(!horzSpan) lumaN = lumaW;
    if(!horzSpan) lumaS = lumaE;
    if(horzSpan) lengthSign = fxaaRcpFrame.y;
    float subpixB = (subpixA * (1.0/12.0)) - lumaM;

    float gradientN = lumaN - lumaM;
    float gradientS = lumaS - lumaM;
    float lumaNN = lumaN + lumaM;
    float lumaSS = lumaS + lumaM;
    bool pairN = abs(gradientN) >= abs(gradientS);
    float gradient = max(abs(gradientN), abs(gradientS));
    if(pairN) lengthSign = -lengthSign;
    float subpixC = FxaaSat(abs(subpixB) * subpixRcpRange);

    float2 posB;
    posB.x = posM.x;
    posB.y = posM.y;
    float2 offNP;
    offNP.x = (!horzSpan) ? 0.0 : fxaaRcpFrame.x;
    offNP.y = ( horzSpan) ? 0.0 : fxaaRcpFrame.y;
    if(!horzSpan) posB.x += lengthSign * 0.5;
    if( horzSpan) posB.y += lengthSign * 0.5;

    float2 posN;
    posN.x = posB.x - offNP.x * FXAA_QUALITY__P0;
    posN.y = posB.y - offNP.y * FXAA_QUALITY__P0;
    float2 posP;
    posP.x = posB.x + offNP.x * FXAA_QUALITY__P0;
    posP.y = posB.y + offNP.y * FXAA_QUALITY__P0;
    float subpixD = ((-2.0)*subpixC) + 3.0;
    float lumaEndN = FxaaLuma(FxaaTexTop(tex, posN));
    float subpixE = subpixC * subpixC;
    float lumaEndP = FxaaLuma(FxaaTexTop(tex, posP));

    if(!pairN) lumaNN = lumaSS;
    float gradientScaled = gradient * 1.0/4.0;
    float lumaMM = lumaM - lumaNN * 0.5;
    float subpixF = subpixD * subpixE;
    bool lumaMLTZero = lumaMM < 0.0;
    lumaEndN -= lumaNN * 0.5;
    lumaEndP -= lumaNN * 0.5;
    bool doneN = abs(lumaEndN) >= gradientScaled;
    bool doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P1;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P1;
    bool doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P1;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P1;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P2;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P2;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P2;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P2;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P3;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P3;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P3;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P3;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P4;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P4;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P4;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P4;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P5;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P5;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P5;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P5;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P6;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P6;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P6;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P6;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P7;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P7;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P7;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P7;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P8;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P8;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P8;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P8;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P9;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P9;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P9;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P9;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P10;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P10;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P10;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P10;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P11;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P11;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P11;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P11;

    if(doneNP) {
    if(!doneN) lumaEndN = FxaaLuma(FxaaTexTop(tex, posN.xy));
    if(!doneP) lumaEndP = FxaaLuma(FxaaTexTop(tex, posP.xy));
    if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
    if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
    doneN = abs(lumaEndN) >= gradientScaled;
    doneP = abs(lumaEndP) >= gradientScaled;
    if(!doneN) posN.x -= offNP.x * FXAA_QUALITY__P12;
    if(!doneN) posN.y -= offNP.y * FXAA_QUALITY__P12;
    doneNP = (!doneN) || (!doneP);
    if(!doneP) posP.x += offNP.x * FXAA_QUALITY__P12;
    if(!doneP) posP.y += offNP.y * FXAA_QUALITY__P12;
    }}}}}}}}}}}

    float dstN = posM.x - posN.x;
    float dstP = posP.x - posM.x;
    if(!horzSpan) dstN = posM.y - posN.y;
    if(!horzSpan) dstP = posP.y - posM.y;

    bool goodSpanN = (lumaEndN < 0.0) != lumaMLTZero;
    float spanLength = (dstP + dstN);
    bool goodSpanP = (lumaEndP < 0.0) != lumaMLTZero;
    float spanLengthRcp = 1.0/spanLength;

    bool directionN = dstN < dstP;
    float dst = min(dstN, dstP);
    bool goodSpan = directionN ? goodSpanN : goodSpanP;
    float subpixG = subpixF * subpixF;
    float pixelOffset = (dst * (-spanLengthRcp)) + 0.5;
    float subpixH = subpixG * fxaaSubpix;

    float pixelOffsetGood = goodSpan ? pixelOffset : 0.0;
    float pixelOffsetSubpix = max(pixelOffsetGood, subpixH);
    if(!horzSpan) posM.x += pixelOffsetSubpix * lengthSign;
    if( horzSpan) posM.y += pixelOffsetSubpix * lengthSign;

    return float4(FxaaTexTop(tex, posM).xyz, lumaM);
}

float4 FxaaPass(float4 FxaaColor, float2 texcoord)
{
    #if(GLSL == 1)
    tex = TextureSampler;
    FxaaColor = FxaaPixelShader(texcoord, TextureSampler, pixelSize.xy, FxaaSubpixMax, FxaaEdgeThreshold, FxaaEdgeThresholdMin);
    #else
    FxaaTex tex;

    tex.tex = Texture;
    tex.smpl = TextureSampler;
    FxaaColor = FxaaPixelShader(texcoord, tex, pixelSize.xy, FxaaSubpixMax, FxaaEdgeThreshold, FxaaEdgeThresholdMin);
    #endif

    return FxaaColor;
}
#endif

/*------------------------------------------------------------------------------
                        [TEXTURE FILTERING FUNCTIONS]
------------------------------------------------------------------------------*/

float BSpline(float x)
{
    float f = x;

    if (f < 0.0)
    {
        f = -f;
    }
    if (f >= 0.0 && f <= 1.0)
    {
        return (2.0 / 3.0) + (0.5) * (f* f * f) - (f*f);
    }
    else if (f > 1.0 && f <= 2.0)
    {
        return 1.0 / 6.0 * pow((2.0 - f), 3.0);
    }
    return 1.0;
}

float CatMullRom(float x)
{
    float b = 0.0;
    float c = 0.5;
    float f = x;

    if (f < 0.0)
    {
        f = -f;
    }
    if (f < 1.0)
    {
        return ((12.0 - 9.0 * b - 6.0 * c) *
                (f * f * f) + (-18.0 + 12.0 * b + 6.0 * c) *
                (f * f) + (6.0 - 2.0 * b)) / 6.0;
    }
    else if (f >= 1.0 && f < 2.0)
    {
        return ((-b - 6.0 * c) * (f * f * f) +
                (6.0 * b + 30.0 * c) *(f *f) +
                (-(12.0 * b) - 48.0 * c) * f +
                8.0 * b + 24.0 * c) / 6.0;
    }
    else
    {
        return 0.0;
    }
}

float Bell(float x)
{
    float f = (x / 2.0) * 1.5;

    if (f > -1.5 && f < -0.5)
    {
        return(0.5 * pow(f + 1.5, 2.0));
    }
    else if (f > -0.5 && f < 0.5)
    {
        return 3.0 / 4.0 - (f * f);
    }
    else if ((f > 0.5 && f < 1.5))
    {
        return(0.5 * pow(f - 1.5, 2.0));
    }
    return 0.0;
}

float Triangular(float x)
{
    x = x / 2.0;

    if (x < 0.0)
    {
        return (x + 1.0);
    }
    else
    {
        return (1.0 - x);
    }
    return 0.0;
}

float Cubic(float coeff)
{
    float4 n = float4(1.0, 2.0, 3.0, 4.0) - coeff;
    float4 s = n * n * n;

    float x = s.x;
    float y = s.y - 4.0 * s.x;
    float z = s.z - 4.0 * s.y + 6.0 * s.x;
    float w = 6.0 - x - y - z;

    return (x + y + z + w) / 4.0;
}

/*------------------------------------------------------------------------------
                       [BILINEAR FILTERING CODE SECTION]
------------------------------------------------------------------------------*/

#if (BILINEAR_FILTERING == 1)
float4 SampleBiLinear(in SamplerState texSample, in float2 texcoord)
{
    float texelSizeX = pixelSize.x;
    float texelSizeY = pixelSize.y;

    int nX = int(texcoord.x * screenSize.x);
    int nY = int(texcoord.y * screenSize.y);

    float2 uvCoord = float2((float(nX) + OffsetAmount) / screenSize.x, (float(nY) + OffsetAmount) / screenSize.y);

    // Take nearest two data in current row.
    float4 SampleA = sample_tex(texSample, uvCoord);
    float4 SampleB = sample_tex(texSample, uvCoord + float2(texelSizeX, 0.0));

    // Take nearest two data in bottom row.
    float4 SampleC = sample_tex(texSample, uvCoord + float2(0.0, texelSizeY));
    float4 SampleD = sample_tex(texSample, uvCoord + float2(texelSizeX, texelSizeY));

    float LX = frac(texcoord.x * screenSize.x); //Get Interpolation factor for X direction.

    // Interpolate in X direction.
    float4 InterpolateA = lerp(SampleA, SampleB, LX); //Top row in X direction.
    float4 InterpolateB = lerp(SampleC, SampleD, LX); //Bottom row in X direction.

    float LY = frac(texcoord.y * screenSize.y); //Get Interpolation factor for Y direction.

    return lerp(InterpolateA, InterpolateB, LY); //Interpolate in Y direction.
}

float4 BiLinearPass(float4 color, float2 texcoord)
{
    float4 bilinear = SampleBiLinear(TextureSampler, texcoord);
    color = lerp(color, bilinear, FilterStrength);

    return color;
}
#endif

/*------------------------------------------------------------------------------
                      [BICUBIC FILTERING CODE SECTION]
------------------------------------------------------------------------------*/

#if (BICUBIC_FILTERING == 1)
float4 BicubicFilter(in SamplerState texSample, in float2 texcoord)
{  
    float texelSizeX = pixelSize.x;
    float texelSizeY = pixelSize.y;

    float4 nSum = float4(0.0, 0.0, 0.0, 0.0);
    float4 nDenom = float4(0.0, 0.0, 0.0, 0.0);

    float a = frac(texcoord.x * screenSize.x);
    float b = frac(texcoord.y * screenSize.y);

    int nX = int(texcoord.x * screenSize.x);
    int nY = int(texcoord.y * screenSize.y);

    float2 uvCoord = float2(float(nX) / screenSize.x + PixelOffset / screenSize.x,
    float(nY) / screenSize.y + PixelOffset / screenSize.y);

    for (int m = -1; m <= 2; m++)
    {
        for (int n = -1; n <= 2; n++)
        {
            float4 Samples = sample_tex(texSample, uvCoord +
            float2(texelSizeX * float(m), texelSizeY * float(n)));

            float vc1 = Interpolation(float(m) - a);
            float4 vecCoeff1 = float4(vc1, vc1, vc1, vc1);

            float vc2 = Interpolation(-(float(n) - b));
            float4 vecCoeff2 = float4(vc2, vc2, vc2, vc2);

            nSum = nSum + (Samples * vecCoeff2 * vecCoeff1);
            nDenom = nDenom + (vecCoeff2 * vecCoeff1);
        }
    }
    return nSum / nDenom;
}

float4 BiCubicPass(float4 color, float2 texcoord)
{
    float4 bicubic = BicubicFilter(TextureSampler, texcoord);
    color = lerp(color, bicubic, BicubicStrength);
    return color;
}
#endif

/*------------------------------------------------------------------------------
                      [GAUSSIAN FILTERING CODE SECTION]
------------------------------------------------------------------------------*/

#if (GAUSSIAN_FILTERING == 1)
float4 GaussianPass(float4 color, float2 texcoord)
{
    if (screenSize.x < 1024 || screenSize.y < 1024)
    {
        pixelSize.x /= 2.0;
        pixelSize.y /= 2.0;
    }
    
    float2 dx = float2(pixelSize.x * GaussianSpread, 0.0);
    float2 dy = float2(0.0, pixelSize.y * GaussianSpread);

    float2 dx2 = 2.0 * dx;
    float2 dy2 = 2.0 * dy;

    float4 gaussian = sample_tex(TextureSampler, texcoord);

    gaussian += sample_tex(TextureSampler, texcoord - dx2 + dy2);
    gaussian += sample_tex(TextureSampler, texcoord - dx + dy2);
    gaussian += sample_tex(TextureSampler, texcoord + dy2);
    gaussian += sample_tex(TextureSampler, texcoord + dx + dy2);
    gaussian += sample_tex(TextureSampler, texcoord + dx2 + dy2);

    gaussian += sample_tex(TextureSampler, texcoord - dx2 + dy);
    gaussian += sample_tex(TextureSampler, texcoord - dx + dy);
    gaussian += sample_tex(TextureSampler, texcoord + dy);
    gaussian += sample_tex(TextureSampler, texcoord + dx + dy);
    gaussian += sample_tex(TextureSampler, texcoord + dx2 + dy);

    gaussian += sample_tex(TextureSampler, texcoord - dx2);
    gaussian += sample_tex(TextureSampler, texcoord - dx);
    gaussian += sample_tex(TextureSampler, texcoord + dx);
    gaussian += sample_tex(TextureSampler, texcoord + dx2);

    gaussian += sample_tex(TextureSampler, texcoord - dx2 - dy);
    gaussian += sample_tex(TextureSampler, texcoord - dx - dy);
    gaussian += sample_tex(TextureSampler, texcoord - dy);
    gaussian += sample_tex(TextureSampler, texcoord + dx - dy);
    gaussian += sample_tex(TextureSampler, texcoord + dx2 - dy);

    gaussian += sample_tex(TextureSampler, texcoord - dx2 - dy2);
    gaussian += sample_tex(TextureSampler, texcoord - dx - dy2);
    gaussian += sample_tex(TextureSampler, texcoord - dy2);
    gaussian += sample_tex(TextureSampler, texcoord + dx - dy2);
    gaussian += sample_tex(TextureSampler, texcoord + dx2 - dy2);

    gaussian /= 25.0;

    color = lerp(color, gaussian, FilterAmount);

    return color;
}
#endif

/*------------------------------------------------------------------------------
                         [BICUBIC SCALER CODE SECTION]
------------------------------------------------------------------------------*/

#if (BICUBLIC_SCALER == 1)
float4 BicubicScaler(in SamplerState tex, in float2 uv, in float2 texSize)
{
    float2 inputSize = float2(1.0/texSize.x, 1.0/texSize.y);

    float2 coord_hg = uv * texSize - 0.5;
    float2 index = floor(coord_hg);
    float2 f = coord_hg - index;

    float4x4 M = matrix4(-1.0, 3.0,-3.0, 1.0, 3.0,-6.0, 3.0, 0.0,
                   -3.0, 0.0, 3.0, 0.0, 1.0, 4.0, 1.0, 0.0);
    M /= 6.0;

    float4 wx = mul(float4(f.x*f.x*f.x, f.x*f.x, f.x, 1.0), M);
    float4 wy = mul(float4(f.y*f.y*f.y, f.y*f.y, f.y, 1.0), M);
    float2 w0 = float2(wx.x, wy.x);
    float2 w1 = float2(wx.y, wy.y);
    float2 w2 = float2(wx.z, wy.z);
    float2 w3 = float2(wx.w, wy.w);

    float2 g0 = w0 + w1;
    float2 g1 = w2 + w3;
    float2 h0 = w1 / g0 - 1.0;
    float2 h1 = w3 / g1 + 1.0;

    float2 coord00 = index + h0;
    float2 coord10 = index + float2(h1.x, h0.y);
    float2 coord01 = index + float2(h0.x, h1.y);
    float2 coord11 = index + h1;

    coord00 = (coord00 + 0.5) * inputSize;
    coord10 = (coord10 + 0.5) * inputSize;
    coord01 = (coord01 + 0.5) * inputSize;
    coord11 = (coord11 + 0.5) * inputSize;

    float4 tex00 = sample_texLevel(tex, coord00, 0);
    float4 tex10 = sample_texLevel(tex, coord10, 0);
    float4 tex01 = sample_texLevel(tex, coord01, 0);
    float4 tex11 = sample_texLevel(tex, coord11, 0);

    tex00 = lerp(tex01, tex00, float4(g0.y, g0.y, g0.y, g0.y));
    tex10 = lerp(tex11, tex10, float4(g0.y, g0.y, g0.y, g0.y));

    float4 res = lerp(tex10, tex00, float4(g0.x, g0.x, g0.x, g0.x));

    return res;
}

float4 BiCubicScalerPass(float4 color, float2 texcoord)
{
    color = BicubicScaler(TextureSampler, texcoord, screenSize);
    return color;
}
#endif

/*------------------------------------------------------------------------------
                         [LANCZOS SCALER CODE SECTION]
------------------------------------------------------------------------------*/

#if (LANCZOS_SCALER == 1)
float3 PixelPos(float xpos, float ypos)
{
    return sample_tex(TextureSampler, float2(xpos, ypos)).rgb;
}

float4 WeightQuad(float x)
{
    #define FIX(c) max(abs(c), 1e-5);
    const float PI = 3.1415926535897932384626433832795;

    float4 weight = FIX(PI * float4(1.0 + x, x, 1.0 - x, 2.0 - x));
    float4 ret = sin(weight) * sin(weight / 2.0) / (weight * weight);

    return ret / dot(ret, float4(1.0, 1.0, 1.0, 1.0));
}

float3 LineRun(float ypos, float4 xpos, float4 linetaps)
{
    return mul(linetaps, matrix4x3(
    PixelPos(xpos.x, ypos),
    PixelPos(xpos.y, ypos),
    PixelPos(xpos.z, ypos),
    PixelPos(xpos.w, ypos)));
}

float4 LanczosScaler(float2 texcoord, float2 inputSize)
{
    float2 stepxy = float2(1.0/inputSize.x, 1.0/inputSize.y);
    float2 pos = texcoord + stepxy;
    float2 f = frac(pos / stepxy);

    float2 xystart = (-2.0 - f) * stepxy + pos;
    float4 xpos = float4(xystart.x,
    xystart.x + stepxy.x,
    xystart.x + stepxy.x * 2.0,
    xystart.x + stepxy.x * 3.0);

    float4 linetaps = WeightQuad(f.x);
    float4 columntaps = WeightQuad(f.y);

    // final sum and weight normalization
    return float4(mul(columntaps, matrix4x3(
    LineRun(xystart.y, xpos, linetaps),
    LineRun(xystart.y + stepxy.y, xpos, linetaps),
    LineRun(xystart.y + stepxy.y * 2.0, xpos, linetaps),
    LineRun(xystart.y + stepxy.y * 3.0, xpos, linetaps))), 1.0);
}

float4 LanczosScalerPass(float4 color, float2 texcoord)
{
    color = LanczosScaler(texcoord, screenSize);
    return color;
}
#endif

/*------------------------------------------------------------------------------
                       [GAMMA CORRECTION CODE SECTION]
------------------------------------------------------------------------------*/

#if (GAMMA_CORRECTION == 1)
float3 RGBGammaToLinear(in float3 color, in float gamma)
{
    color = saturate(color);
    color.r = (color.r <= 0.0404482362771082) ?
    color.r / 12.92 : pow((color.r + 0.055) / 1.055, gamma);
    color.g = (color.g <= 0.0404482362771082) ?
    color.g / 12.92 : pow((color.g + 0.055) / 1.055, gamma);
    color.b = (color.b <= 0.0404482362771082) ?
    color.b / 12.92 : pow((color.b + 0.055) / 1.055, gamma);

    return color;
}

float3 LinearToRGBGamma(in float3 color, in float gamma)
{
    color = saturate(color);
    color.r = (color.r <= 0.00313066844250063) ?
    color.r * 12.92 : 1.055 * pow(color.r, 1.0 / gamma) - 0.055;
    color.g = (color.g <= 0.00313066844250063) ?
    color.g * 12.92 : 1.055 * pow(color.g, 1.0 / gamma) - 0.055;
    color.b = (color.b <= 0.00313066844250063) ?
    color.b * 12.92 : 1.055 * pow(color.b, 1.0 / gamma) - 0.055;

    return color;
}

float4 GammaPass(float4 color, float2 texcoord)
{
    const float GammaConst = 2.233;
    color.rgb = RGBGammaToLinear(color.rgb, GammaConst);
    color.rgb = LinearToRGBGamma(color.rgb, float(Gamma));
    color.a = RGBLuminance(color.rgb);

    return color;
}
#endif

/*------------------------------------------------------------------------------
                       [TEXTURE SHARPEN CODE SECTION]
------------------------------------------------------------------------------*/

#if (TEXTURE_SHARPEN == 1)
float4 SampleBicubic(in SamplerState texSample, in float2 texcoord)
{
    float texelSizeX = pixelSize.x * float(SharpenBias);
    float texelSizeY = pixelSize.y * float(SharpenBias);

    float4 nSum = float4(0.0, 0.0, 0.0, 0.0);
    float4 nDenom = float4(0.0, 0.0, 0.0, 0.0);

    float a = frac(texcoord.x * screenSize.x);
    float b = frac(texcoord.y * screenSize.y);

    int nX = int(texcoord.x * screenSize.x);
    int nY = int(texcoord.y * screenSize.y);

    float2 uvCoord = float2(float(nX) / screenSize.x, float(nY) / screenSize.y);

    for (int m = -1; m <= 2; m++)
    {
        for (int n = -1; n <= 2; n++)
        {
            float4 Samples = sample_tex(texSample, uvCoord +
            float2(texelSizeX * float(m), texelSizeY * float(n)));

            float vc1 = Cubic(float(m) - a);
            float4 vecCoeff1 = float4(vc1, vc1, vc1, vc1);

            float vc2 = Cubic(-(float(n) - b));
            float4 vecCoeff2 = float4(vc2, vc2, vc2, vc2);

            nSum = nSum + (Samples * vecCoeff2 * vecCoeff1);
            nDenom = nDenom + (vecCoeff2 * vecCoeff1);
        }
    }
    return nSum / nDenom;
}

float4 TexSharpenPass(float4 color, float2 texcoord)
{
    float3 calcSharpen = lumCoeff * float(SharpenStrength);

    float4 blurredColor = SampleBicubic(TextureSampler, texcoord);
    float3 sharpenedColor = (color.rgb - blurredColor.rgb);

    float sharpenLuma = dot(sharpenedColor, calcSharpen);
    sharpenLuma = clamp(sharpenLuma, -float(SharpenClamp), float(SharpenClamp));

    color.rgb = color.rgb + sharpenLuma;
    color.a = RGBLuminance(color.rgb);

    #if (DebugSharpen == 1)
        color = saturate(0.5f + (sharpenLuma * 4)).rrrr;
    #endif

    return saturate(color);
}
#endif

/*------------------------------------------------------------------------------
                          [VIBRANCE CODE SECTION]
------------------------------------------------------------------------------*/

#if (PIXEL_VIBRANCE == 1)
float4 VibrancePass(float4 color, float2 texcoord)
{
    #if (GLSL == 1)
    float3 luma = float3(RGBLuminance(color.rgb));
    #else
    float luma = RGBLuminance(color.rgb);
    #endif

    float colorMax = max(color.r, max(color.g, color.b));
    float colorMin = min(color.r, min(color.g, color.b));

    float colorSaturation = colorMax - colorMin;

    color.rgb = lerp(luma, color.rgb, (1.0 + (Vibrance * (1.0 - (sign(Vibrance) * colorSaturation)))));
    color.a = RGBLuminance(color.rgb);

    return saturate(color); //Debug: return colorSaturation.xxxx;
}
#endif

/*------------------------------------------------------------------------------
                        [BLENDED BLOOM CODE SECTION]
------------------------------------------------------------------------------*/

#if (BLENDED_BLOOM == 1)
float3 BlendAddLight(in float3 color, in float3 bloom)
{
    return saturate(color + bloom);
}

float3 BlendScreen(in float3 color, in float3 bloom)
{
    return (color + bloom) - (color * bloom);
}

float3 BlendLuma(in float3 color, in float3 bloom)
{
    return lerp((color * bloom), (1.0 - ((1.0 - color) * (1.0 - bloom))), RGBLuminance(color + bloom));
}

float3 BlendGlow(in float3 color, in float3 bloom)
{
    float3 glow = smoothstep(0.0, 1.0, color);
    glow = lerp((color + bloom) - (color * bloom), (bloom + bloom) - (bloom * bloom), glow);

    return glow;
}

float3 BlendOverlay(in float3 color, in float3 bloom)
{
    float3 overlay = step(0.5, color);
    overlay = lerp((color * bloom * 2.0), (1.0 - (2.0 * (1.0 - color) * (1.0 - bloom))), overlay);

    return overlay;
}

float4 BrightPassFilter(in float4 color)
{
    return float4(color.rgb * pow(abs(max(color.r, max(color.g, color.b))), float(BloomCutoff)), color.a);
}

float4 PyramidFilter(in SamplerState tex, in float2 texcoord, in float2 width)
{
    float4 color = sample_tex(tex, texcoord + float2(0.5, 0.5) * width);
    color += sample_tex(tex, texcoord + float2(-0.5, 0.5) * width);
    color += sample_tex(tex, texcoord + float2(0.5, -0.5) * width);
    color += sample_tex(tex, texcoord + float2(-0.5, -0.5) * width);
    color *= 0.25;

    return color;
}

float3 BloomCorrection(float3 color)
{
    float X = 1.0 / (1.0 + exp(float(BloomReds) / 2.0));
    float Y = 1.0 / (1.0 + exp(float(BloomGreens) / 2.0));
    float Z = 1.0 / (1.0 + exp(float(BloomBlues) / 2.0));

    color.r = (1.0 / (1.0 + exp(float(-BloomReds) * (color.r - 0.5))) - X) / (1.0 - 2.0 * X);
    color.g = (1.0 / (1.0 + exp(float(-BloomGreens) * (color.g - 0.5))) - Y) / (1.0 - 2.0 * Y);
    color.b = (1.0 / (1.0 + exp(float(-BloomBlues) * (color.b - 0.5))) - Z) / (1.0 - 2.0 * Z);

    return color;
}

float4 BloomPass(float4 color, float2 texcoord)
{
    float defocus = 1.25;
    float anflare = 4.00;

    color = BrightPassFilter(color);
    float4 bloom = PyramidFilter(TextureSampler, texcoord, invDefocus * defocus);

    float2 dx = float2(invDefocus.x * float(BloomWidth), 0.0);
    float2 dy = float2(0.0, invDefocus.y * float(BloomWidth));

    float2 mdx = mul(2.0, dx);
    float2 mdy = mul(2.0, dy);

    float4 bloomBlend = bloom * 0.22520613262190495;

    bloomBlend += 0.002589001911021066 * sample_tex(TextureSampler, texcoord - mdx + mdy);
    bloomBlend += 0.010778807494659370 * sample_tex(TextureSampler, texcoord - dx + mdy);
    bloomBlend += 0.024146616900339800 * sample_tex(TextureSampler, texcoord + mdy);
    bloomBlend += 0.010778807494659370 * sample_tex(TextureSampler, texcoord + dx + mdy);
    bloomBlend += 0.002589001911021066 * sample_tex(TextureSampler, texcoord + mdx + mdy);

    bloomBlend += 0.010778807494659370 * sample_tex(TextureSampler, texcoord - mdx + dy);
    bloomBlend += 0.044875475183061630 * sample_tex(TextureSampler, texcoord - dx + dy);
    bloomBlend += 0.100529757860782610 * sample_tex(TextureSampler, texcoord + dy);
    bloomBlend += 0.044875475183061630 * sample_tex(TextureSampler, texcoord + dx + dy);
    bloomBlend += 0.010778807494659370 * sample_tex(TextureSampler, texcoord + mdx + dy);

    bloomBlend += 0.024146616900339800 * sample_tex(TextureSampler, texcoord - mdx);
    bloomBlend += 0.100529757860782610 * sample_tex(TextureSampler, texcoord - dx);
    bloomBlend += 0.100529757860782610 * sample_tex(TextureSampler, texcoord + dx);
    bloomBlend += 0.024146616900339800 * sample_tex(TextureSampler, texcoord + mdx);

    bloomBlend += 0.010778807494659370 * sample_tex(TextureSampler, texcoord - mdx - dy);
    bloomBlend += 0.044875475183061630 * sample_tex(TextureSampler, texcoord - dx - dy);
    bloomBlend += 0.100529757860782610 * sample_tex(TextureSampler, texcoord - dy);
    bloomBlend += 0.044875475183061630 * sample_tex(TextureSampler, texcoord + dx - dy);
    bloomBlend += 0.010778807494659370 * sample_tex(TextureSampler, texcoord + mdx - dy);

    bloomBlend += 0.002589001911021066 * sample_tex(TextureSampler, texcoord - mdx - mdy);
    bloomBlend += 0.010778807494659370 * sample_tex(TextureSampler, texcoord - dx - mdy);
    bloomBlend += 0.024146616900339800 * sample_tex(TextureSampler, texcoord - mdy);
    bloomBlend += 0.010778807494659370 * sample_tex(TextureSampler, texcoord + dx - mdy);
    bloomBlend += 0.002589001911021066 * sample_tex(TextureSampler, texcoord + mdx - mdy);
    bloomBlend = lerp(color, bloomBlend, float(BlendStrength));

    bloom.rgb = BloomType(bloom.rgb, bloomBlend.rgb);
    bloom.rgb = BloomCorrection(bloom.rgb);

    color.a = RGBLuminance(color.rgb);
    bloom.a = RGBLuminance(bloom.rgb);
    bloom.a *= anflare;

    color = lerp(color, bloom, float(BloomStrength));

    return color;
}
#endif
/*------------------------------------------------------------------------------
                 [COLOR CORRECTION/TONE MAPPING CODE SECTION]
------------------------------------------------------------------------------*/

float3 ScaleLuma(in float3 L)
{
    const float W = 1.00;   // Linear White Point Value
    const float K = 1.12;   // Scale

    return (1.0 + K * L / (W * W)) * L / (L + K);
}

float3 FilmicTonemap(in float3 color)
{
    float3 Q = color.xyz;

    float A = 0.10;
    float B = float(BlackLevels);
    float C = 0.10;
    float D = float(ToneAmount);
    float E = 0.02;
    float F = 0.30;
    float W = float(WhitePoint);

    float3 numerator = ((Q*(A*Q + C*B) + D*E) / (Q*(A*Q + B) + D*F)) - E / F;
    float denominator = ((W*(A*W + C*B) + D*E) / (W*(A*W + B) + D*F)) - E / F;

    color.xyz = numerator / denominator;

    return saturate(color);
}

float3 CrossShift(in float3 color)
{
    float3 colMood;

    float2 CrossMatrix[3] = {
    float2 (0.96, 0.04),
    float2 (0.99, 0.01),
    float2 (0.97, 0.03), };

    colMood.r = float(RedShift) * CrossMatrix[0].x + CrossMatrix[0].y;
    colMood.g = float(GreenShift) * CrossMatrix[1].x + CrossMatrix[1].y;
    colMood.b = float(BlueShift) * CrossMatrix[2].x + CrossMatrix[2].y;

    float fLum = RGBLuminance(color.rgb);

    #if (GLSL == 1)
    // Is HLSL float3(x) equivalent to float3(x,x,x) ? (Yes)
    colMood = lerp(float3(0.0), colMood, saturate(fLum * 2.0));
    colMood = lerp(colMood, float3(1.0), saturate(fLum - 0.5) * 2.0);
    #else
    colMood = lerp(0.0, colMood, saturate(fLum * 2.0));
    colMood = lerp(colMood, 1.0, saturate(fLum - 0.5) * 2.0);
    #endif
    float3 colOutput = lerp(color, colMood, saturate(fLum * float(ShiftRatio)));

    return colOutput;
}

float3 ColorCorrection(float3 color)
{
    float X = 1.0 / (1.0 + exp(float(RedCurve) / 2.0));
    float Y = 1.0 / (1.0 + exp(float(GreenCurve) / 2.0));
    float Z = 1.0 / (1.0 + exp(float(BlueCurve) / 2.0));

    color.r = (1.0 / (1.0 + exp(float(-RedCurve) * (color.r - 0.5))) - X) / (1.0 - 2.0 * X);
    color.g = (1.0 / (1.0 + exp(float(-GreenCurve) * (color.g - 0.5))) - Y) / (1.0 - 2.0 * Y);
    color.b = (1.0 / (1.0 + exp(float(-BlueCurve) * (color.b - 0.5))) - Z) / (1.0 - 2.0 * Z);

    return saturate(color);
}

float4 TonemapPass(float4 color, float2 texcoord)
{
    const float delta = 0.001f;
    const float wpoint = pow(1.002f, 2.0f);

    color.rgb = ScaleLuma(color.rgb);

    if (CorrectionPalette == 1) { color.rgb = ColorCorrection(color.rgb); }
    if (FilmicProcess == 1) { color.rgb = CrossShift(color.rgb); }
    if (TonemapType == 1) { color.rgb = FilmicTonemap(color.rgb); }

    // RGB -> XYZ conversion
    const float3x3 RGB2XYZ = matrix3(0.4124564, 0.3575761, 0.1804375,
                               0.2126729, 0.7151522, 0.0721750,
                               0.0193339, 0.1191920, 0.9503041);

    float3 XYZ = mul(RGB2XYZ, color.rgb);

    // XYZ -> Yxy conversion
    float3 Yxy;

    Yxy.r = XYZ.g;                              // copy luminance Y
    Yxy.g = XYZ.r / (XYZ.r + XYZ.g + XYZ.b);    // x = X / (X + Y + Z)
    Yxy.b = XYZ.g / (XYZ.r + XYZ.g + XYZ.b);    // y = Y / (X + Y + Z)

    if (CorrectionPalette == 2) { Yxy.rgb = ColorCorrection(Yxy.rgb); }

    // (Lp) Map average luminance to the middlegrey zone by scaling pixel luminance
    float Lp = Yxy.r * float(Exposure) / (float(Luminance) + delta);

    // (Ld) Scale all luminance within a displayable range of 0 to 1
    Yxy.r = (Lp * (1.0 + Lp / wpoint)) / (1.0 + Lp);

    if (TonemapType == 2) { Yxy.r = FilmicTonemap(Yxy.rgb).r; }

    // Yxy -> XYZ conversion
    XYZ.r = Yxy.r * Yxy.g / Yxy.b;                  // X = Y * x / y
    XYZ.g = Yxy.r;                                  // copy luminance Y
    XYZ.b = Yxy.r * (1.0 - Yxy.g - Yxy.b) / Yxy.b;  // Z = Y * (1-x-y) / y

    if (CorrectionPalette == 3) { XYZ.rgb = ColorCorrection(XYZ.rgb); }

    // XYZ -> RGB conversion
    const float3x3 XYZ2RGB = matrix3(3.2404542,-1.5371385,-0.4985314,
                              -0.9692660, 1.8760108, 0.0415560,
                               0.0556434,-0.2040259, 1.0572252);

    color.rgb = mul(XYZ2RGB, XYZ);
    color.a = RGBLuminance(color.rgb);

    return color;
}

/*------------------------------------------------------------------------------
                       [S-CURVE CONTRAST CODE SECTION]
------------------------------------------------------------------------------*/

#if (S_CURVE_CONTRAST == 1)
float4 ContrastPass(float4 color, float2 texcoord)
{
    float CurveBlend = CurvesContrast;

    #if (CurveType != 2)
    #if (GLSL == 1)
    float3 luma = float3(RGBLuminance(color.rgb));
    #else
    float3 luma = (float3)RGBLuminance(color.rgb);
    #endif
    float3 chroma = color.rgb - luma;
    #endif

    #if (CurveType == 2)
    float3 x = color.rgb;
    #elif (CurveType == 1)
    float3 x = chroma;
    x = x * 0.5 + 0.5;
    #else
    float3 x = luma;
    #endif

    //S-Curve - Cubic Bezier spline
    float3 a = float3(0.00, 0.00, 0.00);    //start point
    float3 b = float3(0.25, 0.25, 0.25);    //control point 1
    float3 c = float3(0.80, 0.80, 0.80);    //control point 2
    float3 d = float3(1.00, 1.00, 1.00);    //endpoint

    float3 ab = lerp(a, b, x);              //point between a and b (green)
    float3 bc = lerp(b, c, x);              //point between b and c (green)
    float3 cd = lerp(c, d, x);              //point between c and d (green)
    float3 abbc = lerp(ab, bc, x);          //point between ab and bc (blue)
    float3 bccd = lerp(bc, cd, x);          //point between bc and cd (blue)
    float3 dest = lerp(abbc, bccd, x);      //point on the bezier-curve (black)

    x = dest;

    #if (CurveType == 0) //Only Luma
    x = lerp(luma, x, CurveBlend);
    color.rgb = x + chroma;
    #elif (CurveType == 1) //Only Chroma
    x = x * 2 - 1;
    float3 LColor = luma + x;
    color.rgb = lerp(color.rgb, LColor, CurveBlend);
    #elif (CurveType == 2) //Both Luma and Chroma
    float3 LColor = x;
    color.rgb = lerp(color.rgb, LColor, CurveBlend);
    #endif

    color.a = RGBLuminance(color.rgb);

    return saturate(color);
}
#endif

/*------------------------------------------------------------------------------
                       [CEL SHADING CODE SECTION]
------------------------------------------------------------------------------*/

#if (CEL_SHADING == 1)
float3 GetYUV(float3 RGB)
{
    const float3x3 RGB2YUV = matrix3(0.2126, 0.7152, 0.0722,
                              -0.09991,-0.33609, 0.436,
                               0.615, -0.55861, -0.05639);

    return mul(RGB2YUV, RGB);
}

float3 GetRGB(float3 YUV)
{
    const float3x3 YUV2RGB = matrix3(1.000, 0.000, 1.28033,
                               1.000,-0.21482,-0.38059,
                               1.000, 2.12798, 0.000);

    return mul(YUV2RGB, YUV);
}

float4 CelPass(float4 color, float2 texcoord)
{   
    float3 yuv;
    float3 sum = color.rgb;

    const int NUM = 9;
    const float2 RoundingOffset = float2(0.25, 0.25);
    const float3 thresholds = float3(9.0, 8.0, 6.0);

    float lum[NUM];
    float3 col[NUM];
    float2 set[NUM] = {
    float2(-0.0078125, -0.0078125),
    float2(0.00, -0.0078125),
    float2(0.0078125, -0.0078125),
    float2(-0.0078125, 0.00),
    float2(0.00, 0.00),
    float2(0.0078125, 0.00),
    float2(-0.0078125, 0.0078125),
    float2(0.00, 0.0078125),
    float2(0.0078125, 0.0078125) };

    for (int i = 0; i < NUM; i++)
    {
        col[i] = sample_tex(TextureSampler, texcoord + set[i] * RoundingOffset).rgb;

        #if (ColorRounding == 1)
        col[i].r = round(col[i].r * thresholds.r) / thresholds.r;
        col[i].g = round(col[i].g * thresholds.g) / thresholds.g;
        col[i].b = round(col[i].b * thresholds.b) / thresholds.b;
        #endif

        lum[i] = RGBLuminance(col[i].xyz);
        yuv = GetYUV(col[i]);

        #if (UseYuvLuma == 0)
        yuv.r = round(yuv.r * thresholds.r) / thresholds.r;
        #else
        yuv.r = saturate(round(yuv.r * lum[i]) / thresholds.r + lum[i]);
        #endif
        
        yuv = GetRGB(yuv);
        sum += yuv;
    }

    float3 shadedColor = (sum / NUM);
    float2 pixel = float2(pixelSize.x * EdgeThickness, pixelSize.y * EdgeThickness);

    float edgeX = dot(sample_tex(TextureSampler, texcoord + pixel).rgb, lumCoeff);
    edgeX = dot(float4(sample_tex(TextureSampler, texcoord - pixel).rgb, edgeX), float4(lumCoeff, -1.0));

    float edgeY = dot(sample_tex(TextureSampler, texcoord + float2(pixel.x, -pixel.y)).rgb, lumCoeff);
    edgeY = dot(float4(sample_tex(TextureSampler, texcoord + float2(-pixel.x, pixel.y)).rgb, edgeY), float4(lumCoeff, -1.0));

    float edge = dot(float2(edgeX, edgeY), float2(edgeX, edgeY));

    #if (PaletteType == 1)
        color.rgb = lerp(color.rgb, color.rgb + pow(edge, EdgeFilter) * -EdgeStrength, EdgeStrength);
    #elif (PaletteType == 2)
        color.rgb = lerp(color.rgb + pow(edge, EdgeFilter) * -EdgeStrength, shadedColor, 0.30);
    #elif (PaletteType == 3)
        color.rgb = lerp(shadedColor + edge * -EdgeStrength, pow(edge, EdgeFilter) * -EdgeStrength + color.rgb, 0.5);
    #endif

    color.a = RGBLuminance(color.rgb);

    return saturate(color);
}
#endif

/*------------------------------------------------------------------------------
                      [COLOR GRADING CODE SECTION]
------------------------------------------------------------------------------*/

#if (COLOR_GRADING == 1)
float RGBCVtoHUE(float3 RGB, float C, float V)
{
    float3 Delta = (V - RGB) / C;

    Delta.rgb -= Delta.brg;
    Delta.rgb += float3(2.0, 4.0, 6.0);
    Delta.brg = step(V, RGB) * Delta.brg;

    float H;
    H = max(Delta.r, max(Delta.g, Delta.b));
    return frac(H / 6);
}

float3 RGBtoHSV(float3 RGB)
{
    float3 HSV = float3(0.0, 0.0, 0.0);
    HSV.z = max(RGB.r, max(RGB.g, RGB.b));
    float M = min(RGB.r, min(RGB.g, RGB.b));
    float C = HSV.z - M;

    if (C != 0)
    {
        HSV.x = RGBCVtoHUE(RGB, C, HSV.z);
        HSV.y = C / HSV.z;
    }

    return HSV;
}

float3 HUEtoRGB(float H)
{
    float R = abs(H * 6 - 3) - 1;
    float G = 2 - abs(H * 6 - 2);
    float B = 2 - abs(H * 6 - 4);

    return saturate(float3(R, G, B));
}

float3 HSVtoRGB(float3 HSV)
{
    float3 RGB = HUEtoRGB(HSV.x);
    return ((RGB - 1) * HSV.y + 1) * HSV.z;
}

float3 HSVComplement(float3 HSV)
{
    float3 complement = HSV;
    complement.x -= 0.5;

    if (complement.x < 0.0) { complement.x += 1.0; }
    return(complement);
}

float HueLerp(float h1, float h2, float v)
{
    float d = abs(h1 - h2);

    if (d <= 0.5)
    { return lerp(h1, h2, v); }
    else if (h1 < h2)
    { return frac(lerp((h1 + 1.0), h2, v)); }
    else
    { return frac(lerp(h1, (h2 + 1.0), v)); }
}

float4 ColorGrading(float4 color, float2 texcoord)
{
    float3 guide = float3(RedGrading, GreenGrading, BlueGrading);
    float amount = GradingStrength;
    float correlation = Correlation;
    float concentration = 2.00;

    float3 colorHSV = RGBtoHSV(color.rgb);
    float3 huePoleA = RGBtoHSV(guide);
    float3 huePoleB = HSVComplement(huePoleA);

    float dist1 = abs(colorHSV.x - huePoleA.x); if (dist1 > 0.5) dist1 = 1.0 - dist1;
    float dist2 = abs(colorHSV.x - huePoleB.x); if (dist2 > 0.5) dist2 = 1.0 - dist2;

    float descent = smoothstep(0.0, correlation, colorHSV.y);

    float3 HSVColor = colorHSV;

    if (dist1 < dist2)
    {
        float c = descent * amount * (1.0 - pow((dist1 * 2.0), 1.0 / concentration));
        HSVColor.x = HueLerp(colorHSV.x, huePoleA.x, c);
        HSVColor.y = lerp(colorHSV.y, huePoleA.y, c);
    }
    else
    {
        float c = descent * amount * (1.0 - pow((dist2 * 2.0), 1.0 / concentration));
        HSVColor.x = HueLerp(colorHSV.x, huePoleB.x, c);
        HSVColor.y = lerp(colorHSV.y, huePoleB.y, c);
    }

    color.rgb = HSVtoRGB(HSVColor);
    color.a = RGBLuminance(color.rgb);

    return saturate(color);
}
#endif

/*------------------------------------------------------------------------------
                           [SCANLINES CODE SECTION]
------------------------------------------------------------------------------*/

#if (SCANLINES == 1)
float4 ScanlinesPass(float4 color, float2 texcoord, float4 fragcoord)
{
    float4 intensity;
    
    #if (GLSL == 1)
    fragcoord = gl_FragCoord;
    #endif

    #if (ScanlineType == 0)
    if (frac(fragcoord.y * 0.25) > ScanlineScale)
    #elif (ScanlineType == 1)
    if (frac(fragcoord.x * 0.25) > ScanlineScale)
    #elif (ScanlineType == 2)
    if (frac(fragcoord.x * 0.25) > ScanlineScale && frac(fragcoord.y * 0.5) > ScanlineScale)
    #endif
    {
        intensity = float4(0.0, 0.0, 0.0, 0.0);
    }
    else
    {
        intensity = smoothstep(0.2, ScanlineBrightness, color) + normalize(float4(color.xyz, RGBLuminance(color.xyz)));
    }

    float level = (4.0 - texcoord.x) * ScanlineIntensity;

    color = intensity * (0.5 - level) + color * 1.1;

    return color;
}
#endif

/*------------------------------------------------------------------------------
                          [VIGNETTE CODE SECTION]
------------------------------------------------------------------------------*/

#if (VIGNETTE == 1)
float4 VignettePass(float4 color, float2 texcoord)
{
    const float2 VignetteCenter = float2(0.500, 0.500);
    float2 tc = texcoord - VignetteCenter;

    tc *= float2((2560.0 / 1440.0), VignetteRatio);
    tc /= VignetteRadius;

    float v = dot(tc, tc);

    color.rgb *= (1.0 + pow(v, VignetteSlope * 0.25) * -VignetteAmount);

    return color;
}
#endif

/*------------------------------------------------------------------------------
                      [SUBPIXEL DITHERING CODE SECTION]
------------------------------------------------------------------------------*/

#if (DITHERING == 1)
float4 DitherPass(float4 color, float2 texcoord)
{
    float ditherSize = 2.0;
    float ditherBits = 8.0;

    #if DitherMethod == 2 //random subpixel dithering

    float seed = dot(texcoord, float2(12.9898, 78.233));
    float sine = sin(seed);
    float noise = frac(sine * 43758.5453 + texcoord.x);

    float ditherShift = (1.0 / (pow(2.0, ditherBits) - 1.0));
    float ditherHalfShift = (ditherShift * 0.5);
    ditherShift = ditherShift * noise - ditherHalfShift;

    color.rgb += float3(-ditherShift, ditherShift, -ditherShift);

    #else //Ordered dithering

    float gridPosition = frac(dot(texcoord, (screenSize / ditherSize)) + (0.5 / ditherSize));
    float ditherShift = (0.75) * (1.0 / (pow(2, ditherBits) - 1.0));

    float3 RGBShift = float3(ditherShift, -ditherShift, ditherShift);
    RGBShift = lerp(2.0 * RGBShift, -2.0 * RGBShift, gridPosition);

    color.rgb += RGBShift;
    #endif

    color.a = RGBLuminance(color.rgb);

    return color;
}
#endif

/*------------------------------------------------------------------------------
                           [PX BORDER CODE SECTION]
------------------------------------------------------------------------------*/

float4 BorderPass(float4 colorInput, float2 tex)
{
    float3 border_color_float = BorderColor / 255.0;

    float2 border = (_rcpFrame.xy * BorderWidth);
    float2 within_border = saturate((-tex * tex + tex) - (-border * border + border));

    #if (GLSL == 1)
    // FIXME GLSL any only support bvec so try to mix it with notEqual
    bvec2 cond = notEqual( within_border, vec2(0.0f) );
    colorInput.rgb = all(cond) ? colorInput.rgb : border_color_float;
    #else
    colorInput.rgb = all(within_border) ? colorInput.rgb : border_color_float;
    #endif

    return colorInput;

}

/*------------------------------------------------------------------------------
                     [MAIN() & COMBINE PASS CODE SECTION]
------------------------------------------------------------------------------*/

#if (GLSL == 1)
void ps_main()
#else
PS_OUTPUT ps_main(VS_OUTPUT input)
#endif
{
    #if (GLSL == 1)
    float2 texcoord = PSin.t;
    float4 position = PSin.p;
    float4 color = texture(TextureSampler, texcoord);
    #else
    PS_OUTPUT output;

    float2 texcoord = input.t;
    float4 position = input.p;
    float4 color = sample_tex(TextureSampler, texcoord);
    #endif

    #if (BILINEAR_FILTERING == 1)
        color = BiLinearPass(color, texcoord);
    #endif

    #if (GAUSSIAN_FILTERING == 1)
        color = GaussianPass(color, texcoord);
    #endif

    #if (BICUBIC_FILTERING == 1)
        color = BiCubicPass(color, texcoord);
    #endif

    #if (BICUBLIC_SCALER == 1)
        color = BiCubicScalerPass(color, texcoord);
    #endif

    #if (LANCZOS_SCALER == 1)
        color = LanczosScalerPass(color, texcoord);
    #endif

    #if (UHQ_FXAA == 1)
        color = FxaaPass(color, texcoord);
    #endif

    #if (GAMMA_CORRECTION == 1)
        color = GammaPass(color, texcoord);
    #endif

    #if (TEXTURE_SHARPEN == 1)
        color = TexSharpenPass(color, texcoord);
    #endif

    #if (CEL_SHADING == 1)
        color = CelPass(color, texcoord);
    #endif

    #if (SCANLINES == 1)
        color = ScanlinesPass(color, texcoord, position);
    #endif

    #if (BLENDED_BLOOM == 1)
        color = BloomPass(color, texcoord);
    #endif

    #if (SCENE_TONEMAPPING == 1)
        color = TonemapPass(color, texcoord);
    #endif

    #if (PIXEL_VIBRANCE == 1)
        color = VibrancePass(color, texcoord);
    #endif

    #if (COLOR_GRADING == 1)
        color = ColorGrading(color, texcoord);
    #endif

    #if (S_CURVE_CONTRAST == 1)
        color = ContrastPass(color, texcoord);
    #endif

    #if (VIGNETTE == 1)
        color = VignettePass(color, texcoord);
    #endif

    #if (PX_BORDER == 1)
        color = BorderPass(color, texcoord);
    #endif
    
    #if (DITHERING == 1)
        color = DitherPass(color, texcoord);
    #endif

    #if (GLSL == 1)
    SV_Target0 = color;
    #else
    output.c = color;

    return output;
    #endif
}
