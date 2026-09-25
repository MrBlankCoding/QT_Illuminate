(function () {
  var host = window.DevToolsHost;
  if (!host || !host.sendMessageToEmbedder) return;
  var send = host.sendMessageToEmbedder.bind(host);
  host.sendMessageToEmbedder = function (json) {
    try {
      var m = JSON.parse(json);
      if (m.method === "setPreference" && m.params && m.params[0] === "currentDockState")
        console.debug("__ILLUMINATE_DOCK_MARKER__" + JSON.parse(m.params[1]));
    } catch (e) {}
    return send(json);
  };
})();