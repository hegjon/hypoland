#pragma once

#include "Monitor.hpp"
#include "../helpers/Format.hpp"
#include "../helpers/time/Timer.hpp"
#include "../render/Framebuffer.hpp"
#include <hyprutils/math/Vector2D.hpp>
#include <vector>

class CEventLoopTimer;

namespace Monitor {
    class CMonitorResources {
      public:
        CMonitorResources(WP<CMonitor> monitor, DRMFormat format, Vector2D size);
        ~CMonitorResources();

        SP<Render::IFramebuffer> getUnusedWorkBuffer();
        SP<Render::IFramebuffer> getUnusedWorkBuffer(const Vector2D& size);
        SP<Render::IFramebuffer> getUnusedSnapshotFB();
        void                     forEachUnusedFB(std::function<void(SP<Render::IFramebuffer>)> callback, bool includeNamed = false);
        bool                     hasMirrorFB() const;
        bool                     shouldKeepMirrorFB() const;
        void                     releaseMirrorFB();
        void                     invalidateMirrorFB();
        void                     markMirrorFBStale(const CRegion& damage);
        void                     markMirrorFBStale();
        void                     markMirrorFBUpdated();
        CRegion                  pendingMirrorFBDamage() const;
        SP<Render::IFramebuffer> mirrorFB();
        SP<Render::ITexture>     getMirrorTexture();

        SP<Render::ITexture>     m_stencilTex; // TODO fix blur ignore alpha and remove
        SP<Render::IFramebuffer> m_blurFB;

      private:
        void     initFB(SP<Render::IFramebuffer> fb);
        Vector2D mirrorFBDamageSize() const;
        void     scheduleCleanup();
        void     releaseUnusedWorkBuffers();

        struct SResource {
            SP<Render::IFramebuffer> buffer;
            CTimer                   lastUsed;
        };

        SP<Render::IFramebuffer> m_monitorMirrorFB;
        CRegion                  m_mirrorFBStaleDamage;
        WP<CMonitor>             m_monitor;
        DRMFormat                m_drmFormat;
        Vector2D                 m_size;
        bool                     m_mirrorFBValid            = false;
        bool                     m_mirrorFBNeedsFullRefresh = true;

        std::vector<SResource>   m_workBuffers;
        std::vector<SResource>   m_sizedWorkBuffers;
        std::vector<SResource>   m_snapshotBuffers;
        SP<CEventLoopTimer>      m_cleanupTimer;

        friend class CMonitor;
    };
}
