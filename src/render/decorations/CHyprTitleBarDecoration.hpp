#pragma once

#include "IHyprWindowDecoration.hpp"
#include "../../helpers/AnimatedVariable.hpp"
#include "../../helpers/signal/Signal.hpp"
#include "../../helpers/time/Time.hpp"
#include "../Texture.hpp"

#include <optional>
#include <string>

// A titlebar above a window: the name of its app or its title, buttons that run commands, dragging the window by it
// and a command on double click. Built in for Omarchy's floating workspaces, see TitleBars.hpp.
class CHyprTitleBarDecoration : public IHyprWindowDecoration {
  public:
    CHyprTitleBarDecoration(PHLWINDOW);
    virtual ~CHyprTitleBarDecoration() = default;

    virtual SDecorationPositioningInfo getPositioningInfo();

    virtual void                       onPositioningReply(const SDecorationPositioningReply& reply);

    virtual void                       draw(PHLMONITOR, float const& a);

    virtual eDecorationType            getDecorationType();

    virtual void                       updateWindow(PHLWINDOW);

    virtual void                       damageEntire();

    virtual bool                       onInputOnDeco(const eInputType, const Vector2D&, std::any = {});

    virtual eDecorationLayer           getDecorationLayer();

    virtual uint64_t                   getDecorationFlags();

    virtual std::string                getDisplayName();

    virtual void                       initializeAnimations();

    // how far it reaches above the window's surface, 0 while hidden
    int  visibleHeight();

    void onConfigReloaded();

  private:
    PHLWINDOWREF              m_window;
    CBox                      m_assignedBox;

    bool                      m_visible = false;
    bool                      m_noBar   = false;
    std::optional<CHyprColor> m_forcedBarColor;
    std::optional<CHyprColor> m_forcedTitleColor;

    PHLANIMVAR<CHyprColor>    m_barColor;

    // the title and what its texture was made from
    SP<Render::ITexture>  m_titleTex;
    std::string           m_windowClass, m_windowTitle, m_title;
    int                   m_titleMaxWidth = 0, m_titleSize = 0;
    bool                  m_titleDirty = true;

    Time::steady_tp       m_lastPress;
    Vector2D              m_pressCoords;
    bool                  m_dragPending = false;
    std::optional<size_t> m_hoveredButton;
    CHyprSignalListener   m_mouseMove;

    bool                  wantsVisible();
    void                  setVisible(bool visible);
    void                  updateRules();
    CBox                  assignedBoxGlobal();
    std::optional<size_t> buttonAt(const Vector2D& barCoords);
    void                  updateTitle(PHLWINDOW window, int maxWidth, float scale);
    void                  onMouseMove(const Vector2D& coords);
    void                  startDrag();
};
