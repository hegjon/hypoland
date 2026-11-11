#include "Math.hpp"
#include "../memory/Memory.hpp"
#include "../../macros.hpp"

#include <unordered_map>
#include <array>
#include <algorithm>
#include <vector>
#include <cmath>

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

double Math::regionArea(const CRegion& region) {
    double area = 0;
    region.forEachRect([&area](const auto& RECT) { area += sc<double>(RECT.x2 - RECT.x1) * sc<double>(RECT.y2 - RECT.y1); });
    return area;
}

CRegion Math::coalesceRegion(const CRegion& region, size_t maxRects, double rectCost) {
    const auto RECTS = sc<size_t>(pixman_region32_n_rects(region.pixman()));
    if (RECTS <= maxRects)
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

    double stripsArea = 0;
    for (const auto& strip : strips) {
        stripsArea += sc<double>(strip.x2 - strip.x1) * sc<double>(strip.y2 - strip.y1);
    }

    const auto   EXTENTS    = region.copy().getExtents();
    const double AS_IS      = sc<double>(RECTS) * rectCost + regionArea(region);
    const double AS_STRIPS  = sc<double>(strips.size()) * rectCost + stripsArea;
    const double AS_EXTENTS = rectCost + EXTENTS.w * EXTENTS.h;
    const double CHEAPEST   = std::min({AS_IS, AS_STRIPS, AS_EXTENTS});

    if (AS_EXTENTS <= CHEAPEST)
        return CRegion{EXTENTS};

    if (AS_STRIPS <= CHEAPEST) {
        CRegion result;
        for (const auto& strip : strips) {
            result.add(CBox{strip.x1, strip.y1, strip.x2 - strip.x1, strip.y2 - strip.y1});
        }
        return result;
    }

    return region.copy();
}

CRegion Math::expandRegion(const CRegion& region, int by) {
    std::vector<pixman_box32_t> boxes;
    boxes.reserve(sc<size_t>(pixman_region32_n_rects(region.pixman())));
    region.forEachRect([&](const auto& RECT) { boxes.push_back({RECT.x1 - by, RECT.y1 - by, RECT.x2 + by, RECT.y2 + by}); });

    CRegion           result;
    pixman_region32_t grown;
    pixman_region32_init_rects(&grown, boxes.data(), sc<int>(boxes.size()));
    pixman_region32_copy(result.pixman(), &grown);
    pixman_region32_fini(&grown);
    return result;
}

CBox Math::coveredPixels(const CBox& box) {
    const double X = std::floor(box.x), Y = std::floor(box.y);
    return {X, Y, std::ceil(box.x + box.w) - X, std::ceil(box.y + box.h) - Y};
}

CBox Math::wholePixels(const CBox& box) {
    const double X = std::ceil(box.x), Y = std::ceil(box.y);
    return {X, Y, std::max(0.0, std::floor(box.x + box.w) - X), std::max(0.0, std::floor(box.y + box.h) - Y)};
}
