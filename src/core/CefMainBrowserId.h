#pragma once

#include <include/cef_browser.h>
#include <atomic>

// The DevTools browser is created by CefBrowserHost::ShowDevTools() and reuses
// the page's CefClient, so every handler also sees the DevTools browser's load,
// title and context-menu events. This is how they tell the two apart: the
// identifier of the page's own browser, claimed by CefTabClient in
// OnAfterCreated. Both run on the CEF UI thread, so a plain atomic is enough.
class CefMainBrowserId
{
public:
    // Claims |id| as the page's own browser. False when one is already claimed,
    // which is how a DevTools browser is recognised.
    bool claim(int id)
    {
        int expected = 0;
        return m_id.compare_exchange_strong(expected, id);
    }

    // Gives the id up if it still belongs to |browser|; false for DevTools.
    bool release(const CefRefPtr<CefBrowser> &browser)
    {
        int expected = browser->GetIdentifier();
        return m_id.compare_exchange_strong(expected, 0);
    }

    // False for the DevTools browser and before the page's browser exists.
    bool matches(const CefRefPtr<CefBrowser> &browser) const
    {
        const int id = m_id.load();
        return id != 0 && browser && browser->GetIdentifier() == id;
    }

private:
    std::atomic<int> m_id{0};
};
