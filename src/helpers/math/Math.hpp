#pragma once

#include <wayland-server-protocol.h>

// includes box and vector as well
#include <hyprutils/math/Region.hpp>
#include <hyprutils/math/Mat3x3.hpp>

// NOLINTNEXTLINE
using namespace Hyprutils::Math;

namespace Math {
    constexpr const Vector2D VECTOR2D_MAX = {std::numeric_limits<double>::max(), std::numeric_limits<double>::max()};

    eTransform               wlTransformToHyprutils(wl_output_transform t);
    wl_output_transform      invertTransform(wl_output_transform tr);
    eTransform               invertTransform(eTransform tr);
    eTransform               composeTransform(eTransform a, eTransform b);

    // A region of more than maxRects rectangles, merged into horizontal strips: the bounding boxes of the rectangles
    // that overlap or touch vertically, and into its bounding box when that still leaves more strips. The result
    // covers the region. Drawing or uploading a region costs a call per rectangle, which costs more than the extra
    // pixels once a region falls apart into many small rectangles.
    CRegion coalesceRegion(const CRegion& region, size_t maxRects);
}