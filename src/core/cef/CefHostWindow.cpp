#include "CefHostWindow.h"

#include <QtGlobal>

#include <utility>

CefHostWindow::CefHostWindow(const CefRect &bounds, std::function<void()> ready)
    : m_bounds(bounds), m_ready(std::move(ready))
{
}

void CefHostWindow::create(CefRefPtr<CefClient> client,
                           const CefString &url,
                           const CefBrowserSettings &settings,
                           CefRefPtr<CefRequestContext> requestContext)
{
    m_browserView = CefBrowserView::CreateBrowserView(client, url, settings, nullptr, requestContext, this);
    CefWindow::CreateTopLevelWindow(this);
}

void CefHostWindow::OnWindowCreated(CefRefPtr<CefWindow> window)
{
    m_window = window;
    window->AddChildView(m_browserView);
    if (m_ready)
        std::exchange(m_ready, nullptr)();
}

void CefHostWindow::OnWindowDestroyed(CefRefPtr<CefWindow> window)
{
    Q_UNUSED(window);
    m_browserView = nullptr;
    m_window = nullptr;
}

void CefHostWindow::setBounds(const CefRect &bounds)
{
    m_bounds = bounds;
    if (m_window)
        m_window->SetBounds(bounds);
}

void CefHostWindow::setVisible(bool visible)
{
    if (!m_window || visible == m_visible)
        return;
    m_visible = visible;
    if (visible)
        m_window->Show();
    else
        m_window->Hide();
}

void CefHostWindow::close()
{
    m_ready = nullptr;
    if (m_window)
        m_window->Close();
}

void *CefHostWindow::nativeHandle() const
{
    return m_window ? reinterpret_cast<void *>(m_window->GetWindowHandle()) : nullptr;
}
