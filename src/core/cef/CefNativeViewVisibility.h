#pragma once

namespace CefNativeViewVisibility
{

constexpr bool shouldShow(bool windowVisible,
                          bool itemVisible,
                          bool loading,
                          bool keepVisibleWhileLoading) noexcept
{
    return windowVisible && (itemVisible || (loading && keepVisibleWhileLoading));
}

} // namespace CefNativeViewVisibility
