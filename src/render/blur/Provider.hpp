#pragma once

#include "../../helpers/math/Math.hpp"
#include "../Framebuffer.hpp"

namespace Render {
    // "Jaki kurwa provident????"
    class IBlurProvider {
      public:
        virtual ~IBlurProvider() = default;

        virtual void             expandDamage(CRegion& damage, float multiplier = 1.F) const                  = 0;
        virtual SP<IFramebuffer> blur(SP<IFramebuffer> source, float strength, const CRegion& originalDamage) = 0;

      protected:
        IBlurProvider() = default;
    };
};
