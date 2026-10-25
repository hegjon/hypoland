#include "Math.hpp"
#include "../memory/Memory.hpp"
#include "../../macros.hpp"

#include <unordered_map>
#include <array>
#include <algorithm>
#include <vector>

using namespace Math;

// FIXME: expose in hu
static std::unordered_map<eTransform, Mat3x3> transforms = {
    {HYPRUTILS_TRANSFORM_NORMAL, std::array<float, 9>{1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f}},
    {HYPRUTILS_TRANSFORM_90, std::array<float, 9>{0.0f, 1.0f, 0.0f, -1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f}},
    {HYPRUTILS_TRANSFORM_180, std::array<float, 9>{-1.0f, 0.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, 0.0f, 1.0f}},
    {HYPRUTILS_TRANSFORM_270, std::array<float, 9>{0.0f, -1.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f}},
    {HYPRUTILS_TRANSFORM_FLIPPED, std::array<float, 9>{-1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f}},
    {HYPRUTILS_TRANSFORM_FLIPPED_90, std::array<float, 9>{0.0f, 1.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f}},
    {HYPRUTILS_TRANSFORM_FLIPPED_180, std::array<float, 9>{1.0f, 0.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f, 0.0f, 1.0f}},
    {HYPRUTILS_TRANSFORM_FLIPPED_270, std::array<float, 9>{0.0f, -1.0f, 0.0f, -1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f}},
};

eTransform Math::wlTransformToHyprutils(wl_output_transform t) {
    switch (t) {
        case WL_OUTPUT_TRANSFORM_NORMAL: return eTransform::HYPRUTILS_TRANSFORM_NORMAL;
        case WL_OUTPUT_TRANSFORM_180: return eTransform::HYPRUTILS_TRANSFORM_180;
        case WL_OUTPUT_TRANSFORM_90: return eTransform::HYPRUTILS_TRANSFORM_90;
        case WL_OUTPUT_TRANSFORM_270: return eTransform::HYPRUTILS_TRANSFORM_270;
        case WL_OUTPUT_TRANSFORM_FLIPPED: return eTransform::HYPRUTILS_TRANSFORM_FLIPPED;
        case WL_OUTPUT_TRANSFORM_FLIPPED_180: return eTransform::HYPRUTILS_TRANSFORM_FLIPPED_180;
        case WL_OUTPUT_TRANSFORM_FLIPPED_270: return eTransform::HYPRUTILS_TRANSFORM_FLIPPED_270;
        case WL_OUTPUT_TRANSFORM_FLIPPED_90: return eTransform::HYPRUTILS_TRANSFORM_FLIPPED_90;
        default: break;
    }
    return eTransform::HYPRUTILS_TRANSFORM_NORMAL;
}

eTransform Math::invertTransform(eTransform tr) {
    if ((tr & HYPRUTILS_TRANSFORM_90) && !(tr & HYPRUTILS_TRANSFORM_FLIPPED))
        tr = sc<eTransform>(tr ^ sc<int>(HYPRUTILS_TRANSFORM_180));

    return tr;
}

wl_output_transform Math::invertTransform(wl_output_transform tr) {
    if ((tr & WL_OUTPUT_TRANSFORM_90) && !(tr & WL_OUTPUT_TRANSFORM_FLIPPED))
        tr = sc<wl_output_transform>(tr ^ sc<int>(WL_OUTPUT_TRANSFORM_180));

    return tr;
}

static bool matEq(const Mat3x3& a, const Mat3x3& b) {
    for (size_t i = 0; i < 9; ++i) {
        const float Δ = std::fabs(a.getMatrix()[i] - b.getMatrix()[i]);
        if (Δ > 1e-6) // eps
            return false;
    }
    return true;
}

static eTransform composeInternal(eTransform a, eTransform b) {
    const auto& A      = transforms.at(a);
    const auto& B      = transforms.at(b);
    const auto  RESULT = Mat3x3{A}.multiply(B);

    for (const auto& [t, M] : transforms) {
        if (matEq(M, RESULT))
            return t;
    }

    return eTransform::HYPRUTILS_TRANSFORM_NORMAL;
}

eTransform Math::composeTransform(eTransform a, eTransform b) {
    static std::array<std::array<eTransform, 8>, 8> lookup;
    static bool                                     once = true;

    if (once) {
        once = false;

        // bake the composition table
        static_assert(HYPRUTILS_TRANSFORM_FLIPPED_270 == 7);
        for (size_t i = 0; i <= HYPRUTILS_TRANSFORM_FLIPPED_270 /* 7 */; ++i) {
            for (size_t j = 0; j <= HYPRUTILS_TRANSFORM_FLIPPED_270 /* 7 */; ++j) {
                lookup[i][j] = composeInternal(sc<eTransform>(i), sc<eTransform>(j));
            }
        }
    }

    RASSERT(a >= HYPRUTILS_TRANSFORM_NORMAL && a <= HYPRUTILS_TRANSFORM_FLIPPED_270, "Invalid transform a in composeTransform");
    RASSERT(b >= HYPRUTILS_TRANSFORM_NORMAL && b <= HYPRUTILS_TRANSFORM_FLIPPED_270, "Invalid transform b in composeTransform");

    return lookup[a][b];
}

CRegion Math::coalesceRegion(const CRegion& region, size_t maxRects) {
    if (sc<size_t>(pixman_region32_n_rects(region.pixman())) <= maxRects)
        return region.copy();

    // pixman sorts the rectangles by their top edge, so one that starts below the strip so far starts the next one
    std::vector<pixman_box32_t> strips;
    region.forEachRect([&strips](const auto& RECT) {
        if (strips.empty() || RECT.y1 > strips.back().y2) {
            strips.emplace_back(RECT);
            return;
        }

        auto& strip = strips.back();
        strip.x1    = std::min(strip.x1, RECT.x1);
        strip.x2    = std::max(strip.x2, RECT.x2);
        strip.y2    = std::max(strip.y2, RECT.y2);
    });

    if (strips.size() > maxRects)
        return CRegion{region.copy().getExtents()};

    CRegion result;
    for (const auto& strip : strips) {
        result.add(CBox{strip.x1, strip.y1, strip.x2 - strip.x1, strip.y2 - strip.y1});
    }

    return result;
}
