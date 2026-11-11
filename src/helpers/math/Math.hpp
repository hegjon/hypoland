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

    // What a rectangle of a region costs to upload on top of its pixels, in pixels: the call per rectangle
    constexpr double COALESCE_RECT_COST = 8192;
    // What a rectangle of a frame's damage costs on top of its pixels: every element of the frame is drawn once per
    // rectangle (a scissor and a draw call each). Measured on crocus and r600 (2026-11-04, 4 fresh sessions each of 8k,
    // 64k and 256k): at 8k a focus change under load came 0.4 to 0.6 ms later, at 256k typing 1 ms
    constexpr double COALESCE_FRAME_RECT_COST = 65536;

    // A region of more than maxRects rectangles as the cheapest of three that cover it, a rectangle costing rectCost
    // pixels on top of its area: the region itself, its horizontal strips (the bounding boxes of the rectangles that
    // overlap or touch vertically) or its bounding box. Drawing or uploading a region costs a call per rectangle, which
    // costs more than the extra pixels once a region falls apart into many small rectangles, and less than the pixels
    // of a bounding box around distant ones (a typed key in one window and a printing log in another).
    CRegion coalesceRegion(const CRegion& region, size_t maxRects, double rectCost = COALESCE_RECT_COST);

    // The pixels of a region, its rectangles' areas added up (they do not overlap)
    double regionArea(const CRegion& region);

    // The region with every rectangle grown by `by` pixels on each side: what CRegion::expand() gives, made at once
    // instead of unioning the grown rectangles one at a time, whose cost grows with the square of their number
    CRegion expandRegion(const CRegion& region, int by);

    // Every pixel a box in pixels can touch when it is drawn: its start rounded down, its end up. A box at a half pixel
    // (a logical position at a fractional scale) is drawn with the row or column whose centre lies on its edge, on one
    // side or the other depending on the GPU, which CBox::round() can drop from its damage
    CBox coveredPixels(const CBox& box);

    // The pixels a box in pixels covers whole: its start rounded up, its end down (empty when it covers none). What an
    // opaque box hides: a pixel it covers in part shows what is under it as well
    CBox wholePixels(const CBox& box);
}