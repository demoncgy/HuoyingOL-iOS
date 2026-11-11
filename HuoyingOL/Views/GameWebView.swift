//
//  GameWebView.swift
//  HuoyingOL
//
//  游戏WKWebView包装视图
//  通过UIViewRepresentable桥接WebKit，注入qq-return.js、自定义UserAgent、处理多账号Cookie隔离与QQ OAuth回调
//

import SwiftUI
import WebKit

/// 游戏WKWebView包装器
/// 负责承载火影OL网页游戏界面，注入关键JS脚本，管理网络请求生命周期
struct GameWebView: UIViewRepresentable {
    @ObservedObject var viewModel: GameViewModel
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 允许内联媒体播放。wasm 和 entry.swf 都在页面内存里交给 Ruffle，不走 ruffle://。
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(RuffleSchemeHandler(), forURLScheme: RuffleSchemeHandler.scheme)
        let assetBridge = AirNativeFetchBridge()
        context.coordinator.assetBridge = assetBridge
        configuration.userContentController.add(assetBridge, name: AirNativeFetchBridge.handlerName)
        let socketBridge = AirSocketBridge()
        context.coordinator.socketBridge = socketBridge
        configuration.userContentController.add(socketBridge, name: AirSocketBridge.handlerName)
        
        // 注入 qq-return.js 脚本 (在所有子frame中执行，用于处理跨iframe登录通信)
        injectQQReturnScript(into: configuration.userContentController)
        injectRuffleScript(into: configuration.userContentController)
        // 主框架铺满屏幕：viewport-fit=cover，并按视口缩放选区页 / 游戏舞台
        injectFullscreenScript(into: configuration.userContentController)
        
        // 创建独立的或者持久化的 WKWebView
        let webView = WKWebView(frame: .zero, configuration: configuration)
        assetBridge.webView = webView
        socketBridge.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // 铺满屏幕，不把刘海/灵动岛的安全区再垫进网页视口
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.insetsLayoutMarginsFromSafeArea = false
        webView.scrollView.contentInset = .zero
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        webView.insetsLayoutMarginsFromSafeArea = false
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        
        // 默认手机 UA，避免游戏页被 narutoweb.js 判成「未安装 Flash」。
        // 点登录时再临时换成桌面 UA，见 GameViewModel.startQQLogin。
        webView.customUserAgent = AppSettings.mobileWebUserAgent
        
        // 绑定引用到 ViewModel
        viewModel.webView = webView
        
        // 监听 WebView 进度和状态
        context.coordinator.setupObservers(for: webView)
        
        // 恢复该账号持久化的 Cookie
        viewModel.restoreCookies()
        
        // 加载主页
        viewModel.loadGamePage()
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // ViewModel 驱动变更，由服务层直接执行 evaluateJavaScript
    }
    
    /// 注入 QQ 回调代理通信脚本
    private func injectQQReturnScript(into contentController: WKUserContentController) {
        var scriptSource = ""
        
        // 优先从应用 Bundle 中加载 qq-return.js
        if let fileURL = Bundle.main.url(forResource: "qq-return", withExtension: "js"),
           let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            scriptSource = content
        } else {
            // 与 Resources/qq-return.js 保持一致，Bundle 缺失时仍能登录
            scriptSource = #"""
// QQ 登录桥。登录必须留在 WKWebView 里完成。
// 拉起手机 QQ 会让回调打开到系统浏览器，qccallback 缺少 s_url，登录态回不来。
(() => {
 const home="https://huoying.qq.com", graph="https://graph.qq.com";
 const login=["https://xui.ptlogin2.qq.com","https://ssl.ptlogin2.qq.com"];
 const type="huoying-air-qq-return-v1", origin=location.origin;
 if(origin===home&&/\/comm-htdocs\/login\/qccallback\.html$/i.test(location.pathname)){
  // 手机版回调要求 s_url，官方 PC 登录不会带这个参数。锁住 isMobile，让页面自己走 parent.qqConnectCallback，且只调用一次。
  try{
   Object.defineProperty(window,"isMobile",{configurable:false,writable:false,value:function(){return false;}});
  }catch(e){
   try{
    const q=new URLSearchParams(location.search);
    const payload={code:q.get("code")||"",state:q.get("state")||"",error:q.get("error")||"",error_description:q.get("error_description")||""};
    const parentWin=window.parent;
    if(parentWin&&parentWin!==window&&typeof parentWin.qqConnectCallback==="function")parentWin.qqConnectCallback(payload);
   }catch(err){}
  }
 }
 if(window.top===window&&origin===home){
  let modeTimer,activeMode;
  function wireZoneLogin(){
   if(typeof window.loginNew!=="function"||typeof window.QcGameLogin!=="function"||window.loginNew.airNativeLogin)return;
   const original=window.loginNew;
   window.loginNew=function(id){
    const cookies=new Set(document.cookie.split(";").map(x=>x.trim().split("=")[0]));
    if(window.iUseQQConnect!=1||!cookies.has("openid")||!cookies.has("access_token"))return original.apply(this,arguments);
    if(!window.JSON_server?.[id]&&window.all_JSON_server?.[id])window.JSON_server=window.all_JSON_server;
    const server=window.JSON_server?.[id];
    if(!server||server.sServerStatus==0)return original.apply(this,arguments);
    return window.QcGameLogin(id);
   };
   window.loginNew.airNativeLogin=true;
  }
  wireZoneLogin();addEventListener("DOMContentLoaded",wireZoneLogin);addEventListener("load",wireZoneLogin);
  if(!window.loginNew?.airNativeLogin){
   const until=Date.now()+120000;
   const probe=setInterval(()=>{wireZoneLogin();if(window.loginNew?.airNativeLogin||Date.now()>until)clearInterval(probe);},250);
  }
  function send(data){
   for(const frame of document.querySelectorAll("iframe")) {
    let target;try{target=new URL(frame.src,location.href).origin;}catch{continue;}
    if(target===graph||login.includes(target))for(const destination of [graph,...login])frame.contentWindow.postMessage(data,destination);
   }
  }
  function fitLoginFrame(){
   if(!document.getElementById("air-login-fit")){
    const style=document.createElement("style");
    style.id="air-login-fit";
    style.textContent=".qConnectLogin,.qConnectLoginCover{position:fixed!important;left:0!important;top:0!important;width:100%!important;height:100%!important;}.qConnectLoginContent{width:100%!important;height:100%!important;left:0!important;top:0!important;margin:0!important;max-width:none!important;border:0!important;border-radius:0!important;}.qConnectLoginContent .loginframe,iframe.loginframe{width:100%!important;height:100%!important;}";
    (document.head||document.documentElement).appendChild(style);
   }
   const box=document.querySelector(".qConnectLoginContent");
   if(box){
    box.style.width="100%";box.style.height="100%";box.style.left="0";box.style.top="0";box.style.margin="0";
   }
   for(const frame of document.querySelectorAll("iframe.loginframe,#loginIframe")){
    frame.style.width="100%";frame.style.height="100%";
   }
  }
  window.airQqReturn={accepted:false,accept(url){
   this.accepted=false;
   send({type,action:"return",url});
  },mode(kind){
   if(kind!=="password"&&kind!=="qq")return;
   activeMode=kind;
   clearInterval(modeTimer);
   fitLoginFrame();
   const attempt=String(Date.now()),started=Date.now(),deadline=started+60000;
   let opened=false,lastOpen=0;
   modeTimer=setInterval(()=>{
    wireZoneLogin();
    fitLoginFrame();
    if(Date.now()>deadline){clearInterval(modeTimer);return;}
    const exists=[...document.querySelectorAll("iframe")].some(f=>{try{return [graph,...login].includes(new URL(f.src,location.href).origin);}catch{return false;}});
    if(exists)opened=true;
    if(!exists&&!opened&&Date.now()-started>=500&&Date.now()-lastOpen>=1000){
     lastOpen=Date.now();
     const btn=document.getElementById("dologin");
     if(btn)btn.click();
     else if(window.LoginManager&&typeof window.LoginManager.login==="function"){try{window.LoginManager.login();}catch(e){}}
    }
    send({type,action:kind,attempt});
   },250);
  }};
  addEventListener("message",e=>{
   if(e.data?.type!==type)return;
   const fromFrame=[...document.querySelectorAll("iframe")].some(f=>f.contentWindow===e.source);
   if(!fromFrame)return;
   if(e.data.action==="accepted"&&(e.origin===graph||login.includes(e.origin)))window.airQqReturn.accepted=true;
   if(e.data.action==="mode-ready"&&(e.origin===graph||login.includes(e.origin))&&activeMode==="qq")clearInterval(modeTimer);
  });return;
 }
 if(origin!==graph&&!login.includes(origin))return;
 let issued;
 function isJump(url){
  try{
   const u=new URL(url);
   return /ptlogin2\.qq\.com$/.test(u.hostname)&&u.pathname==="/jump"&&!u.username&&!u.password&&!u.hash;
  }catch(e){return false;}
 }
 function blockOneKey(){
  try{
   if(window.pt&&typeof window.pt.doOneKey==="function"&&!window.pt.doOneKey.airBlocked){
    window.pt.doOneKey=function(){};
    window.pt.doOneKey.airBlocked=true;
   }
  }catch(e){}
  const onekey=document.getElementById("onekey");
  if(onekey)onekey.style.display="none";
 }
 function revealPassword(){
  blockOneKey();
  const p=document.getElementById("p"),u=document.getElementById("u");
  const already=!!(p&&p.getBoundingClientRect().height>0);
  if(!already){
   try{if(typeof window.pt?.switchpwd==="function")window.pt.switchpwd();}catch(e){}
   const sw=document.getElementById("switcher_plogin");
   if(sw)sw.click();
   const qrSwitch=document.getElementById("qrlogin_switch");
   if(qrSwitch&&!sw)qrSwitch.click();
  }
  const qr=document.getElementById("qrlogin");
  if(qr)qr.style.display="none";
  const pwd=document.getElementById("pwdlogin")||document.getElementById("web_login");
  if(pwd)pwd.style.display="block";
  const form=document.getElementById("form_outter_wrap");
  if(form)form.style.display="block";
  const go=document.getElementById("go");
  if(go)go.style.display="block";
  const visible=!!(p&&p.getBoundingClientRect().height>0)||!!document.getElementById("switcher_plogin");
  if(!already&&p&&p.getBoundingClientRect().height>0&&u&&document.activeElement!==u&&document.activeElement!==p){try{u.focus();}catch(e){}}
  return visible;
 }
 function showQR(){
  blockOneKey();
  const toQr=document.getElementById("switcher_qlogin");
  if(toQr)toQr.click();
  try{if(typeof window.pt?.switchqr==="function")window.pt.switchqr();}catch(e){}
  const qr=document.getElementById("web_qr_login")||document.getElementById("qrlogin");
  if(qr)qr.style.display="block";
  return !!(document.getElementById("qrlogin_img")||document.getElementById("qrimg")||qr);
 }
 addEventListener("message",e=>{
  const d=e.data;if(d?.type!==type)return;
  if(origin===graph&&["accepted","mode-ready"].includes(d.action)&&login.includes(e.origin)&&
    [...document.querySelectorAll("iframe")].some(f=>f.contentWindow===e.source)){
   window.parent.postMessage({type,action:d.action},home);return;
  }
  if(e.source!==window.parent)return;
  if(origin===graph){
   if(e.origin!==home)return;
   blockOneKey();
   for(const f of document.querySelectorAll("iframe"))for(const target of login)f.contentWindow.postMessage(d,target);
  }else if((e.origin===home||e.origin===graph)&&d.action==="return"&&typeof d.url==="string"){
   if(!isJump(d.url))return;
   window.parent.postMessage({type,action:"accepted"},e.origin);location.replace(d.url);
  }else if((e.origin===home||e.origin===graph)&&typeof d.attempt==="string"){
   blockOneKey();
   if(d.action==="password"){revealPassword();return;}
   if(d.action!=="qq")return;
   const ready=showQR();
   if(!ready||issued===d.attempt)return;
   issued=d.attempt;
   window.parent.postMessage({type,action:"mode-ready"},e.origin);
  }
 });
})();
"""#
        }
        
        let userScript = WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(userScript)
    }

    /// 让选区页和游戏舞台贴着物理屏幕，而不是停在安全区或 1020×600 的最小舞台里。
    private func injectFullscreenScript(into contentController: WKUserContentController) {
        let source = #"""
        (() => {
          if (window.top !== window) return;
          var host = location.hostname;
          if (!/(^|\.)huoying\.qq\.com$/.test(host)) return;
          function installViewport() {
            var head = document.head || document.documentElement;
            var meta = document.querySelector('meta[name="viewport"]');
            if (!meta) {
              meta = document.createElement("meta");
              meta.setAttribute("name", "viewport");
              head.appendChild(meta);
            }
            meta.setAttribute("content", "width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover");
          }
          function fitGame(stage) {
            var w = window.innerWidth, h = window.innerHeight;
            if (!stage) return;
            stage.style.width = w + "px";
            stage.style.height = h + "px";
            stage.style.maxWidth = "none";
            stage.style.maxHeight = "none";
            document.documentElement.style.height = "100%";
            document.documentElement.style.overflow = "hidden";
            document.body.style.margin = "0";
            document.body.style.minWidth = "0";
            document.body.style.width = w + "px";
            document.body.style.height = h + "px";
            document.body.style.overflow = "hidden";
            document.body.style.background = "#000";
            var child = stage.firstElementChild;
            if (child) { child.style.width = w + "px"; child.style.height = h + "px"; }
          }
          function fitServer() {
            var wrap = document.querySelector(".wrap");
            if (!wrap) return;
            var design = 1000;
            var scale = window.innerWidth / design;
            wrap.style.transformOrigin = "0 0";
            wrap.style.transform = "scale(" + scale + ")";
            wrap.style.width = design + "px";
            document.documentElement.style.overflowX = "hidden";
            document.body.style.margin = "0";
            document.body.style.minWidth = "0";
            document.body.style.overflowX = "hidden";
            document.body.style.width = window.innerWidth + "px";
            document.body.style.background = "#ebebeb";
            var footer = document.getElementById("gfooter");
            if (footer) {
              footer.style.transformOrigin = "0 0";
              footer.style.transform = "scale(" + scale + ")";
              footer.style.width = design + "px";
            }
            var used = wrap.offsetHeight * scale + (footer ? footer.offsetHeight * scale : 0);
            document.body.style.height = Math.max(window.innerHeight, used) + "px";
          }
          function allowEmbeddedClient() {
            var client = window.web;
            if (!client || !client.sys) return;
            // 让 narutoweb.js 真正插入 object/embed，而不是换成「请点击安装」。
            // Ruffle 的 polyfill 会接管这些节点并播放 entry.swf。
            if (!client.sys.chrome) client.sys.chrome = "120.0.0.0";
            client.sys.playerInstalled = true;
            if (!document.getElementById("air-ruffle-fit")) {
              var style = document.createElement("style");
              style.id = "air-ruffle-fit";
              style.textContent = "#resizeTarget, #resizeTarget ruffle-player, #resizeTarget ruffle-embed, #resizeTarget object, #resizeTarget embed { width:100% !important; height:100% !important; max-width:none !important; max-height:none !important; display:block; background:#000; }";
              (document.head || document.documentElement).appendChild(style);
            }
          }
          function fit() {
            installViewport();
            if (location.hostname.indexOf("game.") === 0) allowEmbeddedClient();
            var stage = document.getElementById("resizeTarget");
            if (stage || location.hostname.indexOf("game.") === 0) fitGame(stage);
            else fitServer();
          }
          if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fit);
          window.addEventListener("load", fit);
          window.addEventListener("resize", fit);
          window.addEventListener("orientationchange", fit);
          setInterval(fit, 700);
          fit();
        })();
        """#
        contentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// 在 Ruffle 启动前把包内 wasm 写进页面内存。真机上 fetch 和 script src 都到不了 ruffle://，SWF 改走 airNativeFetch。
    private func injectRuffleScript(into contentController: WKUserContentController) {
        let wasmNames = [
            "878d548199cddef07035.wasm",
            "172de42e6619eac8f371.wasm"
        ]
        for name in wasmNames {
            guard let file = Self.ruffleResource(name),
                  let data = try? Data(contentsOf: file),
                  !data.isEmpty else {
                let missing = "console.error('[air-ruffle] missing \(name)');"
                contentController.addUserScript(WKUserScript(source: missing, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                continue
            }
            let encoded = data.base64EncodedString()
            let chunkSize = 200_000
            var cursor = encoded.startIndex
            while cursor < encoded.endIndex {
                let next = encoded.index(cursor, offsetBy: chunkSize, limitedBy: encoded.endIndex) ?? encoded.endIndex
                let chunk = String(encoded[cursor..<next])
                let source = "window.__airWasmB64=window.__airWasmB64||{};window.__airWasmB64[\"\(name)\"]=(window.__airWasmB64[\"\(name)\"]||\"\")+\"\(chunk)\";"
                contentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                cursor = next
            }
        }

        let runtime = #"""
        (() => {
          var wasmNames = ["878d548199cddef07035.wasm", "172de42e6619eac8f371.wasm"];
          function airStatus(text, ok) {
            console.log("[air-ruffle] " + text);
            function paint() {
              var parent = document.body || document.documentElement;
              if (!parent) return;
              var el = document.getElementById("air-ruffle-status");
              if (!el) {
                el = document.createElement("div");
                el.id = "air-ruffle-status";
                el.style.cssText = "position:fixed;left:8px;bottom:8px;z-index:2147483647;padding:4px 8px;font:12px/1.4 -apple-system,sans-serif;color:#fff;border-radius:6px;pointer-events:none;max-width:92vw;";
                parent.appendChild(el);
              }
              el.style.background = ok ? "rgba(10,122,50,.92)" : "rgba(160,40,40,.92)";
              el.textContent = text;
            }
            paint();
            document.addEventListener("DOMContentLoaded", paint);
          }
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
            upgradeToHttps: true,
            socketProxy: []
          });
          window.__airSockets = {};
          function queryValue(search, key) {
            var q = String(search || "");
            var mark = q.indexOf("?");
            if (mark >= 0) q = q.slice(mark + 1);
            var parts = q.split("&");
            for (var i = 0; i < parts.length; i++) {
              var eq = parts[i].indexOf("=");
              var name = eq >= 0 ? decodeURIComponent(parts[i].slice(0, eq)) : parts[i];
              if (name === key) return eq >= 0 ? decodeURIComponent(parts[i].slice(eq + 1)) : "";
            }
            return "";
          }
          function rememberSocket(host, port) {
            host = String(host || "").replace(/^\s+|\s+$/g, "");
            port = parseInt(port, 10);
            if (!host || !(port > 0 && port < 65536)) return;
            var key = host.toLowerCase() + ":" + port;
            if (window.__airSockets[key]) return;
            window.__airSockets[key] = true;
            var proxy = "ws://air.socket/connect?host=" + encodeURIComponent(host) + "&port=" + String(port);
            var list = window.RufflePlayer.config.socketProxy || [];
            list.push({ host: host, port: port, proxyUrl: proxy });
            window.RufflePlayer.config.socketProxy = list;
            console.log("[air-ruffle] socketProxy " + host + ":" + port);
            if (port !== 843) rememberSocket(host, 843);
          }
          function scanSocketText(text) {
            if (!text || text.indexOf("port=") < 0) return;
            var ip = queryValue(text, "ip") || queryValue(text, "host");
            var port = queryValue(text, "port");
            if (ip && port && ip.indexOf("://") < 0) rememberSocket(ip, port);
          }
          function scanSockets() {
            scanSocketText(location.href);
            var nodes = document.querySelectorAll("embed,object,param");
            for (var i = 0; i < nodes.length; i++) {
              var node = nodes[i];
              scanSocketText(node.src || node.data || node.value || "");
            }
          }
          rememberSocket("ied-tqosweb.qq.com", 8001);
          scanSockets();
          var socketObserver = new MutationObserver(scanSockets);
          socketObserver.observe(document.documentElement || document, { childList: true, subtree: true, attributes: true, attributeFilter: ["src", "data", "value"] });
          var OrigWebSocket = window.WebSocket;
          function bytesToB64(bytes) {
            var bin = "";
            var step = 4096;
            for (var i = 0; i < bytes.length; i += step) {
              var slice = bytes.subarray(i, Math.min(i + step, bytes.length));
              var tmp = new Array(slice.length);
              for (var j = 0; j < slice.length; j++) tmp[j] = slice[j];
              bin += String.fromCharCode.apply(null, tmp);
            }
            return btoa(bin);
          }
          function AirWebSocket(url, protocols) {
            if (!(this instanceof AirWebSocket)) return new AirWebSocket(url, protocols);
            var text = String(url || "");
            if (text.indexOf("ws://air.socket/connect") !== 0) {
              return protocols === undefined ? new OrigWebSocket(url) : new OrigWebSocket(url, protocols);
            }
            var self = this;
            this.url = text;
            this.readyState = 0;
            this.bufferedAmount = 0;
            this.extensions = "";
            this.protocol = "";
            this.binaryType = "arraybuffer";
            this.onopen = null;
            this.onmessage = null;
            this.onerror = null;
            this.onclose = null;
            this._queue = [];
            this._open = false;
            this._id = "s" + (++window.__airFetchSeq);
            window.__airSocketMap[this._id] = this;
            var host = queryValue(text, "host");
            var port = queryValue(text, "port");
            var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.airNativeSocket;
            if (!bridge) {
              this.readyState = 3;
              airStatus("socket 失败 无桥 " + host + ":" + port, false);
              return;
            }
            bridge.postMessage({ op: "open", id: this._id, host: host, port: parseInt(port, 10) || 0 });
            this.send = function (data) {
              var bytes = null;
              if (data instanceof ArrayBuffer) bytes = new Uint8Array(data);
              else if (typeof ArrayBuffer !== "undefined" && ArrayBuffer.isView && ArrayBuffer.isView(data)) bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
              if (!bytes) return;
              var b64 = bytesToB64(bytes);
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
              var fn = self["on" + type];
              if (typeof fn === "function") fn.call(self, event);
              var list = self["_on" + type] || [];
              for (var n = 0; n < list.length; n++) list[n].call(self, event);
            };
            this._nativeOpen = function () {
              self._open = true;
              self.readyState = 1;
              while (self._queue.length) bridge.postMessage({ op: "send", id: self._id, b64: self._queue.shift() });
              airStatus("socket 已连接 " + host + ":" + port, true);
              setTimeout(function () { self._emit("open", { type: "open", target: self }); }, 0);
            };
            this._nativeData = function (b64) {
              var raw = bytesFromB64(b64);
              var payload = self.binaryType === "blob" ? new Blob([raw]) : raw.buffer;
              self._emit("message", { type: "message", data: payload, target: self });
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
          window.__airSocketMap = {};
          window.__airFetchSeq = window.__airFetchSeq || 0;
          window.__airSocketEvent = function (id, type, b64) {
            var sock = window.__airSocketMap[id];
            if (!sock) return;
            if (type === "open" && sock._nativeOpen) sock._nativeOpen();
            else if (type === "data" && sock._nativeData) sock._nativeData(b64 || "");
            else if (sock._nativeClose) sock._nativeClose(type);
          };
          airStatus("正在解码 Ruffle wasm…", false);
          window.__airWasmReady = {};
          try {
            wasmNames.forEach(function (name) {
              var b64 = window.__airWasmB64 && window.__airWasmB64[name];
              if (!b64) throw new Error("missing " + name);
              var bin = atob(b64);
              var bytes = new Uint8Array(bin.length);
              var step = 32768;
              for (var i = 0; i < bin.length; i += step) {
                var end = Math.min(i + step, bin.length);
                for (var j = i; j < end; j++) bytes[j] = bin.charCodeAt(j);
              }
              window.__airWasmReady[name] = bytes;
              delete window.__airWasmB64[name];
            });
          } catch (error) {
            airStatus("wasm 失败 " + (error && error.message ? error.message : error), false);
            console.error("[air-ruffle]", error);
          }
          var ready = window.__airWasmReady;
          function requestUrl(input) {
            if (typeof input === "string") return input;
            if (typeof URL === "function" && input instanceof URL) return input.href;
            if (typeof Request === "function" && input instanceof Request) return input.url;
            if (input && input.href) return input.href;
            if (input && input.url) return input.url;
            return "";
          }
          window.__airRuffleStatus = airStatus;
          if (window.WebAssembly && WebAssembly.instantiateStreaming) {
            var origStreaming = WebAssembly.instantiateStreaming.bind(WebAssembly);
            WebAssembly.instantiateStreaming = function (source, imports) {
              return origStreaming(source, imports).catch(function () {
                return Promise.resolve(source).then(function (response) {
                  return response.arrayBuffer();
                }).then(function (buffer) {
                  return WebAssembly.instantiate(buffer, imports);
                });
              });
            };
          }
          function nativeAssetUrl(raw) {
            try {
              if (!raw) return null;
              var abs = new URL(String(raw), document.baseURI || location.href);
              if (abs.protocol !== "http:" && abs.protocol !== "https:") return null;
              var path = abs.pathname.toLowerCase();
              var host = abs.hostname.toLowerCase();
              var asset = path.indexOf(".swf") >= 0 || path.indexOf(".pkg") >= 0 || path.indexOf(".cfg") >= 0 || path.indexOf("/flash/") >= 0 || path.indexOf("/assets/") >= 0 || path.indexOf("/config/") >= 0 || path.indexOf("narutobeta") >= 0;
              if (!asset && host !== "res.huoying.qq.com" && host !== "res.huoying.com") return null;
              if (host === location.hostname.toLowerCase() || host === "game.huoying.qq.com" || host === "huoying.qq.com") {
                if (!asset) return null;
                abs = new URL("https://res.huoying.qq.com" + abs.pathname + abs.search);
              }
              return abs.href;
            } catch (e) {
              return null;
            }
          }
          window.__airFetchSeq = 0;
          window.__airNativeSlots = {};
          function bytesFromB64(b64) {
            var bin = atob(b64);
            var bytes = new Uint8Array(bin.length);
            var step = 32768;
            for (var i = 0; i < bin.length; i += step) {
              var end = Math.min(i + step, bin.length);
              for (var j = i; j < end; j++) bytes[j] = bin.charCodeAt(j) & 255;
            }
            return bytes;
          }
          window.__airNativePush = function (id, b64) {
            var slot = window.__airNativeSlots[id];
            if (slot && b64) slot.chunks.push(bytesFromB64(b64));
          };
          window.__airNativeFinish = function (id, status, mime, error) {
            var slot = window.__airNativeSlots[id];
            if (!slot) return;
            delete window.__airNativeSlots[id];
            var leafOf = function (url) {
              var leaf = String(url || "").split("?")[0];
              var slash = leaf.lastIndexOf("/");
              return (slash >= 0 ? leaf.slice(slash + 1) : leaf) || leaf;
            };
            if (error) {
              airStatus("资源失败 " + leafOf(slot.url) + " " + error, false);
              slot.reject(new Error(error));
              return;
            }
            var total = 0;
            for (var i = 0; i < slot.chunks.length; i++) total += slot.chunks[i].length;
            var bytes = new Uint8Array(total);
            var offset = 0;
            for (var k = 0; k < slot.chunks.length; k++) {
              bytes.set(slot.chunks[k], offset);
              offset += slot.chunks[k].length;
            }
            var type = mime || "application/octet-stream";
            if (String(slot.url).toLowerCase().indexOf(".swf") >= 0) type = "application/x-shockwave-flash";
            var code = status | 0;
            if (code < 200 || code > 599) code = 200;
            var response = new Response(bytes, {
              status: code,
              statusText: "OK",
              headers: {
                "Content-Type": type,
                "Content-Length": String(bytes.byteLength),
                "Access-Control-Allow-Origin": "*"
              }
            });
            console.log("[air-ruffle] native " + code + " " + bytes.byteLength + " " + slot.url);
            window.__airAssetCount = (window.__airAssetCount || 0) + 1;
            airStatus("资源 #" + window.__airAssetCount + " " + leafOf(slot.url) + " " + bytes.byteLength, code < 400);
            slot.resolve(response);
          };
          function nativeFetch(url) {
            return new Promise(function (resolve, reject) {
              var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.airNativeFetch;
              if (!bridge) {
                airStatus("swf 失败 airNativeFetch missing", false);
                reject(new Error("airNativeFetch missing"));
                return;
              }
              var id = "f" + (++window.__airFetchSeq);
              var timer = setTimeout(function () {
                if (!window.__airNativeSlots[id]) return;
                delete window.__airNativeSlots[id];
                airStatus("swf 失败 timeout", false);
                reject(new Error("native fetch timeout"));
              }, 90000);
              window.__airNativeSlots[id] = {
                url: url,
                chunks: [],
                resolve: function (response) { clearTimeout(timer); resolve(response); },
                reject: function (error) { clearTimeout(timer); reject(error); }
              };
              bridge.postMessage({ id: id, url: url });
            });
          }
          function wasmNameOf(raw) {
            var text = String(raw || "");
            var query = text.indexOf("?");
            if (query >= 0) text = text.slice(0, query);
            var slash = text.lastIndexOf("/");
            var base = slash >= 0 ? text.slice(slash + 1) : text;
            for (var i = 0; i < wasmNames.length; i++) {
              if (base === wasmNames[i]) return base;
            }
            return null;
          }
          function wasmResponse(name) {
            var bytes = ready[name];
            if (!bytes) return Promise.reject(new Error("wasm not ready " + name));
            return Promise.resolve(new Response(bytes.slice(0), {
              status: 200,
              statusText: "OK",
              headers: {
                "Content-Type": "application/wasm",
                "Content-Length": String(bytes.byteLength)
              }
            }));
          }
          var origFetch = window.fetch.bind(window);
          window.fetch = function (input, init) {
            var raw = requestUrl(input);
            var wasmName = wasmNameOf(raw);
            if (wasmName && ready[wasmName]) return wasmResponse(wasmName);
            var asset = nativeAssetUrl(raw);
            if (!asset) return origFetch(input, init);
            if (asset.toLowerCase().indexOf(".swf") >= 0) airStatus("正在下载 swf…", false);
            return nativeFetch(asset);
          };
          globalThis.fetch = window.fetch;
          var origOpen = XMLHttpRequest.prototype.open;
          var origSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function (method, url) {
            this.__airAsset = nativeAssetUrl(url);
            return origOpen.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function (body) {
            var asset = this.__airAsset;
            if (!asset) return origSend.apply(this, arguments);
            var xhr = this;
            nativeFetch(asset).then(function (resp) {
              return resp.arrayBuffer().then(function (buf) {
                var text = "";
                try { text = new TextDecoder().decode(buf); } catch (e) { text = ""; }
                try {
                  Object.defineProperty(xhr, "status", { configurable: true, get: function () { return resp.status; } });
                  Object.defineProperty(xhr, "readyState", { configurable: true, get: function () { return 4; } });
                  Object.defineProperty(xhr, "responseURL", { configurable: true, get: function () { return asset; } });
                  Object.defineProperty(xhr, "responseText", { configurable: true, get: function () { return text; } });
                  Object.defineProperty(xhr, "response", { configurable: true, get: function () {
                    if (xhr.responseType === "arraybuffer") return buf;
                    if (xhr.responseType === "blob") return new Blob([buf]);
                    return text;
                  } });
                } catch (patchError) {
                  console.warn("[air-ruffle] xhr response patch failed", patchError);
                }
                try { xhr.dispatchEvent(new Event("readystatechange")); } catch (e1) {}
                try { xhr.dispatchEvent(new ProgressEvent("load")); } catch (e2) {}
                try { xhr.dispatchEvent(new ProgressEvent("loadend")); } catch (e3) {}
                if (typeof xhr.onreadystatechange === "function") xhr.onreadystatechange();
                if (typeof xhr.onload === "function") xhr.onload();
                if (typeof xhr.onloadend === "function") xhr.onloadend();
              });
            }).catch(function (error) {
              console.error("[air-ruffle] xhr", asset, error);
              try { xhr.dispatchEvent(new ProgressEvent("error")); } catch (e4) {}
              if (typeof xhr.onerror === "function") xhr.onerror(error);
            });
          };
          if (ready["878d548199cddef07035.wasm"] && ready["172de42e6619eac8f371.wasm"]) {
            airStatus("wasm 已就绪 " + ready["878d548199cddef07035.wasm"].length + " + " + ready["172de42e6619eac8f371.wasm"].length + " bytes", true);
          }
        })();
        """#
        contentController.addUserScript(WKUserScript(source: runtime, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        for coreName in ["core.ruffle.16d61072ac7fdc4d5013.js", "core.ruffle.994eeef0a471a88cd0e3.js"] {
            if let file = Self.ruffleResource(coreName),
               let source = try? String(contentsOf: file, encoding: .utf8),
               !source.isEmpty {
                contentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
        }

        if let ruffleFile = Self.ruffleResource("ruffle.js"),
           let source = try? String(contentsOf: ruffleFile, encoding: .utf8),
           !source.isEmpty {
            contentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
    }

    private static func ruffleResource(_ name: String) -> URL? {
        if let root = Bundle.main.resourceURL?.appendingPathComponent("Ruffle", isDirectory: true) {
            let file = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
        }
        return Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Ruffle")
            ?? Bundle.main.url(forResource: name, withExtension: nil)
    }

    // MARK: - Coordinator
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var viewModel: GameViewModel
        var assetBridge: AirNativeFetchBridge?
        var socketBridge: AirSocketBridge?
        private var progressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?
        
        init(viewModel: GameViewModel) {
            self.viewModel = viewModel
            super.init()
        }
        
        deinit {
            progressObservation?.invalidate()
            titleObservation?.invalidate()
            urlObservation?.invalidate()
            loadingObservation?.invalidate()
        }
        
        func setupObservers(for webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.viewModel.updateProgress(wv.estimatedProgress)
                }
            }
            
            titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.viewModel.updateTitle(wv.title)
                }
            }
            
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.viewModel.updateURL(wv.url)
                }
            }
            
            loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.viewModel.updateLoadingState(wv.isLoading)
                }
            }
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            if alignMainFrameUserAgent(navigationAction, webView: webView) {
                decisionHandler(.cancel)
                return
            }

            if QQLoginService.isAppCallback(url) {
                viewModel.handleQQCallback(url: url)
                decisionHandler(.cancel)
                return
            }

            // wtloginmqq:// 会把登录交出去。QQ 完成后用系统浏览器打开 huoying.qq.com，
            // 那个页面没有 s_url，登录态也回不到 WebView。这里直接取消，让账号密码和扫码留在页内。
            if QQLoginService.shouldOpenExternally(url) {
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
        }

        /// 主框架离开登录域时改回手机 UA，并重发这次导航，避免游戏页继续带着桌面 Safari 标识。
        private func alignMainFrameUserAgent(_ navigationAction: WKNavigationAction, webView: WKWebView) -> Bool {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return false
            }
            let desired = AppSettings.userAgent(forMainFrame: url)
            guard webView.customUserAgent != desired else { return false }
            webView.customUserAgent = desired
            webView.load(navigationAction.request)
            return true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.updateLoadingState(false)
            viewModel.onPageFinishLoad()
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled || nsError.code == 102 {
                viewModel.updateLoadingState(false)
                return
            }
            viewModel.updateLoadingState(false)
            viewModel.errorMessage = error.localizedDescription
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if let failed = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL, QQLoginService.shouldOpenExternally(failed) {
                viewModel.updateLoadingState(false)
                return
            }
            // 自定义 scheme 被取消时 WebKit 会报帧加载中断，不必当成页面错误弹出来。
            if nsError.code == NSURLErrorCancelled || nsError.code == 102 {
                viewModel.updateLoadingState(false)
                return
            }
            viewModel.updateLoadingState(false)
            viewModel.errorMessage = error.localizedDescription
        }
        
        // MARK: - WKUIDelegate (处理 window.open / 弹窗)
        
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            if QQLoginService.isAppCallback(url) {
                viewModel.handleQQCallback(url: url)
                return nil
            }
            if QQLoginService.shouldOpenExternally(url) {
                return nil
            }
            // 只把真正的网页弹窗留在当前 WebView。about:blank 会把选区页替换掉。
            let scheme = url.scheme?.lowercased() ?? ""
            if navigationAction.targetFrame == nil, scheme == "http" || scheme == "https" {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
