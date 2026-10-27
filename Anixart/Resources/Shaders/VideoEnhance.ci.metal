// "Режим улучшения видео +", after the APK's AnixAnime4KShaderProgram.
//
// Not a line-by-line port any more, and deliberately so. The APK's shader has
// two faults that make it produce artefacts rather than detail:
//
//   * Its gradient is `(r - l, l + 2c + r)`. The second term is a *sum*, not a
//     derivative, so it measures local brightness. Normalised, that direction
//     reads 91% vertical even on a strong vertical edge, and exactly vertical
//     on a flat patch -- so the directional pass blended every pixel with the
//     one above or below it. A vertical smear over the whole picture.
//   * `dValue` then folds that into `-ty + by` where both terms are the same
//     number, so the y component is identically zero and only horizontal
//     differences were detected at all -- at four times their size, which
//     saturated the detector at a luma step of 0.25.
//
// So the gradient here is a real 3x3 Scharr on both axes, and the result is
// clamped to the neighbourhood's own range at the end. That clamp is what stops
// the halos: an unsharp mask creates them by overshooting past the brightest
// and darkest pixels around it, and this cannot. Anime4K's power curve and the
// coefficients the APK sets are unchanged.
//
// Three things here are about faces rather than lines, because a face is what
// a 480p stream handles worst and what sharpening helps least:
//
//   * Scharr instead of Sobel, because Sobel under-reads diagonals by about a
//     tenth, and a face is diagonals.
//   * The sharpening is luma-only, so an edge cannot shift hue.
//   * `flat_relief` takes the quantisation terraces out of smooth shading.
//     Sharpening a banded cheek makes the bands crisper; this is the pass that
//     makes it a cheek again.
//
// The caller runs this twice over the decoded frame and once more after the
// upscale -- see VideoEnhanceFilter.
//
// Compiled with -fcikernel / -cikernel (see project.yml); the result is loaded
// from the target's default.metallib by VideoEnhanceFilter.

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

namespace {

inline float get_luma(float4 rgba) {
    return dot(float3(0.299, 0.587, 0.114), rgba.rgb);
}

/// The polynomial Anime4K uses to turn a gradient magnitude into a blend
/// weight: ~0 below a luma step of about 0.1, rising to ~0.73 by 0.5.
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

/// The 3x3 neighbourhood, sampled once.
///
/// The original sampled around twenty-five times for nine distinct pixels,
/// because every helper re-fetched what the one before it already had.
struct Neighbourhood {
    float4 c;
    float4 t, b, l, r;
    float4 tl, tr, bl, br;
};

inline Neighbourhood gather(coreimage::sampler src, float2 pos, float2 d) {
    Neighbourhood n;
    n.c  = src.sample(pos);
    n.t  = src.sample(pos + float2( 0.0, -d.y));
    n.b  = src.sample(pos + float2( 0.0,  d.y));
    n.l  = src.sample(pos + float2(-d.x,  0.0));
    n.r  = src.sample(pos + float2( d.x,  0.0));
    n.tl = src.sample(pos + float2(-d.x, -d.y));
    n.tr = src.sample(pos + float2( d.x, -d.y));
    n.bl = src.sample(pos + float2(-d.x,  d.y));
    n.br = src.sample(pos + float2( d.x,  d.y));
    return n;
}

/// A 3x3 Scharr on luma, scaled so a full black-to-white edge reads 1.
///
/// Scharr's (3, 10, 3) rather than Sobel's (1, 2, 1) because Sobel is not
/// rotationally symmetric: it under-reads a 45-degree edge by about 10%
/// compared with a vertical one. Anime is diagonals -- a jawline, an eyelash, a
/// strand of hair -- so that bias lands on exactly the lines worth keeping, and
/// the detector that drives everything downstream was reading them as weaker
/// than they are. Scharr was derived to minimise precisely that error.
inline float2 luma_gradient(Neighbourhood n) {
    float tl = get_luma(n.tl), t = get_luma(n.t), tr = get_luma(n.tr);
    float l  = get_luma(n.l),                     r  = get_luma(n.r);
    float bl = get_luma(n.bl), b = get_luma(n.b), br = get_luma(n.br);

    float gx = (3.0 * tr + 10.0 * r + 3.0 * br) - (3.0 * tl + 10.0 * l + 3.0 * bl);
    float gy = (3.0 * bl + 10.0 * b + 3.0 * br) - (3.0 * tl + 10.0 * t + 3.0 * tr);

    return float2(gx, gy) * 0.0625;
}

/// Pulls an edge pixel toward the neighbour on the darker side of the gradient,
/// which is the line-thinning the Anime4K family is built around. With a real
/// gradient this finally moves along the edge instead of always downwards.
inline float4 directional_refine(Neighbourhood n, float2 gradient, float weight) {
    float2 dir = gradient / max(length(gradient), 1e-4);

    float4 across_x = dir.x > 0.0 ? n.l : n.r;
    float4 across_y = dir.y > 0.0 ? n.t : n.b;

    float ratio = abs(dir.x) / max(abs(dir.x) + abs(dir.y), 1e-4);
    float4 target = mix(across_y, across_x, ratio);

    return mix(n.c, target, weight);
}

/// Adaptive unsharp mask, on luma only.
///
/// Sharpening each colour channel on its own is what puts a coloured rim around
/// a red line crossing a blue fill: every channel overshoots by its own amount
/// and the hue at the edge moves. Anime is flat fills bounded by dark lines, so
/// everything worth recovering is in luma -- take the overshoot from luma and
/// add that one number to all three channels, and the colour stays where the
/// artist put it.
///
/// The old floor of half strength on flat areas was sharpening the one thing
/// there that is not detail: the stream's own block noise and banding. Held near
/// zero until the detector actually sees an edge.
inline float4 unsharp(Neighbourhood n, float4 color, float edge, float strength) {
    float4 blur = (n.t + n.b + n.l + n.r + n.tl + n.tr + n.bl + n.br) / 8.0;
    float adaptive = mix(strength * 0.1, strength, smoothstep(0.0, 0.25, edge));
    float delta = get_luma(color) - get_luma(blur);
    return float4(color.rgb + delta * adaptive, color.a);
}

/// Keeps the result inside the range of the pixels around it.
///
/// Overshoot past the local maximum is exactly what a halo is, so forbidding it
/// removes them without taking the sharpening away.
inline float4 anti_ringing(Neighbourhood n, float4 value) {
    float4 lo = min(min(min(n.tl, n.t), min(n.tr, n.l)),
                    min(min(n.c, n.r), min(n.bl, min(n.b, n.br))));
    float4 hi = max(max(max(n.tl, n.t), max(n.tr, n.l)),
                    max(max(n.c, n.r), max(n.bl, max(n.b, n.br))));
    return clamp(value, lo, hi);
}

/// Takes the steps out of a face.
///
/// A 480p stream spends almost no bits on smooth shading, so a cheek, a
/// forehead or a sky arrives quantised into visible terraces. Sharpening makes
/// those terraces crisper, which is the opposite of what anyone wants -- it is
/// why more sharpening has never made a face look better.
///
/// Where the detector sees no real edge, this averages the neighbourhood
/// instead. On a smooth ramp the mean equals the centre, so genuine shading is
/// untouched; on a one-code step it is exactly the step that disappears. Then a
/// little noise, below the threshold of being seen as noise, breaks up the
/// quantisation that formed the band, so what is left cannot line up into a
/// contour.
inline float4 flat_relief(Neighbourhood n, float4 color, float edge, float2 dc, float amount) {
    float flat = (1.0 - smoothstep(0.004, 0.02, edge)) * amount;
    if (flat <= 0.0) {
        return color;
    }

    float4 mean = (n.t + n.b + n.l + n.r + n.tl + n.tr + n.bl + n.br + n.c) / 9.0;
    float4 soft = mix(color, mean, flat * 0.65);

    float noise = fract(sin(dot(dc, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    return float4(soft.rgb + noise * flat * (1.5 / 255.0), color.a);
}

} // namespace

extern "C" float4 anixVideoEnhance(
    coreimage::sampler src,
    float refineStrength,
    float refineBias,
    float edgeThreshold,
    float deblurIntensity,
    float sharpeningStrength,
    float debandAmount,
    coreimage::destination dest
) {
    // The GLSL offsets by uTexelSize = 1/size. A Core Image sampler's space is
    // not the pixel grid, so guessing at the step is how this went wrong the
    // first time: every neighbour landed a whole image away and came back as
    // the clamped edge. Ask Core Image for the mapping instead -- one
    // destination pixel, expressed in sampler space, is correct whatever that
    // space turns out to be.
    float2 dc = dest.coord();
    float2 pos = src.transform(dc);
    // abs() because the transform may flip an axis; the kernel samples both
    // +d and -d, so the sign carries no information.
    float2 d = abs(src.transform(dc + float2(1.0, 1.0)) - pos);

    Neighbourhood n = gather(src, pos, d);

    float2 gradient = luma_gradient(n);
    float edge = min(length(gradient), 1.0);
    float weight = clamp(
        anime4k_power_function(edge) * refineStrength + refineBias,
        0.0,
        1.0
    );

    float4 result = n.c;
    if (edge > edgeThreshold) {
        result = directional_refine(n, gradient, weight * deblurIntensity);
    }
    result = unsharp(n, result, edge, sharpeningStrength);
    result = anti_ringing(n, result);
    // After the clamp, not before: anti-ringing holds the result inside the
    // neighbourhood's own range, and on a flat patch that range is zero -- it
    // would take the dither straight back out again.
    result = flat_relief(n, result, edge, dc, debandAmount);

    return float4(clamp(result.rgb, 0.0, 1.0), n.c.a);
}
