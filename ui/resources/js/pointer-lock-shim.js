(function () {
  if (window.__illuminatePointerLockInstalled) return;
  window.__illuminatePointerLockInstalled = true;
  var locked = false;
  var elem = null;
  var REQ = "__illuminate_plock_req__";
  var EXIT = "__illuminate_plock_exit__";
  function signal(m) { try { console.debug(m); } catch (e) {} }
  function fireLockChange() {
    try {
      var ev = new Event("pointerlockchange");
      if (elem && elem.dispatchEvent) elem.dispatchEvent(ev);
      document.dispatchEvent(ev);
    } catch (e) {}
  }
  try {
    Object.defineProperty(document, "pointerLockElement", {
      configurable: true,
      get: function () { return locked ? elem : null; }
    });
  } catch (e) {}
  try {
    Object.defineProperty(Element.prototype, "requestPointerLock", {
      configurable: true,
      writable: true,
      value: function (options) {
        if (locked) return;
        locked = true;
        elem = this || document.documentElement;
        signal(REQ);
        fireLockChange();
      }
    });
    Object.defineProperty(Document.prototype, "exitPointerLock", {
      configurable: true,
      writable: true,
      value: function () {
        if (locked) { locked = false; signal(EXIT); fireLockChange(); }
      }
    });
  } catch (e) {}
  function dispatchDelta(dx, dy) {
    if (!locked || !elem) return;
    var opts = { movementX: dx, movementY: dy, bubbles: true, cancelable: true,
                 button: 0, buttons: 0 };
    try { elem.dispatchEvent(new MouseEvent("mousemove", opts)); } catch (e) {}
    try {
      if ("PointerEvent" in window)
        elem.dispatchEvent(new PointerEvent("pointermove", {
          movementX: dx, movementY: dy, bubbles: true, cancelable: true,
          button: 0, buttons: 0, pointerId: 1, pointerType: "mouse", isPrimary: true,
          clientX: 0, clientY: 0, screenX: 0, screenY: 0
        }));
    } catch (e) {}
  }
  window.__illuminate__onLockDelta = dispatchDelta;
  window.__illuminate__forceExit = function () {
    if (!locked) return;
    locked = false;
    signal(EXIT);
    fireLockChange();
  };
})();