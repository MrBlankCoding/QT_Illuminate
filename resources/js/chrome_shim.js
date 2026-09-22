(function () {
  "use strict";
  // This is always true
  if (window.chrome && window.chrome.runtime && window.chrome.runtime.id)
    return;

  var boot = window.__illum || {};
  var EXID = boot.id || location.host || "";
  var manifest = boot.manifest || {};
  var messages = boot.messages || {}; // keys are lower-cased
  var uiLang = boot.uiLanguage || navigator.language || "en-US";
  var platform = boot.platform || { os: "linux", arch: "x86-64" };

  // helper functions
  function exUrl(p) {
    return "illum-ext://" + EXID + "/" + String(p).replace(/^\/+/, "");
  }
  function resolveUrl(u) {
    try {
      return new URL(String(u), exUrl("")).href;
    } catch (e) {
      return String(u);
    }
  }
  function openPage(u) {
    try {
      window.open(resolveUrl(u), "_blank");
    } catch (e) {}
  }
  function has(o, k) {
    return Object.prototype.hasOwnProperty.call(o, k);
  }
  function clone(v) {
    return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
  }
  function lastFn(args) {
    var l = args[args.length - 1];
    return typeof l === "function" ? l : undefined;
  }
  // callbacks always fire async
  function respond(cb, value) {
    if (typeof cb === "function") {
      setTimeout(function () {
        cb(value);
      }, 0);
      return undefined;
    }
    return Promise.resolve(value);
  }
  function noop() {
    return respond(lastFn(arguments));
  }

  function makeEvent() {
    var cbs = [];
    return {
      addListener: function (cb) {
        if (typeof cb === "function") cbs.push(cb);
      },
      removeListener: function (cb) {
        var i = cbs.indexOf(cb);
        if (i >= 0) cbs.splice(i, 1);
      },
      hasListener: function (cb) {
        return cbs.indexOf(cb) >= 0;
      },
      hasListeners: function () {
        return cbs.length > 0;
      },
      emit: function () {
        var a = arguments;
        cbs.slice().forEach(function (cb) {
          try {
            cb.apply(null, a);
          } catch (e) {}
        });
      },
    };
  }

  // i18n
  function predefined(key) {
    switch (key) {
      case "@@extension_id":
        return EXID;
      case "@@ui_locale":
        return uiLang.replace("-", "_");
      case "@@bidi_dir":
        return "ltr";
      case "@@bidi_reversed_dir":
        return "rtl";
      case "@@bidi_start_edge":
        return "left";
      case "@@bidi_end_edge":
        return "right";
    }
    return "";
  }

  var i18n = {
    getUILanguage: function () {
      return uiLang;
    },
    getAcceptLanguages: function (cb) {
      var langs =
        navigator.languages && navigator.languages.length
          ? Array.prototype.slice.call(navigator.languages)
          : [uiLang];
      return respond(cb, langs);
    },
    getMessage: function (key, substitutions) {
      key = String(key);
      if (key.indexOf("@@") === 0) return predefined(key.toLowerCase());
      var entry = messages[key.toLowerCase()];
      if (!entry || entry.message == null) return "";
      var msg = String(entry.message);

      // $NAME$ -> placeholders[NAME].content (which is usually "$1")
      var ph = entry.placeholders;
      if (ph) {
        var lookup = {};
        Object.keys(ph).forEach(function (n) {
          lookup[n.toLowerCase()] =
            ph[n] && ph[n].content != null ? String(ph[n].content) : "";
        });
        msg = msg.replace(/\$([a-z0-9_@]+)\$/gi, function (whole, n) {
          var v = lookup[n.toLowerCase()];
          return v === undefined ? whole : v;
        });
      }

      // $1..$9 -> substitutions, $$ -> $
      var subs =
        substitutions == null
          ? []
          : Array.isArray(substitutions)
            ? substitutions
            : [substitutions];
      return msg.replace(/\$(\$|\d)/g, function (whole, d) {
        if (d === "$") return "$";
        var i = parseInt(d, 10) - 1;
        return i >= 0 && i < subs.length ? String(subs[i]) : "";
      });
    },
  };

  // storage shim
  var hasLocalStorage = (function () {
    try {
      var k = "__illum_probe";
      window.localStorage.setItem(k, "1");
      window.localStorage.removeItem(k);
      return true;
    } catch (e) {
      return false;
    }
  })();
  var storageChanged = makeEvent();

  function storageArea(name, persistent) {
    var key = "__illum_storage_" + name;
    var persist = persistent && hasLocalStorage;
    var mem = {};

    function load() {
      if (!persist) return mem;
      try {
        return JSON.parse(window.localStorage.getItem(key)) || {};
      } catch (e) {
        return {};
      }
    }
    function save(d) {
      if (!persist) {
        mem = d;
        return;
      }
      try {
        window.localStorage.setItem(key, JSON.stringify(d));
      } catch (e) {}
    }
    function keyList(k) {
      return k == null ? null : Array.isArray(k) ? k : [k];
    }

    var area = { onChanged: makeEvent() };
    function notify(changes) {
      if (!Object.keys(changes).length) return;
      area.onChanged.emit(changes);
      storageChanged.emit(changes, name);
    }

    area.get = function (keys, cb) {
      var d = load(),
        out = {};
      if (keys == null) {
        Object.keys(d).forEach(function (k) {
          out[k] = clone(d[k]);
        });
      } else if (typeof keys === "string" || Array.isArray(keys)) {
        keyList(keys).forEach(function (k) {
          if (has(d, k)) out[k] = clone(d[k]);
        });
      } else if (typeof keys === "object") {
        Object.keys(keys).forEach(function (k) {
          out[k] = has(d, k) ? clone(d[k]) : keys[k];
        });
      }
      return respond(cb, out);
    };
    area.set = function (items, cb) {
      var d = load(),
        changes = {};
      Object.keys(items || {}).forEach(function (k) {
        var nv = clone(items[k]);
        var ov = has(d, k) ? d[k] : undefined;
        d[k] = nv;
        if (JSON.stringify(ov) !== JSON.stringify(nv))
          changes[k] = { oldValue: ov, newValue: nv };
      });
      save(d);
      notify(changes);
      return respond(cb);
    };
    area.remove = function (keys, cb) {
      var d = load(),
        changes = {};
      (keyList(keys) || []).forEach(function (k) {
        if (has(d, k)) {
          changes[k] = { oldValue: d[k] };
          delete d[k];
        }
      });
      save(d);
      notify(changes);
      return respond(cb);
    };
    area.clear = function (cb) {
      var d = load(),
        changes = {};
      Object.keys(d).forEach(function (k) {
        changes[k] = { oldValue: d[k] };
      });
      save({});
      notify(changes);
      return respond(cb);
    };
    area.getBytesInUse = function (keys, cb) {
      var d = load();
      var list = keyList(keys) || Object.keys(d);
      var bytes = list.reduce(function (s, k) {
        return s + (has(d, k) ? k.length + JSON.stringify(d[k]).length : 0);
      }, 0);
      return respond(lastFn(arguments), bytes);
    };
    area.setAccessLevel = noop;
    return area;
  }

  var storage = {
    local: storageArea("local", true),
    sync: storageArea("sync", true),
    session: storageArea("session", false),
    managed: {
      get: function () {
        return respond(lastFn(arguments), {});
      },
      getBytesInUse: function () {
        return respond(lastFn(arguments), 0);
      },
      onChanged: makeEvent(),
    },
    onChanged: storageChanged,
  };

  // No extension service worker runs in this browser, so messages that would
  // normally be answered by the background script have no real reply. Pages
  // like uBO Lite's dashboard gate rendering on their options payload
  // (settings.js: `getOptionsPageData().then(data => { if(!data) return; ... })`
  // and only removes `body.loading` once data arrives). Answer those known
  // read-only intents with inert defaults so the UI can reveal itself; leave
  // everything else unanswered (undefined), as before.
  function defaultReply(msg) {
    if (msg == null || typeof msg !== "object") return undefined;
    switch (String(msg.what)) {
      case "getOptionsPageData":
        return {
          firstRun: false,
          autoReload: false,
          canShowBlockedCount: false,
          showBlockedCount: false,
          hasOmnipotence: false,
          strictBlockMode: false,
          popupBlockMode: true,
          developerMode: false,
          disabledFeatures: [],
          defaultFilteringMode: 2,
          supportsUserScripts: false,
          supportsCompiledFilters: false,
        };
    }
    return undefined;
  }

  // runtime shim
  var runtime = {
    id: EXID,
    lastError: null,
    getURL: exUrl,
    getManifest: function () {
      return manifest;
    },
    getPlatformInfo: function (cb) {
      return respond(cb, { os: platform.os, arch: platform.arch });
    },
    getBackgroundPage: function (cb) {
      return respond(cb, null);
    },
    sendMessage: function () {
      return respond(lastFn(arguments), defaultReply(arguments[0]));
    },
    connect: function (a, b) {
      var info =
        b && typeof b === "object" ? b : a && typeof a === "object" ? a : {};
      return {
        name: info.name || "",
        postMessage: function () {},
        disconnect: function () {},
        onMessage: makeEvent(),
        onDisconnect: makeEvent(),
      };
    },
    openOptionsPage: function (cb) {
      var page =
        (manifest.options_ui && manifest.options_ui.page) ||
        manifest.options_page;
      if (page) openPage(page);
      return respond(cb);
    },
    setUninstallURL: noop,
    reload: function () {
      location.reload();
    },
    onMessage: makeEvent(),
    onMessageExternal: makeEvent(),
    onConnect: makeEvent(),
    onInstalled: makeEvent(),
    onStartup: makeEvent(),
    onSuspend: makeEvent(),
    onUpdateAvailable: makeEvent(),
  };

  var extension = {
    getURL: exUrl,
    getBackgroundPage: function () {
      return null;
    },
    getViews: function () {
      return [];
    },
    isAllowedIncognitoAccess: function (cb) {
      return respond(cb, false);
    },
    isAllowedFileSchemeAccess: function (cb) {
      return respond(cb, false);
    },
    lastError: null,
    inIncognitoContext: false,
  };

  // inert stubs
  var action = {
    onClicked: makeEvent(),
    setBadgeText: noop,
    setBadgeBackgroundColor: noop,
    setBadgeTextColor: noop,
    setTitle: noop,
    setIcon: noop,
    setPopup: noop,
    enable: noop,
    disable: noop,
    getBadgeText: function () {
      return respond(lastFn(arguments), "");
    },
    getTitle: function () {
      return respond(lastFn(arguments), "");
    },
  };

  // install
  var chromeObj = window.chrome || {};
  function define(name, value) {
    if (!chromeObj[name]) chromeObj[name] = value;
  }

  // builds a synthetic Tab object, good enough for callbacks/promises that only
  // read id/url/active. Uses a dummy id: the popup has no real tab id.
  function makeTab(id, url) {
    return {
      id: id,
      windowId: 1,
      index: 0,
      active: true,
      pinned: false,
      url: url,
      title: "",
    };
  }
  function makeTabs() {
    return {
      // fake current tab
      query: function () {
        return respond(lastFn(arguments), [makeTab(1, location.href)]);
      },
      get: function (id, cb) {
        return respond(lastFn(arguments), makeTab(id || 1, location.href));
      },
      getCurrent: function (cb) {
        return respond(lastFn(arguments), makeTab(1, location.href));
      },
      sendMessage: function () {
        // no content scripts in this browser; reply undefined so callers see a
        // failed send instead of throwing.
        return respond(lastFn(arguments), undefined);
      },
      create: function (opts, cb) {
        opts = opts || {};
        var url = opts.url ? resolveUrl(opts.url) : "about:blank";
        var tab = makeTab(2, url);
        setTimeout(function () {
          try {
            window.open(url, "_blank");
          } catch (e) {}
          onCreatedEvent.emit(tab);
        }, 0);
        return respond(cb, tab);
      },
      update: function () {
        return respond(lastFn(arguments));
      },
      onUpdated: makeEvent(),
      onRemoved: makeEvent(),
    };
  }

  function makeWindows() {
    var win = {
      id: 1,
      focused: true,
      alwaysOnTop: false,
      incognito: false,
      type: "normal",
      state: "normal",
      top: 0,
      left: 0,
      width: window.screen ? window.screen.width : 800,
      height: window.screen ? window.screen.height : 600,
    };
    return {
      // This browser only has one window; a requested window becomes a new tab.
      create: function (opts, cb) {
        opts = opts || {};
        var url = opts.url ? resolveUrl(opts.url) : "about:blank";
        setTimeout(function () {
          try {
            window.open(url, "_blank");
          } catch (e) {}
        }, 0);
        var w = {
          id: 1,
          focused: true,
          type: opts.type || "normal",
          width: opts.width,
          height: opts.height,
          top: opts.top,
          left: opts.left,
        };
        return respond(cb, w);
      },
      getCurrent: function (cb) {
        return respond(lastFn(arguments), clone(win));
      },
      getLastFocused: function (cb) {
        return respond(lastFn(arguments), clone(win));
      },
      getAll: function (cb) {
        return respond(lastFn(arguments), [clone(win)]);
      },
      update: function () {
        return respond(lastFn(arguments));
      },
      remove: function () {
        return respond(lastFn(arguments));
      },
      onCreated: makeEvent(),
      onRemoved: makeEvent(),
      onFocusChanged: makeEvent(),
    };
  }

  var onCreatedEvent = makeEvent();
  var tabs = chromeObj.tabs || {};
  var tabsShim = makeTabs();
  Object.keys(tabsShim).forEach(function (k) {
    if (tabs[k] === undefined) tabs[k] = tabsShim[k];
  });
  tabs.onCreated = onCreatedEvent;
  chromeObj.tabs = tabs;
  chromeObj.runtime = runtime;
  chromeObj.i18n = i18n;
  chromeObj.storage = storage;
  chromeObj.extension = extension;
  define("action", action);
  if (manifest.manifest_version === 2) define("browserAction", action); // MV2 only, like Chrome
  define("windows", makeWindows());
  define("scripting", {
    executeScript: function () {
      return respond(lastFn(arguments), [{ result: undefined }]);
    },
    insertCSS: function () {
      return respond(lastFn(arguments), []);
    },
    removeCSS: function () {
      return respond(lastFn(arguments));
    },
    registerContentScripts: function () {
      return respond(lastFn(arguments), []);
    },
    unregisterContentScripts: function () {
      return respond(lastFn(arguments));
    },
    updateContentScripts: function () {
      return respond(lastFn(arguments));
    },
    onMessage: makeEvent(),
  });
  define("commands", { onCommand: makeEvent() });
  define("management", { onEnabled: makeEvent(), onDisabled: makeEvent() });
  define("permissions", {
    contains: function () {
      return respond(lastFn(arguments), false);
    },
    request: function () {
      return respond(lastFn(arguments), false);
    },
  });
  window.chrome = chromeObj;
  // WebExtensions-style extensions (uBlock etc.) use `browser.*`; point it at
  // the same shim so their pages init instead of throwing on `browser.i18n`.
  if (window.browser === undefined) window.browser = chromeObj;
})();
