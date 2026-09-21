// this is a bit laggy right now
// maybe only inject on extensions pages themselves rather then the gallary
(function () {
  "use strict";

  // guard against double injection
  // this might not be working
  if (window.__storeInterceptLoaded) return;
  window.__storeInterceptLoaded = true;
  if (window.location.hostname !== "chromewebstore.google.com") return;

  // config
  // why is thi so complex 
  var DEBUG = true;
  var TAG = "StoreIntercept";
  var BRIDGE_POLL_MS = 50;
  var BRIDGE_MAX_ATTEMPTS = 200; // ~10 s
  var BUTTON_RESET_MS = 5000; // fallback when no installFinished signal
  var ADD_TO_CHROME_RE = /Add to Chrome/i;
  var BANNER_SELECTORS = '[jscontroller="o2G9me"], #c15';
  var INSTALL_MARK = "data-store-intercept-install";

  function log() {
    if (!DEBUG) return;
    var parts = ["[" + TAG + "]"];
    for (var i = 0; i < arguments.length; i++) parts.push("" + arguments[i]);
    try {
      console.log(parts.join(" "));
    } catch (e) {}
  }

  // Qt WebChannel client
  // loaded at DocumentCreation before this script; shared via window.QWebChannel.

  // /detail/{slug}/{32-char-id}
  function extractId(urlOrPath) {
    var m = String(urlOrPath || "").match(
      /\/detail\/(?:[a-z0-9_-]+\/)?([a-z]{32})(?:[\/?#]|$)/i,
    );
    return m && m[1];
  }

  // cpp bridge
  var bridge = new Promise(function (resolve) {
    var attempts = 0;
    (function tick() {
      var transport = null;
      try {
        transport = window.qt && window.qt.webChannelTransport;
      } catch (e) {}
      if (!transport) {
        if (++attempts < BRIDGE_MAX_ATTEMPTS) {
          setTimeout(tick, BRIDGE_POLL_MS);
        } else {
          log("bridge: qt.webChannelTransport never appeared");
          resolve(null);
        }
        return;
      }
      if (!window.QWebChannel) {
        log("bridge: window.QWebChannel missing (qwebchannel.js not loaded first?)");
        resolve(null);
        return;
      }
      log(
        "bridge: transport found after " +
          attempts +
          " retries, creating QWebChannel",
      );
      new window.QWebChannel(transport, function (channel) {
        var installer = channel.objects.extensionInstaller || null;
        log("bridge: ready, extensionInstaller present=" + !!installer);
        resolve(installer);
      });
    })();
  });

  // rejects only if the bridge is unusable.
  // outcome comes from the optional installFinished signal.)
  function requestInstall(extensionId) {
    return bridge.then(function (installer) {
      if (!installer) throw new Error("extensionInstaller bridge missing");
      log("calling installExtension id=" + extensionId);
      installer.installExtension(extensionId);
    });
  }

  // polyfill chrome.webstore.install() so that the store page can call it and we can intercept the request.
  function storeInstall(url, success, failure) {
    var extensionId = extractId(url);
    log("storeInstall() url=" + url + " id=" + (extensionId || "NONE"));

    function later(fn, arg) {
      if (typeof fn === "function")
        setTimeout(function () {
          fn(arg);
        }, 0);
    }

    if (!extensionId) {
      later(failure, "No extension id in URL: " + url);
    } else {
      requestInstall(extensionId).then(
        function () {
          later(success);
        },
        function (err) {
          log("storeInstall failed: " + (err && err.message));
          later(failure, String((err && err.message) || err));
        },
      );
    }
    return Promise.resolve();
  }

  var hadStoreInstall = !!(
    window.chrome &&
    window.chrome.webstore &&
    window.chrome.webstore.install
  );
  window.chrome = window.chrome || {};
  window.chrome.webstore = window.chrome.webstore || {};
  window.chrome.webstore.install =
    window.chrome.webstore.install || storeInstall;
  log(
    "polyfill: pre-existing install=" +
      hadStoreInstall +
      ", now " +
      (window.chrome.webstore.install === storeInstall
        ? "OURS"
        : "pre-existing"),
  );

  // capture click
  function isInstallButton(button) {
    return (
      button.hasAttribute(INSTALL_MARK) ||
      ADD_TO_CHROME_RE.test(button.textContent)
    );
  }

  function setButtonBusy(button) {
    if (!button.hasAttribute("data-store-intercept-label"))
      button.setAttribute("data-store-intercept-label", button.textContent);
    button.textContent = "Installing...";
    button.disabled = true;
  }

  function resetButton(button, label) {
    if (!button.isConnected) return;
    button.textContent =
      label ||
      button.getAttribute("data-store-intercept-label") ||
      "Add to Chrome";
    button.removeAttribute("data-store-intercept-label");
    button.disabled = false;
  }

  var pending = {}; // extensionId -> button awaiting an installFinished signal

  bridge.then(function (installer) {
    if (
      installer &&
      installer.installFinished &&
      installer.installFinished.connect
    ) {
      installer.installFinished.connect(function (id, ok, message) {
        log("installFinished id=" + id + " ok=" + ok + " message=" + message);
        var button = pending[id];
        delete pending[id];
        if (button) resetButton(button, ok ? "Installed" : "Install failed");
      });
    }
  });

  document.addEventListener(
    "click",
    function (event) {
      var target = event.target;
      var button = target instanceof Element ? target.closest("button") : null;
      if (!button || !isInstallButton(button)) return;

      var extensionId = extractId(window.location.pathname);
      log(
        "click on install button, path=" +
          window.location.pathname +
          " id=" +
          (extensionId || "NONE") +
          " disabled=" +
          button.disabled,
      );
      if (!extensionId) {
        log("could not parse id, letting store handle it");
        return;
      }

      event.preventDefault();
      event.stopImmediatePropagation();
      setButtonBusy(button);

      requestInstall(extensionId).then(
        function () {
          pending[extensionId] = button;
          // the host never reports back, don't leave the button stuck.
          setTimeout(function () {
            if (pending[extensionId] === button) {
              delete pending[extensionId];
              resetButton(button);
            }
          }, BUTTON_RESET_MS);
        },
        function (err) {
          log("install request failed: " + (err && err.message));
          resetButton(button, "Install failed");
        },
      );
    },
    true,
  );
  log("capture click listener installed");

  // hide switch to chrome button 
  function cleanStore() {
    var changed = false;

    document.querySelectorAll(BANNER_SELECTORS).forEach(function (el) {
      if (el.style.display !== "none") {
        el.style.display = "none";
        changed = true;
      }
    });

    document.querySelectorAll("button[disabled]").forEach(function (b) {
      if (ADD_TO_CHROME_RE.test(b.textContent)) {
        b.disabled = false;
        b.setAttribute(INSTALL_MARK, "");
        changed = true;
      }
    });

    if (changed) log("cleanStore: adjusted store UI");
  }

  var cleanScheduled = false;
  function scheduleClean() {
    if (cleanScheduled) return;
    cleanScheduled = true;
    (window.requestAnimationFrame || setTimeout)(function () {
      cleanScheduled = false;
      cleanStore();
    });
  }

  function startWatching() {
    if (!document.documentElement) {
      log("startWatching deferred: documentElement not ready yet");
      return;
    }
    cleanStore();
    // childList only: our own style/attribute edits don't retrigger it.
    new MutationObserver(scheduleClean).observe(document.documentElement, {
      childList: true,
      subtree: true,
    });
    log("MutationObserver installed");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      log("DOMContentLoaded");
      startWatching();
    });
  } else {
    log("document already ready (" + document.readyState + ")");
    startWatching();
  }
})();
