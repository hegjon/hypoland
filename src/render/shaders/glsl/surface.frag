#version 100
#define ALLOW_INCLUDES
#extension GL_ARB_shading_language_include : enable

#include "defines.h"

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
varying vec2           v_texcoord;
uniform sampler2D tex;
#if USE_BLUR
uniform vec2      uvSize;
uniform vec2      uvOffset;
uniform sampler2D blurredBG;
uniform float     blurAlpha;
#endif
#if USE_BLUR_MATTE
uniform sampler2D blurAlphaMatte;
#endif

uniform float alpha;

#if USE_DISCARD
uniform bool  discardOpaque;
uniform bool  discardAlpha;
uniform float discardAlphaValue;
#endif

#if USE_TINT
uniform vec3 tint;
#endif

#if USE_ROUNDING
uniform float radius;
uniform float roundingPower;
uniform vec2  topLeft;
uniform vec2  fullSize;
#include "rounding.glsl"
#else
const float radius        = 0.0;
const float roundingPower = 2.0;
#endif

void main() {
#if USE_RGBA
    vec4 pixColor = texture2D(tex, v_texcoord);
#else
    vec4 pixColor = vec4(texture2D(tex, v_texcoord).rgb, 1.0);
#endif
#if USE_BLUR_MATTE
    float blurAlphaMask = clamp(texture2D(blurAlphaMatte, v_texcoord).r, 0.0, 1.0);
#endif

#if USE_DISCARD && !USE_BLUR
    if (discardOpaque && pixColor.a * alpha == 1.0)
        discard;

    if (discardAlpha && pixColor.a <= discardAlphaValue)
        discard;
#endif

#if USE_TINT
    pixColor.rgb = pixColor.rgb * tint;
#endif

#if USE_ROUNDING
    pixColor = rounding(pixColor, radius, roundingPower, topLeft, fullSize);
#endif
    pixColor *= alpha;
#if USE_BLUR
    vec2 blurUV = v_texcoord * uvSize + uvOffset;
#if USE_BLUR_MATTE
    float pixBlurAlphaMask = blurAlphaMask * blurAlpha;
#if USE_DISCARD
    if (discardAlpha && pixColor.a <= discardAlphaValue)
        pixBlurAlphaMask = 0.0;
#endif
    vec3 blurredPixColor = texture2D(blurredBG, blurUV).rgb;
#if USE_BLUR_PROPORTIONAL
    float blurredPixT     = 1.0 - pixColor.a;
    float blurredPixAlpha = 1.0 - blurredPixT * blurredPixT * blurredPixT;
#else
    float blurredPixAlpha = 1.0;
#endif
    float pixBlurBgAlpha = (1.0 - pixColor.a) * pixBlurAlphaMask * blurredPixAlpha;
    pixColor             = vec4(pixColor.rgb + blurredPixColor * pixBlurBgAlpha, pixColor.a + pixBlurBgAlpha);
#else
#if USE_BLUR_ALPHA_MASK
    if (pixColor.a <= 0.0)
        discard;
#endif
#if USE_DISCARD
    float pixBlurAlphaMask = discardAlpha && (pixColor.a <= discardAlphaValue) ? 0.0 : 1.0;
#else
    float pixBlurAlphaMask = 1.0;
#endif
    vec3 blurredPixColor = texture2D(blurredBG, blurUV).rgb;
#if USE_BLUR_PROPORTIONAL
    float blurredPixT     = 1.0 - pixColor.a;
    float blurredPixAlpha = 1.0 - blurredPixT * blurredPixT * blurredPixT;
#else
    float blurredPixAlpha = 1.0;
#endif
    float pixBlurBgAlpha = (1.0 - pixColor.a) * pixBlurAlphaMask * blurredPixAlpha;
    pixColor             = vec4(pixColor.rgb + blurredPixColor * pixBlurBgAlpha, pixColor.a + pixBlurBgAlpha);
#endif
#endif

    gl_FragColor = pixColor;
}
