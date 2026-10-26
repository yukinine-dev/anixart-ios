// "Режим улучшения видео +", ported from the APK's AnixAnime4KShaderProgram.
//
// The Android build runs this as a GLSL ExoPlayer effect; this is the same
// algorithm as a Core Image kernel so it can sit in an AVPlayerItem's video
// composition. The maths is unchanged -- an Anime4K-style directional deblur
// driven by a luma Sobel, then an adaptive unsharp mask, then a guard that
// backs both off where they would invent detail.
//
// Compiled with -fcikernel / -cikernel (see project.yml); the result is loaded
// from the target's default.metallib by VideoEnhanceFilter.

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

namespace {

inline float get_luma(float4 rgba) {
    return dot(float4(0.299, 0.587, 0.114, 0.0), rgba);
}

/// The polynomial Anime4K uses to turn a Sobel norm into a blend weight.
inline float anime4k_power_function(float x) {
    const float P5 =  11.68129591;
    const float P4 = -42.46906057;
    const float P3 =  60.28286266;
    const float P2 = -41.84451327;
    const float P1 =  14.05517353;
    const float P0 =  -1.081521930;

    float x2 = x * x;
    float x3 = x2 * x;
    float x4 = x2 * x2;
    float x5 = x2 * x3;

    return P5 * x5 + P4 * x4 + P3 * x3 + P2 * x2 + P1 * x + P0;
}

inline float2 initialLumaGradients(coreimage::sampler src, float2 pos, float2 d) {
    float l = get_luma(src.sample(pos + float2(-d.x, 0.0)));
    float c = get_luma(src.sample(pos));
    float r = get_luma(src.sample(pos + float2( d.x, 0.0)));

    float xgrad = r - l;
    float ygrad = l + c + c + r;

    return float2(xgrad, ygrad);
}

inline float dValue(float2 initialGrad, float refineStrength, float refineBias) {
    float tx = initialGrad.x;
    float cx = initialGrad.x;
    float bx = initialGrad.x;

    float ty = initialGrad.y;
    float by = initialGrad.y;

    float xgrad = (tx + cx + cx + bx);
    float ygrad = (-ty + by);

    float sobelNorm = clamp(sqrt(xgrad * xgrad + ygrad * ygrad), 0.0, 1.0);

    return clamp(anime4k_power_function(sobelNorm) * refineStrength + refineBias, 0.0, 1.0);
}

inline float2 normalizeGradients(float2 dirGrad) {
    float norm = sqrt(dirGrad.x * dirGrad.x + dirGrad.y * dirGrad.y);
    if (norm <= 0.001) {
        return float2(0.0, 0.0);
    }
    return dirGrad / norm;
}

inline float4 advancedDeblur(coreimage::sampler src, float2 pos, float2 d, float sharpeningStrength) {
    float4 center = src.sample(pos);

    float4 top    = src.sample(pos + float2( 0.0, -d.y));
    float4 bottom = src.sample(pos + float2( 0.0,  d.y));
    float4 left   = src.sample(pos + float2(-d.x,  0.0));
    float4 right  = src.sample(pos + float2( d.x,  0.0));

    float4 laplacian = (top + bottom + left + right) - 4.0 * center;

    float blurStrength = length(laplacian.rgb);
    float adaptiveDeblur = mix(sharpeningStrength, sharpeningStrength * 2.0,
                               min(blurStrength * 5.0, 1.0));

    return clamp(center - laplacian * adaptiveDeblur, 0.0, 1.0);
}

inline float4 directionalDeblur(
    coreimage::sampler src, float2 pos, float2 d,
    float refineStrength, float refineBias, float edgeThreshold,
    float deblurIntensity, float sharpeningStrength
) {
    float4 originalColor = src.sample(pos);

    float2 initialGrad = initialLumaGradients(src, pos, d);
    float dval = dValue(initialGrad, refineStrength, refineBias);

    if (dval < edgeThreshold) {
        return mix(originalColor, advancedDeblur(src, pos, d, sharpeningStrength), deblurIntensity * 0.3);
    }

    // Above the threshold the GLSL recomputes the same gradients it already has,
    // so this reuses them rather than sampling twice for the same numbers.
    float2 normalizedGrad = normalizeGradients(initialGrad);

    if (abs(normalizedGrad.x) + abs(normalizedGrad.y) <= 0.0001) {
        return mix(originalColor, advancedDeblur(src, pos, d, sharpeningStrength), deblurIntensity * 0.5);
    }

    float xpos = -sign(normalizedGrad.x);
    float ypos = -sign(normalizedGrad.y);

    float4 xval = src.sample(pos + float2(d.x * xpos, 0.0));
    float4 yval = src.sample(pos + float2(0.0, d.y * ypos));

    float xyratio = abs(normalizedGrad.x) / (abs(normalizedGrad.x) + abs(normalizedGrad.y));

    float4 interpolated = xyratio * xval + (1.0 - xyratio) * yval;
    float4 deblurred = advancedDeblur(src, pos, d, sharpeningStrength);
    float4 anime4kResult = interpolated * dval + originalColor * (1.0 - dval);

    return mix(anime4kResult, deblurred, deblurIntensity);
}

inline float4 enhanceSharpness(
    coreimage::sampler src, float4 color, float2 pos, float2 d, float sharpeningStrength
) {
    float4 blur = (
        src.sample(pos + float2(-d.x, -d.y)) +
        src.sample(pos + float2( 0.0, -d.y)) +
        src.sample(pos + float2( d.x, -d.y)) +
        src.sample(pos + float2(-d.x,  0.0)) +
        src.sample(pos + float2( d.x,  0.0)) +
        src.sample(pos + float2(-d.x,  d.y)) +
        src.sample(pos + float2( 0.0,  d.y)) +
        src.sample(pos + float2( d.x,  d.y))
    ) / 8.0;

    float4 highFreq = color - blur;

    float edgeStrength = length(initialLumaGradients(src, pos, d));
    float adaptiveSharpness = mix(sharpeningStrength * 0.5, sharpeningStrength,
                                  min(edgeStrength * 3.0, 1.0));

    return clamp(color + highFreq * adaptiveSharpness, 0.0, 1.0);
}

inline float4 artifactProtection(
    coreimage::sampler src, float4 enhanced, float4 original, float2 pos, float2 d
) {
    float centerLuma = get_luma(original);

    float variation = 0.0;
    variation += abs(get_luma(src.sample(pos + float2( d.x, 0.0))) - centerLuma);
    variation += abs(get_luma(src.sample(pos + float2(-d.x, 0.0))) - centerLuma);
    variation += abs(get_luma(src.sample(pos + float2(0.0,  d.y))) - centerLuma);
    variation += abs(get_luma(src.sample(pos + float2(0.0, -d.y))) - centerLuma);
    variation /= 4.0;

    float lumaChange = abs(get_luma(enhanced) - get_luma(original));

    if (variation < 0.05 && lumaChange > 0.2) {
        return mix(original, enhanced, 0.5);
    }

    if (any(enhanced.rgb > float3(0.95))) {
        return mix(enhanced, original, 0.3);
    }

    return enhanced;
}

} // namespace

extern "C" float4 anixVideoEnhance(
    coreimage::sampler src,
    float refineStrength,
    float refineBias,
    float edgeThreshold,
    float deblurIntensity,
    float sharpeningStrength,
    coreimage::destination dest
) {
    // The GLSL offsets by uTexelSize = 1/size. A Core Image sampler's space is
    // not the pixel grid, so guessing at the step is how this went wrong the
    // first time: every neighbour landed a whole image away and came back as
    // the clamped edge, which is what produced the artefacts. Ask Core Image
    // for the mapping instead -- one destination pixel, expressed in sampler
    // space, is correct whatever that space turns out to be.
    float2 dc = dest.coord();
    float2 pos = src.transform(dc);
    // abs() because the transform may flip an axis; the kernel samples both
    // +d and -d, so the sign carries no information.
    float2 d = abs(src.transform(dc + float2(1.0, 1.0)) - pos);

    float4 originalColor = src.sample(pos);
    float4 deblurred = directionalDeblur(
        src, pos, d, refineStrength, refineBias, edgeThreshold, deblurIntensity, sharpeningStrength
    );
    float4 sharpened = enhanceSharpness(src, deblurred, pos, d, sharpeningStrength);
    return artifactProtection(src, sharpened, originalColor, pos, d);
}
