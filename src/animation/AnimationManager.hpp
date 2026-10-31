#pragma once

#include <optional>
#include <hyprutils/animation/AnimationManager.hpp>
#include <hyprutils/animation/AnimatedVariable.hpp>

#include "../defines.hpp"
#include "../helpers/AnimatedVariable.hpp"
#include "../desktop/DesktopTypes.hpp"
#include "../helpers/time/Timer.hpp"
#include "../helpers/time/Time.hpp"
#include "../managers/eventLoop/EventLoopTimer.hpp"

namespace Animation {

    class CHyprAnimationManager : public Hyprutils::Animation::CAnimationManager {
      public:
        CHyprAnimationManager();

        void tick(const Time::steady_tp& now);
        // now is the frame's clock read, shared with the render and the timer re-arm. The values are those of the moment the
        // frame reaches the screen, the next vblank of monitor (the one rendering, or the fastest), see curveStep()
        void         frameTick(const Time::steady_tp& now, PHLMONITOR monitor = nullptr);
        void         requestTick();
        virtual void scheduleTick();
        void         scheduleTick(std::optional<Time::steady_tp> now);
        virtual void onTicked();

        // Reset tick state after session changes (suspend/wake, lock/unlock)
        void resetTickState();

        using SAnimationPropertyConfig = Hyprutils::Animation::SAnimationPropertyConfig;
        template <Animable VarType>
        void createAnimation(const VarType& v, PHLANIMVAR<VarType>& pav, SP<SAnimationPropertyConfig> pConfig, eAVarDamagePolicy policy) {
            constexpr const eAnimatedVarType EAVTYPE = typeToeAnimatedVarType<VarType>;
            pav                                      = makeUnique<CAnimatedVariable<VarType>>();

            pav->create2(EAVTYPE, sc<Hyprutils::Animation::CAnimationManager*>(this), pav, v);
            pav->setConfig(pConfig);
            pav->m_Context.eDamagePolicy = policy;
        }

        template <Animable VarType>
        void createAnimation(const VarType& v, PHLANIMVAR<VarType>& pav, SP<SAnimationPropertyConfig> pConfig, PHLWINDOW pWindow, eAVarDamagePolicy policy) {
            createAnimation(v, pav, pConfig, policy);
            pav->m_Context.pWindow = pWindow;
        }
        template <Animable VarType>
        void createAnimation(const VarType& v, PHLANIMVAR<VarType>& pav, SP<SAnimationPropertyConfig> pConfig, PHLWINDOW pWindow, SP<IHyprWindowDecoration> pDecoration,
                             eAVarDamagePolicy policy) {
            createAnimation(v, pav, pConfig, pWindow, policy);
            pav->m_Context.pDecoration = pDecoration;
        }
        template <Animable VarType>
        void createAnimation(const VarType& v, PHLANIMVAR<VarType>& pav, SP<SAnimationPropertyConfig> pConfig, PHLWORKSPACE pWorkspace, eAVarDamagePolicy policy) {
            createAnimation(v, pav, pConfig, policy);
            pav->m_Context.pWorkspace = pWorkspace;
        }
        template <Animable VarType>
        void createAnimation(const VarType& v, PHLANIMVAR<VarType>& pav, SP<SAnimationPropertyConfig> pConfig, PHLLS pLayer, eAVarDamagePolicy policy) {
            createAnimation(v, pav, pConfig, policy);
            pav->m_Context.pLayer = pLayer;
        }

        std::string         styleValidInConfigVar(const std::string&, const std::string&);

        SP<CEventLoopTimer> m_animationTimer;

        float               m_lastTickTimeMs;

        // how far ahead of the tick's clock read the frame it computes values for is shown
        std::chrono::nanoseconds m_tickLead{0};

      private:
        bool            m_tickScheduled       = false;
        bool            m_manualTickRequested = false;
        bool            m_lastTickValid       = false;
        Time::steady_tp m_lastTick;
    };

    UP<CHyprAnimationManager>& mgr();
}
