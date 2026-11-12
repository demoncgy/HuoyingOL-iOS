/*
 * air-boot.js -- iOS 启动层，按 OL-AIR-2.4.apk 的 airgame.bridge 架构重写
 *
 * 安卓 APK 的真实做法（来自 assets/MobileGame.swf 常量池）：
 *   1. 网页完成 QQ 登录，产出会话 {account, entryURL, parameters, pageParameters, cookies, userAgent}
 *   2. 原生/AIR 侧下载官方 entry.swf 字节，运行时补版本、补参数后启动，不依赖 <base>
 *   3. RuntimeAdapter.Socket / URLLoader / ExternalInterface 全部由原生接管
 *   4. 网关域名 zone.huoying.qq.com 写死，HTTPDNS /d?dn= 自行修正
 *
 * iOS 没有 AIR 运行时，因此用 WKWebView + Ruffle 承载 SWF，用 Swift 原生 bridge 做等价的事：
 *   AirNativeFetchBridge (airNativeFetch)  -> 资源下载 / HTTPDNS
 *   AirSocketBridge      (airNativeSocket) -> TCP 直连游戏服务器
 *   本文件负责会话构造、参数注入、URL 绝对化与网络接管。
 */
(() => {
  "use strict";

  // ------------------------------------------------------------------
  // 1. APK 2.4 逆向得到的确定值
  // ------------------------------------------------------------------
  const APK = {
    ip: "zone.huoying.qq.com",
    host: "https://res.huoying.qq.com",
    cdn: "https://res.huoying.qq.com/",
    versionFile: "version.js",
    // fcgi 实测端口：随区服变化且无公式，这里存实测值，其余按 10000+zone_id 估算。
    ports: {
      1: "10001", 2: "10001", 3: "10001", 10: "10001", 100: "10073",
      201: "10157", 401: "10383", 601: "10581", 801: "10800",
      1001: "10991", 1101: "11099", 6001: "16001", 8001: "18001", 8999: "18976"
    },
    defaultZone: 1101,
    httpDns: "http://182.254.116.117/d"
  };

  function serverPortFor(zone) {
    const n = parseInt(zone, 10);
    if (!n || n < 1) return APK.ports[APK.defaultZone];
    return APK.ports[String(n)] || String(10000 + n);
  }

  function zoneFromLocation(href) {
    try {
      const u = new URL(href);
      const v = parseInt(u.searchParams.get("zone_id") || "", 10);
      return v > 0 ? v : APK.defaultZone;
    } catch (e) { return APK.defaultZone; }
  }

  // 把 narutoweb.js 生成的相对 entry 地址变成绝对地址，并保证参数里没有 null。
  // 用字符串级修正而不是 new URL() 重建：官方串里 host=https://... 未编码，
  // URL 对象会把它变成 %3A%2F%2F，与官方 SWF 的解析习惯不一致。
  function buildEntryUrl(raw, web) {
    let text = String(raw || "");
    if (!text) return "";
    const zone = zoneFromLocation(location.href);
    const put = (key, value) => {
      const present = new RegExp("([?&]" + key + "=)([^&]*)", "i");
      const bad = /^(|null|undefined)$/i;
      if (present.test(text)) {
        text = text.replace(present, (m, head, old) => head + (bad.test(old) ? value : old));
      } else {
        text += (text.indexOf("?") >= 0 ? "&" : "?") + key + "=" + value;
      }
    };
    put("zone_id", String(zone));
    put("ip", APK.ip);
    put("port", serverPortFor(zone));
    put("host", APK.host);
    if (!/^https?:\/\//i.test(text)) text = APK.cdn + text.replace(/^\/+/, "");
    return text;
  }

  // 官方 HTTPDNS 只提供 http。Ruffle 的 upgradeToHttps 会把 IP 请求升级为 https 导致证书失败。
  function fixHttpDns(raw) {
    try {
      const abs = new URL(String(raw), document.baseURI || location.href);
      if (abs.pathname !== "/d" || !abs.searchParams.has("dn")) return null;
      const dn = abs.searchParams.get("dn") || "";
      if (!dn || dn === "null" || dn === "undefined" || dn === "0") {
        abs.searchParams.set("dn", APK.ip);
      }
      abs.protocol = "http:";
      return abs.href;
    } catch (e) { return null; }
  }

  function absolutizeMovie(raw) {
    try {
      const abs = new URL(String(raw), document.baseURI || location.href);
      if (abs.protocol !== "http:" && abs.protocol !== "https:") return String(raw);
      if (abs.hostname === location.hostname ||
          abs.hostname === "game.huoying.qq.com" ||
          abs.hostname === "huoying.qq.com") {
        return APK.host + abs.pathname + abs.search;
      }
      return abs.href;
    } catch (e) { return String(raw); }
  }

  function isAssetUrl(abs) {
    const path = abs.pathname.toLowerCase();
    const host = abs.hostname.toLowerCase();
    if (path.indexOf(".swf") >= 0 || path.indexOf(".pkg") >= 0 || path.indexOf(".cfg") >= 0) return true;
    if (path.indexOf("/flash/") >= 0 || path.indexOf("/assets/") >= 0 || path.indexOf("/config/") >= 0) return true;
    if (path.indexOf("narutobeta") >= 0) return true;
    return host === "res.huoying.qq.com" || host === "res.huoying.com";
  }

  function nativeAssetUrl(raw, base) {
    try {
      const abs = new URL(String(raw), base || document.baseURI || location.href);
      if (abs.protocol !== "http:" && abs.protocol !== "https:") return null;
      if (!isAssetUrl(abs)) return null;
      if (abs.hostname === location.hostname ||
          abs.hostname === "game.huoying.qq.com" ||
          abs.hostname === "huoying.qq.com") {
        return APK.host + abs.pathname + abs.search;
      }
      return abs.href;
    } catch (e) { return null; }
  }

  function looseNativeUrl(raw, base) {
    try {
      const abs = new URL(String(raw), base || document.baseURI || location.href);
      if (abs.protocol !== "http:" && abs.protocol !== "https:") return null;
      const host = abs.hostname.toLowerCase();
      if (host === "qq.com" || host.slice(-7) === ".qq.com") return abs.href;
      const parts = host.split(".");
      if (parts.length === 4 && parts.every((p) => /^[0-9]{1,3}$/.test(p))) return abs.href;
      return null;
    } catch (e) { return null; }
  }

  // ------------------------------------------------------------------
  // 2. 屏幕诊断（状态条 + 轻点展开日志）
  // ------------------------------------------------------------------
  const logs = [];
  let overlay = null;
  function stamp() {
    const d = new Date();
    const p = (n) => ("0" + n).slice(-2);
    return p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds());
  }
  function log(level, text) {
    try {
      const line = String(text).replace(/\s+/g, " ").slice(0, 400);
      logs.push(stamp() + " [" + level + "] " + line);
      if (logs.length > 200) logs.shift();
      console.log("[air-boot] " + line);
      if (overlay) renderOverlay();
    } catch (e) {}
  }
  function airStatus(text, ok) {
    log(ok ? "I" : "W", text);
    try {
      const parent = document.body || document.documentElement;
      if (!parent) return;
      let el = document.getElementById("air-ruffle-status");
      if (!el) {
        el = document.createElement("div");
        el.id = "air-ruffle-status";
        el.style.cssText = "position:fixed;left:8px;bottom:8px;z-index:2147483647;padding:4px 8px;" +
          "font:12px/1.4 -apple-system,sans-serif;color:#fff;border-radius:6px;max-width:92vw;";
        el.addEventListener("click", toggleOverlay, { passive: true });
        parent.appendChild(el);
      }
      el.style.background = ok ? "rgba(10,122,50,.92)" : "rgba(160,40,40,.92)";
      el.textContent = text;
    } catch (e) {}
  }
  function renderOverlay() {
    if (!overlay) return;
    overlay.textContent = "火影OL 诊断日志（" + logs.length + " 条，轻点关闭）\n\n" + logs.join("\n");
    overlay.scrollTop = overlay.scrollHeight;
  }
  function toggleOverlay() {
    if (overlay) { overlay.remove(); overlay = null; return; }
    try {
      overlay = document.createElement("pre");
      overlay.style.cssText = "position:fixed;inset:8%;z-index:2147483646;overflow:auto;white-space:pre-wrap;" +
        "background:rgba(12,12,14,.96);color:#e8e8e8;font:11px/1.5 monospace;padding:12px;border-radius:8px;";
      overlay.addEventListener("click", toggleOverlay, { passive: true });
      (document.body || document.documentElement).appendChild(overlay);
      renderOverlay();
    } catch (e) {}
  }
  if (window.top === window) {
    const origError = console.error;
    console.error = function () {
      log("E", Array.prototype.map.call(arguments, String).join(" "));
      origError.apply(console, arguments);
    };
    window.addEventListener("error", (e) => log("E", "window.error " + (e.message || "")));
    window.addEventListener("unhandledrejection", (e) => log("E", "promise " + String(e.reason || "")));
  }

  // ------------------------------------------------------------------
  // 3. Ruffle 运行时配置（对齐 APK 的 RuntimeAdapter）
  // ------------------------------------------------------------------
  window.RufflePlayer = window.RufflePlayer || {};
  window.RufflePlayer.config = Object.assign({}, window.RufflePlayer.config, {
    publicPath: "",
    polyfills: true,
    autoplay: "on",
    unmuteOverlay: "hidden",
    splashScreen: false,
    letterbox: "off",
    scale: "exactFit",
    forceScale: true,
    wmode: "opaque",
    quality: "high",
    warnOnUnsupportedContent: false,
    openUrlMode: "allow",
    allowNetworking: "all",
    // 关键：官方 HTTPDNS 是 http://<IP>/d，升级到 https 会因证书不匹配失败。
    upgradeToHttps: false,
    socketProxy: []
  });

  // 主动注册网关 socket 代理，不依赖扫描 DOM 标签（Ruffle 走 JS API 时扫不到）。
  function registerSocketProxy(host, port) {
    const h = String(host || "").trim();
    const p = parseInt(port, 10);
    if (!h || !(p > 0 && p < 65536)) return;
    const list = window.RufflePlayer.config.socketProxy || [];
    const exists = list.some((x) => x.host === h && x.port === p);
    if (!exists) {
      list.push({
        host: h,
        port: p,
        proxyUrl: "ws://air.socket/connect?host=" + encodeURIComponent(h) + "&port=" + p
      });
      window.RufflePlayer.config.socketProxy = list;
      log("I", "socketProxy " + h + ":" + p);
    }
    if (p !== 843) {
      const has843 = list.some((x) => x.host === h && x.port === 843);
      if (!has843) list.push({
        host: h, port: 843,
        proxyUrl: "ws://air.socket/connect?host=" + encodeURIComponent(h) + "&port=843"
      });
    }
  }

  // ------------------------------------------------------------------
  // 4. 原生 fetch 桥（AirNativeFetchBridge）
  // ------------------------------------------------------------------
  let fetchSeq = 0;
  const nativeSlots = {};
  window.__airFetchSeq = 0;
  window.__airSocketMap = {};

  function bytesFromB64(b64) {
    const bin = atob(b64 || "");
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i) & 255;
    return out;
  }
  function bytesToB64(bytes) {
    let bin = "";
    const step = 4096;
    for (let i = 0; i < bytes.length; i += step) {
      const slice = bytes.subarray(i, Math.min(i + step, bytes.length));
      const tmp = new Array(slice.length);
      for (let j = 0; j < slice.length; j++) tmp[j] = slice[j];
      bin += String.fromCharCode.apply(null, tmp);
    }
    return btoa(bin);
  }
  window.__airNativePush = function (id, b64) {
    const slot = nativeSlots[id];
    if (slot && b64) slot.chunks.push(bytesFromB64(b64));
  };
  window.__airNativeFinish = function (id, status, mime, error) {
    const slot = nativeSlots[id];
    if (!slot) return;
    delete nativeSlots[id];
    if (error) {
      airStatus("资源失败 " + slot.url.split("/").pop().split("?")[0] + " " + error, false);
      slot.reject(new Error(error));
      return;
    }
    let total = 0;
    for (const c of slot.chunks) total += c.length;
    const all = new Uint8Array(total);
    let off = 0;
    for (const c of slot.chunks) { all.set(c, off); off += c.length; }
    log("I", "native " + status + " " + total + " " + slot.url.slice(0, 160));
    if (status >= 400) airStatus("资源 HTTP " + status + " " + slot.url.split("/").pop(), false);
    slot.resolve(new Response(all.slice(0), {
      status: status >= 100 ? status : 200,
      headers: { "Content-Type": mime || "application/octet-stream" }
    }));
  };
  window.__airAssetCount = 0;

  function nativeFetch(url) {
    return new Promise((resolve, reject) => {
      const bridge = window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.airNativeFetch;
      if (!bridge) { reject(new Error("airNativeFetch missing")); return; }
      const id = "f" + (++fetchSeq);
      const timer = setTimeout(() => {
        if (!nativeSlots[id]) return;
        delete nativeSlots[id];
        reject(new Error("native fetch timeout"));
      }, 90000);
      nativeSlots[id] = {
        url: String(url), chunks: [],
        resolve: (r) => { clearTimeout(timer); resolve(r); },
        reject: (e) => { clearTimeout(timer); reject(e); }
      };
      bridge.postMessage({ id: id, url: String(url) });
    });
  }

  // ------------------------------------------------------------------
  // 4b. wasm 字节：Ruffle 真正初始化时按需向 App Bundle 取
  // 不再用 WKUserScript 把 28MB 二进制（38MB base64）灌进每个页面，
  // 那样登录页也要付一次内存/解析代价，还容易撞 WebKit 注入体积上限。
  // AirBundleBridge 逐块回传 base64，这里逐块 atob，避免生成 38MB 的中间字符串。
  // ------------------------------------------------------------------
  const wasmNames = ["878d548199cddef07035.wasm", "172de42e6619eac8f371.wasm"];
  const wasmCache = {};
  const bundleSlots = {};
  let bundleSeq = 0;
  // ruffle.js 的加载补丁读的就是这个表，必须与它对齐。
  window.__airWasmReady = wasmCache;
  window.__airRuffleStatus = airStatus;

  function decodeChunk(chunk) {
    const bin = atob(chunk);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i) & 255;
    return out;
  }
  window.__airBundlePush = function (id, chunk) {
    const slot = bundleSlots[id];
    if (!slot || !chunk) return;
    try { slot.parts.push(decodeChunk(chunk)); }
    catch (e) { slot.error = String(e); }
  };
  window.__airBundleFinish = function (id, error) {
    const slot = bundleSlots[id];
    if (!slot) return;
    delete bundleSlots[id];
    clearTimeout(slot.timer);
    if (error || slot.error) { slot.reject(new Error(error || slot.error)); return; }
    let total = 0;
    for (const part of slot.parts) total += part.length;
    const all = new Uint8Array(total);
    let off = 0;
    for (const part of slot.parts) { all.set(part, off); off += part.length; }
    if (!all.length) { slot.reject(new Error("empty wasm")); return; }
    wasmCache[slot.name] = all;
    log("I", "wasm 就绪 " + slot.name + " " + all.length + " bytes");
    airStatus("wasm 已载入 " + slot.name.slice(0, 8) + " " + all.length + " bytes", true);
    slot.resolve(all);
  };

  window.__airLoadWasm = function (name) {
    if (wasmCache[name]) return Promise.resolve(wasmCache[name]);
    // 兼容旧版可能仍在页面里的内联 base64（WKUserScript 注入路径）。
    const inline = (window.__airWasmB64 || {})[name];
    if (inline) {
      try {
        const bytes = bytesFromB64(inline);
        wasmCache[name] = bytes;
        return Promise.resolve(bytes);
      } catch (e) { log("E", "内联 wasm 解码失败 " + e); }
    }
    return new Promise((resolve, reject) => {
      const bridge = window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.airNativeBundle;
      if (!bridge) { reject(new Error("airNativeBundle 桥缺失")); return; }
      const id = "w" + (++bundleSeq);
      const timer = setTimeout(() => {
        if (!bundleSlots[id]) return;
        delete bundleSlots[id];
        reject(new Error("wasm 读取超时 " + name));
      }, 60000);
      bundleSlots[id] = { name: name, parts: [], resolve: resolve, reject: reject, timer: timer, error: null };
      log("I", "请求 bundle wasm " + name);
      bridge.postMessage({ id: id, name: name });
    });
  };

  function wasmNameOf(raw) {
    const clean = String(raw || "").split("?")[0];
    const base = clean.slice(clean.lastIndexOf("/") + 1);
    return wasmNames.indexOf(base) >= 0 ? base : null;
  }

  const origFetch = window.fetch.bind(window);
  window.fetch = function (input, init) {
    const raw = typeof input === "string" ? input : (input && input.url) || String(input);
    const wname = wasmNameOf(raw);
    // 双保险：万一 Ruffle 走的是 wasm-bindgen 默认的 fetch(URL) 路径，也能拿到字节。
    if (wname) {
      return window.__airLoadWasm(wname).then((bytes) => new Response(bytes.slice(0), {
        status: 200, headers: { "Content-Type": "application/wasm" }
      }));
    }
    const dns = fixHttpDns(raw);
    if (dns) {
      log("I", "HTTPDNS 原生 " + dns);
      return nativeFetch(dns);
    }
    const asset = nativeAssetUrl(raw);
    if (asset) {
      if (asset.toLowerCase().indexOf(".swf") >= 0) airStatus("正在下载 swf…", false);
      return nativeFetch(asset);
    }
    const direct = origFetch(input, init);
    if (init && init.body) return direct;
    return direct.catch((error) => {
      const loose = looseNativeUrl(raw);
      if (!loose) throw error;
      log("W", "fetch 回退原生 " + String(raw).slice(0, 140));
      return nativeFetch(loose);
    });
  };
  globalThis.fetch = window.fetch;

  // ------------------------------------------------------------------
  // 5. WebSocket 桥（AirSocketBridge / NWConnection）
  // ------------------------------------------------------------------
  const OrigWebSocket = window.WebSocket;
  function queryValue(search, key) {
    let q = String(search || "");
    const mark = q.indexOf("?");
    if (mark >= 0) q = q.slice(mark + 1);
    for (const part of q.split("&")) {
      const eq = part.indexOf("=");
      const name = eq >= 0 ? decodeURIComponent(part.slice(0, eq)) : part;
      if (name === key) return eq >= 0 ? decodeURIComponent(part.slice(eq + 1)) : "";
    }
    return "";
  }
  function AirWebSocket(url, protocols) {
    if (!(this instanceof AirWebSocket)) return new AirWebSocket(url, protocols);
    const text = String(url || "");
    if (text.indexOf("ws://air.socket/connect") !== 0) {
      return protocols === undefined ? new OrigWebSocket(url) : new OrigWebSocket(url, protocols);
    }
    const self = this;
    const host = queryValue(text, "host");
    const port = queryValue(text, "port");
    const bridge = window.webkit && window.webkit.messageHandlers &&
      window.webkit.messageHandlers.airNativeSocket;
    this.url = text;
    this.readyState = 0;
    this.bufferedAmount = 0;
    this.extensions = "";
    this.protocol = "";
    this.binaryType = "arraybuffer";
    this.onopen = this.onmessage = this.onerror = this.onclose = null;
    this._id = "s" + (++window.__airFetchSeq);
    this._queue = [];
    this._open = false;
    window.__airSocketMap[this._id] = this;
    if (!bridge) {
      this.readyState = 3;
      airStatus("socket 失败 无原生桥 " + host + ":" + port, false);
      return;
    }
    bridge.postMessage({ op: "open", id: this._id, host: host, port: parseInt(port, 10) || 0 });
    this.send = function (data) {
      let bytes = null;
      if (data instanceof ArrayBuffer) bytes = new Uint8Array(data);
      else if (ArrayBuffer.isView && ArrayBuffer.isView(data)) {
        bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
      }
      if (!bytes) return;
      const b64 = bytesToB64(bytes);
      if (!self._open) self._queue.push(b64);
      else bridge.postMessage({ op: "send", id: self._id, b64: b64 });
    };
    this.close = function () {
      self.readyState = 2;
      bridge.postMessage({ op: "close", id: self._id });
    };
    this.addEventListener = function (type, fn) {
      self["_on" + type] = self["_on" + type] || [];
      self["_on" + type].push(fn);
    };
    this.removeEventListener = function () {};
    this._emit = function (type, event) {
      const fn = self["on" + type];
      if (typeof fn === "function") fn.call(self, event);
      const list = self["_on" + type] || [];
      for (const f of list) f.call(self, event);
    };
    this._nativeOpen = function () {
      self._open = true;
      self.readyState = 1;
      while (self._queue.length) bridge.postMessage({ op: "send", id: self._id, b64: self._queue.shift() });
      airStatus("socket 已连接 " + host + ":" + port, true);
      setTimeout(() => self._emit("open", { type: "open", target: self }), 0);
    };
    this._nativeData = function (b64) {
      const raw = bytesFromB64(b64);
      self._emit("message", { type: "message", data: raw.buffer, target: self });
    };
    this._nativeClose = function (kind) {
      self._open = false;
      self.readyState = 3;
      delete window.__airSocketMap[self._id];
      if (kind === "error") {
        airStatus("socket 失败 " + host + ":" + port, false);
        self._emit("error", { type: "error", target: self });
      }
      self._emit("close", { type: "close", target: self });
    };
  }
  AirWebSocket.CONNECTING = 0;
  AirWebSocket.OPEN = 1;
  AirWebSocket.CLOSING = 2;
  AirWebSocket.CLOSED = 3;
  AirWebSocket.prototype = OrigWebSocket ? OrigWebSocket.prototype : {};
  window.WebSocket = AirWebSocket;
  window.__airSocketEvent = function (id, type, b64) {
    const sock = window.__airSocketMap[id];
    if (!sock) return;
    if (type === "open" && sock._nativeOpen) sock._nativeOpen();
    else if (type === "data" && sock._nativeData) sock._nativeData(b64 || "");
    else if (sock._nativeClose) sock._nativeClose(type);
  };

  // ------------------------------------------------------------------
  // 6. 会话层：接管 naruto.Web（对应 APK 的 huoyingair-session）
  // ------------------------------------------------------------------
  window.__airAbsUrl = (raw) => absolutizeMovie(raw);

  let webPatched = false;
  function patchNarutoWeb(w) {
    if (!w || webPatched || typeof w.getEntrySwfUrl !== "function") return;
    webPatched = true;
    const zone = zoneFromLocation(location.href);
    const port = serverPortFor(zone);

    // APK 同款：参数在实例创建瞬间确定，fcgi 只用于校正端口，不决定能否启动。
    w.zone_id = zone;
    w.ip = APK.ip;
    w.host = APK.host;
    w.port = port;
    w.versionFileName = APK.versionFile;
    registerSocketProxy(APK.ip, port);
    log("I", "APK 会话 account=web ip=" + w.ip + " port=" + w.port + " zone=" + zone);

    const origUrl = w.getEntrySwfUrl;
    w.getEntrySwfUrl = function () {
      const url = buildEntryUrl(origUrl.apply(this, arguments), this);
      log("I", "entry 绝对化 " + url.slice(0, 230));
      registerSocketProxy(new URL(url).searchParams.get("ip"), new URL(url).searchParams.get("port"));
      return url;
    };

    const origServerInfo = w.getServerInfo;
    w.getServerInfo = function (callback) {
      const obj = this;
      let done = false, accurate = false;
      const finish = (from) => {
        if (done) return;
        done = true;
        const z = parseInt(obj.zone_id, 10) || zone;
        if (!obj.ip || obj.ip === "null") obj.ip = APK.ip;
        if (!obj.port || obj.port === "null") obj.port = serverPortFor(z);
        if (!obj.host || obj.host === "null") obj.host = APK.host;
        if (!obj.versionFileName || obj.versionFileName === "null") obj.versionFileName = APK.versionFile;
        registerSocketProxy(obj.ip, obj.port);
        log("I", "区服信息(" + from + ") " + obj.ip + ":" + obj.port + " host=" + obj.host);
        try { callback(); } catch (e) { log("E", "启动回调异常 " + e); }
      };
      let fcgi = "";
      try { fcgi = obj.getBaseLocation() + "/fcgi-bin/query_svr_info.fcgi?svr_id=" + obj.zone_id; } catch (e) {}
      if (fcgi) {
        nativeFetch(fcgi).then((r) => r.text()).then((text) => {
          const arr = JSON.parse(text);
          if (arr && arr.length >= 4 && arr[0] && arr[0] !== "null") {
            obj.$parseResult(arr);
            accurate = true;
            finish("fcgi");
          }
        }).catch((e) => log("W", "fcgi 失败 " + e));
      }
      try { origServerInfo.call(obj, () => { if (!accurate) finish("ajax"); }); } catch (e) {}
      // 绝不无限等待：2.5 秒后一律按 APK 参数启动。
      setTimeout(() => { if (!done) { log("W", "fcgi 超时，采用 APK 参数"); finish("apk"); } }, 2500);
    };

    const origCreate = w.createEntrySwfObject;
    if (typeof origCreate === "function") {
      w.createEntrySwfObject = function (attributes, param, id, a) {
        try {
          if (attributes && attributes.data && param && !param.flashvars) {
            const mark = String(attributes.data).indexOf("?");
            if (mark >= 0) {
              param.flashvars = String(attributes.data).slice(mark + 1);
              log("I", "flashvars 已注入 " + param.flashvars.slice(0, 160));
            }
          }
        } catch (e) {}
        return origCreate.apply(this, arguments);
      };
    }
    log("I", "naruto.Web 已接管 " + location.href.slice(0, 150));
  }

  // narutoweb.js 末尾是全局 `var web = new naruto.Web()`；访问器在赋值瞬间接管。
  let webValue;
  try {
    Object.defineProperty(window, "web", {
      configurable: true,
      get: () => webValue,
      set: (v) => { webValue = v; try { patchNarutoWeb(v); } catch (e) { log("E", "web 接管 " + e); } }
    });
    log("I", "window.web 访问器已安装");
  } catch (e) { log("E", "访问器失败 " + e); }
  setInterval(() => { try { patchNarutoWeb(window.web); } catch (e) {} }, 250);

  // ------------------------------------------------------------------
  // 7. 心跳 + 测试接口
  // ------------------------------------------------------------------
  setInterval(() => {
    try {
      const players = document.querySelectorAll("ruffle-embed, ruffle-player, embed, object");
      const socks = Object.keys(window.__airSocketMap || {}).length;
      const proxies = (window.RufflePlayer.config.socketProxy || []).length;
      log("I", "心跳 资源=" + (window.__airAssetCount || 0) + " 播放器=" + players.length +
        " socketProxy=" + proxies + " 活跃socket=" + socks + " 日志=" + logs.length);
    } catch (e) {}
  }, 10000);

  window.__airBoot = {
    APK,
    serverPortFor,
    zoneFromLocation,
    buildEntryUrl,
    fixHttpDns,
    absolutizeMovie,
    nativeAssetUrl,
    looseNativeUrl,
    registerSocketProxy,
    nativeFetch,
    loadWasm: window.__airLoadWasm,
    wasmCache,
    logs,
    log
  };
  airStatus("air-boot v3.1 已启动（wasm 走 bundle 桥 / 分块已预注入）", true);
})();
