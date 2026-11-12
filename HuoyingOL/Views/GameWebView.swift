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
        
        // 屏幕日志诊断层必须第一个注入：这样 ruffle.js / 运行时在启动阶段打出的日志
        // 也能被捕获，否则排查时永远看不到「组件已定义 / 已接管」这类关键行。
        injectDiagnosticsScript(into: configuration.userContentController)
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
          // 浏览器 fetch 失败后的兜底：腾讯系域名和纯 IP 的接口都允许走原生 URLSession。
          function looseNativeUrl(raw) {
            try {
              if (!raw) return null;
              var abs = new URL(String(raw), document.baseURI || location.href);
              if (abs.protocol !== "http:" && abs.protocol !== "https:") return null;
              var host = abs.hostname.toLowerCase();
              if (host === "qq.com" || host.slice(-7) === ".qq.com") return abs.href;
              var parts = host.split(".");
              if (parts.length === 4 && parts.every(function (p) { return /^[0-9]{1,3}$/.test(p); })) return abs.href;
              return null;
            } catch (e) {
              return null;
            }
          }
          // === 依据 OL-AIR-2.4.apk / assets/MobileGame.swf 的 airgame.bridge 常量池 ===
          // 安卓版不依赖 query_svr_info.fcgi：网关域名 zone.huoying.qq.com 写死在 SWF 里，
          // 并由 OfficialResources 拦截 http://182.254.116.117/d?dn=<host> 自行修正 HTTPDNS。
          // iOS 网页版的 fcgi 一旦失败，web.ip 保持 null，游戏就会请求 dn=null 并卡死。
          // 这里把同一套确定值内置进来，fcgi 只用于修正端口，不再决定能否启动。
          window.__airApk = {
            ip: "zone.huoying.qq.com",
            host: "https://res.huoying.qq.com",
            cdn: "https://res.huoying.qq.com/",
            versionFile: "version.js",
            // 官网 fcgi 实测值；其余区服按 10000+zone_id 估算（新区服完全吻合）。
            portFor: function (z) {
              var n = parseInt(z, 10);
              if (!n || n < 1) n = 1101;
              var known = {1:"10001",2:"10001",3:"10001",10:"10001",100:"10073",
                           201:"10157",401:"10383",601:"10581",801:"10800",
                           1001:"10991",1101:"11099",6001:"16001",8001:"18001",8999:"18976"};
              return known[String(n)] || String(10000 + n);
            }
          };
          // 游戏用腾讯 HTTPDNS 解析区服域名。参数丢失时会请求 dn=null，
          // WebView 里还会被混合内容/CORS 挡掉。这里修正 dn 并直接走原生 URLSession。
          function httpDnsUrl(raw) {
            try {
              var abs = new URL(String(raw), document.baseURI || location.href);
              if (abs.pathname !== "/d" || !abs.searchParams.has("dn")) return null;
              var dn = abs.searchParams.get("dn") || "";
              if (!dn || dn === "null" || dn === "undefined" || dn === "0") {
                abs.searchParams.set("dn", window.__airApk.ip);
                console.log("[air-ruffle] HTTPDNS dn 修正 '" + dn + "' -> " + window.__airApk.ip);
              }
              // 官方 HTTPDNS 只提供 http；游戏里出现的 https://<IP>/d 会因证书不匹配失败。
              abs.protocol = "http:";
              return abs.href;
            } catch (e) { return null; }
          }
          window.__airFetchSeq = 0;
          window.__airNativeSlots = {};
          // Ruffle 0.7.1 直接读 <embed src>/<object data> 的原始字符串当 loader URL。
          // narutoweb.js 写的是相对路径，Ruffle 解析查询参数会报「relative URL without a base」，
          // 导致 loaderInfo.parameters（zone_id / ip / port）和 SharedObject 全部失效。
          // 这里在 polyfill 接管前把 SWF 地址改成绝对 URL。
          function absoluteMovie(raw) {
            try {
              if (!raw) return null;
              var abs = new URL(String(raw), document.baseURI || location.href);
              if (abs.protocol !== "http:" && abs.protocol !== "https:") return null;
              var host = abs.hostname.toLowerCase();
              if (host === location.hostname.toLowerCase() || host === "game.huoying.qq.com" || host === "huoying.qq.com") {
                abs = new URL("https://res.huoying.qq.com" + abs.pathname + abs.search);
              }
              return abs.href;
            } catch (e) { return null; }
          }
          // ruffle.js 源码里已经把 checkOptions/kn 的 url 改成调用这个函数，
          // 保证进入 wasm 的 movie_url 一定是绝对地址（query 参数才能被解析出来）。
          window.__airAbsUrl = function (raw) {
            var fixed = absoluteMovie(raw);
            return fixed || raw;
          };

          // === 真正的根因修复 ===
          // main.html 的 web.getEntrySwfUrl() 返回相对地址
          // "NarutoBeta6.38Build302/entry.swf?zone_id=...&ip=...&host=...&port=..."，
          // 靠页面 <base href="https://res.huoying.qq.com/"> 解析。Ruffle 0.7.1 不认 <base>，
          // 直接把相对字符串当 loader URL，tag_utils.rs 报 relative URL without a base，
          // loaderInfo.parameters 为空 → 游戏拿到 ip=null → HTTPDNS 请求 dn=null → 卡死。
          // 这里在页面层把地址绝对化，并把参数再通过 flashvars 送一份，双保险。
          function airAbsEntry(raw) {
            var text = String(raw || "");
            if (/^https?:\/\//i.test(text)) return text;
            var host = (window.web && window.web.host) || "https://res.huoying.qq.com";
            return String(host).replace(/\/+$/, "") + "/" + text.replace(/^\/+/, "");
          }
          var airWebPatched = false;
          function airPatchNarutoWeb() {
            var w = window.web;
            if (!w || airWebPatched || typeof w.getEntrySwfUrl !== "function") return;
            airWebPatched = true;
            // APK 2.4 同款：在 web 实例创建的瞬间就把网关参数固定住，
            // 不让 fcgi 的成败决定 ip / host / port 是否为空。
            var APK = window.__airApk;
            try {
              var z = parseInt(w.getzoneid ? w.getzoneid() : w.zone_id, 10);
              if (!z || z < 1) z = 1101;
              w.zone_id = z;
              w.ip = APK.ip;
              w.host = APK.host;
              w.port = APK.portFor(z);
              w.versionFileName = APK.versionFile;
              console.log("[air-ruffle] APK 启动参数 ip=" + w.ip + " port=" + w.port + " host=" + w.host + " zone=" + w.zone_id);
            } catch (e) { console.log("[air-ruffle] APK 参数注入异常 " + e); }
            var origUrl = w.getEntrySwfUrl;
            w.getEntrySwfUrl = function () {
              var raw = origUrl.apply(this, arguments);
              var fixed = airAbsEntry(raw);
              console.log("[air-ruffle] entry 绝对化 " + fixed.slice(0, 230));
              if (String(fixed).indexOf("ip=null") >= 0 || String(fixed).indexOf("port=null") >= 0) {
                console.log("[air-ruffle] 警告 区服信息为空，检查 query_svr_info.fcgi");
              }
              return fixed;
            };
            // narutoweb.js 的 getServerInfo 只有 success、没有 error：fcgi 一旦失败，
            // ip/port/host/versionFileName 全是 null，整个启动链就断了。
            // 原生通道 + 原始 AJAX 双路并行，谁先成功谁触发（finish 保证只触发一次）。
            var origServerInfo = w.getServerInfo;
            w.getServerInfo = function (callback) {
              var done = false, accurate = false;
              var obj = this;
              var APK = window.__airApk;
              // 无论 fcgi / ajax 结果如何，启动参数都保证有值（APK 兜底）。
              var finish = function (from) {
                if (done) return;
                done = true;
                if (!obj.ip || obj.ip === "null" || obj.ip === "undefined") obj.ip = APK.ip;
                if (!obj.port || obj.port === "null" || obj.port === "undefined") obj.port = APK.portFor(obj.zone_id);
                if (!obj.host || obj.host === "null" || obj.host === "undefined") obj.host = APK.host;
                if (!obj.versionFileName || obj.versionFileName === "null") obj.versionFileName = APK.versionFile;
                console.log("[air-ruffle] 区服信息(" + from + ") " + obj.ip + ":" + obj.port
                  + " host=" + obj.host + " ver=" + obj.versionFileName + " zone=" + obj.zone_id);
                try { callback(); } catch (e) { console.log("[air-ruffle] 启动回调异常 " + e); }
              };
              try { obj.zone_id = obj.getzoneid(); } catch (e) {}
              var fcgi = "";
              try { fcgi = obj.getBaseLocation() + "/fcgi-bin/query_svr_info.fcgi?svr_id=" + obj.zone_id; } catch (e) {}
              if (fcgi) {
                nativeFetch(fcgi).then(function (resp) { return resp.text(); }).then(function (text) {
                  var arr = JSON.parse(text);
                  if (arr && arr.length >= 4 && arr[0] && arr[0] !== "null") {
                    obj.$parseResult(arr);
                    accurate = true;
                    finish("fcgi");
                  } else { console.log("[air-ruffle] fcgi 返回异常 " + String(text).slice(0, 120)); }
                }).catch(function (err) { console.log("[air-ruffle] fcgi 失败 " + err); });
              }
              try {
                origServerInfo.call(obj, function () { if (!accurate) finish("ajax"); });
              } catch (e) {}
              // 关键：绝不无限等待。2.5 秒后无论网络如何都用 APK 参数启动。
              setTimeout(function () { if (!done) { console.log("[air-ruffle] fcgi 超时，采用 APK 兜底参数"); finish("apk"); } }, 2500);
            };
            var origCreate = w.createEntrySwfObject;
            if (typeof origCreate === "function") {
              w.createEntrySwfObject = function (attributes, param, id, a) {
                try {
                  if (attributes && attributes.data && param && !param.flashvars) {
                    var mark = String(attributes.data).indexOf("?");
                    if (mark >= 0) param.flashvars = String(attributes.data).slice(mark + 1);
                  }
                } catch (e) {}
                return origCreate.apply(this, arguments);
              };
            }
            console.log("[air-ruffle] naruto.Web 已接管 " + String(location.href).slice(0, 160));
          }
          // narutoweb.js 末尾是全局 `var web = new naruto.Web()`。用访问器在赋值瞬间
          // 完成接管，比定时器轮询更早、更确定（不会错过 main.html 的 onLoad）。
          try {
            var _airWebValue;
            Object.defineProperty(window, "web", {
              configurable: true,
              get: function () { return _airWebValue; },
              set: function (v) {
                _airWebValue = v;
                try { airPatchNarutoWeb(); } catch (e) { console.log("[air-ruffle] web 接管异常 " + e); }
              }
            });
            console.log("[air-ruffle] window.web 访问器已安装");
          } catch (e) { console.log("[air-ruffle] window.web 访问器失败 " + e); }
          setInterval(airPatchNarutoWeb, 100);
          var movieFixes = 0;
          function fixMovieAttr(node) {
            if (!node || node.nodeType !== 1) return;
            var tag = node.tagName ? node.tagName.toLowerCase() : "";
            var attr = "";
            if (tag === "embed") attr = "src";
            else if (tag === "object") attr = "data";
            else if (tag === "param") {
              var pname = String(node.getAttribute("name") || "").toLowerCase();
              if (pname === "movie" || pname === "src") attr = "value";
            }
            if (!attr) return;
            var value = node.getAttribute(attr);
            if (!value || value.indexOf(".swf") < 0) return;
            var abs = absoluteMovie(value);
            if (!abs || abs === value) return;
            node.setAttribute(attr, abs);
            movieFixes++;
            if (movieFixes <= 4) console.log("[air-ruffle] 影片地址绝对化 " + abs);
          }
          function fixMovieTree(root) {
            if (!root) return;
            if (root.nodeType === 1) fixMovieAttr(root);
            if (!root.querySelectorAll) return;
            var nodes = root.querySelectorAll("embed,object,param");
            for (var i = 0; i < nodes.length; i++) fixMovieAttr(nodes[i]);
          }
          var movieObserver = new MutationObserver(function (muts) {
            for (var i = 0; i < muts.length; i++) {
              var m = muts[i];
              if (m.type === "attributes") fixMovieAttr(m.target);
              else for (var j = 0; j < m.addedNodes.length; j++) fixMovieTree(m.addedNodes[j]);
            }
          });
          function startMovieObserver() {
            var root = document.documentElement || document;
            movieObserver.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ["src", "data", "value"] });
            fixMovieTree(root);
          }
          if (document.documentElement) startMovieObserver();
          else document.addEventListener("DOMContentLoaded", startMovieObserver);
          setInterval(function () { fixMovieTree(document.documentElement); }, 400);

          // 真正的入口在这里：火影的启动器把 entry.swf 交给 Ruffle 的 JS API（player.load），
          // 不经过 <embed>。Ruffle 会把传进来的字符串原样当 loader URL，
          // 相对路径就解析不出 zone_id / ip / port，SharedObject 也会报错。
          // 钩住 customElements.define，在播放器组件注册前替换 prototype.load。
          window.__airAbsolutizeMovie = absoluteMovie;
          var domFixes = 0;
          function absolutizeLoadOptions(options) {
            if (!options) return options;
            try {
              if (typeof options === "string") {
                var single = absoluteMovie(options);
                if (single && single !== options) {
                  domFixes++;
                  if (domFixes <= 4) console.log("[air-ruffle] 影片地址绝对化 " + single);
                  return single;
                }
                return options;
              }
              if (typeof options === "object" && typeof options.url === "string") {
                var abs = absoluteMovie(options.url);
                if (abs && abs !== options.url) {
                  domFixes++;
                  if (domFixes <= 4) console.log("[air-ruffle] 影片地址绝对化 " + abs);
                  options.url = abs;
                }
              }
            } catch (e) {}
            return options;
          }
          if (window.customElements && customElements.define) {
            var origDefine = customElements.define.bind(customElements);
            customElements.define = function (name, ctor, options) {
              try {
                if (ctor && ctor.prototype && typeof ctor.prototype.load === "function") {
                  var origLoad = ctor.prototype.load;
                  ctor.prototype.load = function (loadOptions) {
                    return origLoad.call(this, absolutizeLoadOptions(loadOptions));
                  };
                }
              } catch (e) {}
              return origDefine(name, ctor, options);
            };
          }
          function wrapApiPlayer(player) {
            if (!player || player.__airWrapped) return player;
            player.__airWrapped = true;
            var origCreate = player.createPlayer;
            if (typeof origCreate === "function") {
              player.createPlayer = function () {
                var el = origCreate.apply(this, arguments);
                if (el && typeof el.load === "function" && !el.__airLoadWrapped) {
                  var innerLoad = el.load;
                  el.__airLoadWrapped = true;
                  el.load = function (loadOptions) {
                    return innerLoad.call(this, absolutizeLoadOptions(loadOptions));
                  };
                }
                return el;
              };
            }
            return player;
          }
          function patchRuffleApi() {
            var api = window.RufflePlayer;
            if (!api || api.__airApiPatched || typeof api.newest !== "function") return;
            api.__airApiPatched = true;
            var origNewest = api.newest.bind(api);
            api.newest = function () {
              return wrapApiPlayer(origNewest.apply(null, arguments));
            };
            console.log("[air-ruffle] RufflePlayer API 已接管");
          }
          setInterval(patchRuffleApi, 150);
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
            // APK 2.4 的 OfficialResources 会拦截 HTTPDNS /d?dn=…；这里同款修正，
            // 并把 dn=null 改成网关域名后直接走原生通道，避免 CORS / 证书失败。
            var dns = httpDnsUrl(raw);
            if (dns) {
              console.log("[air-ruffle] HTTPDNS 原生 " + dns.slice(0, 160));
              return nativeFetch(dns);
            }
            var asset = nativeAssetUrl(raw);
            if (!asset) {
              // 非资源请求（HTTPDNS /d?dn=…、登录校验等）先走浏览器 fetch，
              // 被 CORS 或网络策略挡掉时回退到原生通道，避免 Ruffle 侧拿到
              // 「FetchError: Got JS error」直接判定加载失败。
              var direct = origFetch(input, init);
              if (init && init.body) return direct;
              return direct.catch(function (error) {
                var loose = looseNativeUrl(raw);
                if (!loose) throw error;
                console.log("[air-ruffle] fetch 回退原生 " + String(raw).slice(0, 160));
                return nativeFetch(loose);
              });
            }
            if (String(raw) !== asset) console.log("[air-ruffle] req " + String(raw).slice(0, 180) + " -> " + asset);
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
            // 末尾追加补丁：bundle 执行完的瞬间组件已经注册好，此时接管 load() 一定命中，
            // 不存在「比 Ruffle 更早/更晚」的时序竞争。
            contentController.addUserScript(WKUserScript(source: source + Self.ruffleEntryPatch, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
    }

    /// 追加在 ruffle.js 末尾的补丁。
    /// Ruffle 会把 load() 收到的字符串原样当作 loader URL，相对路径就解析不出
    /// zone_id / ip / port（报 relative URL without a base），SharedObject 也跟着失效。
    /// 这里在组件注册完成后立刻接管 load()，把影片地址绝对化并补上参数。
    private static let ruffleEntryPatch = #"""

    ;(function () {
      function airLog(msg) {
        try { console.log("[air-ruffle] " + msg); } catch (e) {}
      }
      function airShort(value) {
        try {
          var text = typeof value === "string" ? value : (value && value.url ? String(value.url) : String(value));
          return text.slice(0, 150);
        } catch (e) { return "?"; }
      }
      function airAbs(raw) {
        try {
          if (typeof raw !== "string" || !raw) return raw;
          var abs = new URL(raw, document.baseURI || location.href);
          if (abs.protocol !== "http:" && abs.protocol !== "https:") return raw;
          var host = abs.hostname.toLowerCase();
          if (host === String(location.hostname).toLowerCase() || host === "game.huoying.qq.com" || host === "huoying.qq.com") {
            abs = new URL("https://res.huoying.qq.com" + abs.pathname + abs.search);
          }
          return abs.href;
        } catch (e) { return raw; }
      }
      function airQuery(raw) {
        try {
          var text = String(raw || "");
          var mark = text.indexOf("?");
          if (mark < 0) return null;
          var query = text.slice(mark + 1).split("#")[0];
          if (!query) return null;
          var out = {};
          var pairs = query.split("&");
          for (var i = 0; i < pairs.length; i++) {
            var pair = pairs[i];
            if (!pair) continue;
            var eq = pair.indexOf("=");
            var name = decodeURIComponent(eq < 0 ? pair : pair.slice(0, eq));
            if (!name) continue;
            out[name] = decodeURIComponent((eq < 0 ? "" : pair.slice(eq + 1)).replace(/\+/g, " "));
          }
          return out;
        } catch (e) { return null; }
      }
      var fixes = 0;
      var loads = 0;
      function airFixOptions(options) {
        if (typeof options === "string") {
          var single = airAbs(options);
          if (single !== options) {
            fixes++;
            if (fixes <= 6) airLog("影片地址绝对化 " + single.slice(0, 150));
          }
          return single;
        }
        if (options && typeof options === "object" && typeof options.url === "string") {
          var before = options.url;
          var after = airAbs(before);
          if (after !== before) {
            options.url = after;
            fixes++;
            if (fixes <= 6) airLog("影片地址绝对化 " + after.slice(0, 150));
          }
          try {
            if (!options.base) {
              var baseUrl = new URL(options.url, document.baseURI || location.href);
              options.base = baseUrl.origin + baseUrl.pathname.replace(/[^/]*$/, "");
              airLog("已设 base " + options.base.slice(0, 120));
            }
          } catch (e) {}
          try {
            var hasParams = false;
            if (options.parameters) {
              for (var key in options.parameters) { hasParams = true; break; }
            }
            if (!hasParams) {
              var params = airQuery(options.url);
              if (params) {
                var names = [];
                for (var paramKey in params) names.push(paramKey);
                if (names.length) {
                  options.parameters = params;
                  airLog("已补参数 " + names.join(","));
                }
              }
            }
          } catch (e) {}
        }
        return options;
      }
      function airPatchLoad(ctor, name) {
        try {
          if (!ctor || !ctor.prototype) return false;
          var original = ctor.prototype.load;
          if (typeof original !== "function") return false;
          if (original.__airFixed) return true;
          var wrapped = function (options) {
            var args = Array.prototype.slice.call(arguments);
            loads++;
            if (loads <= 3) airLog("load #" + loads + " " + (typeof options) + " " + airShort(options));
            args[0] = airFixOptions(args[0]);
            return original.apply(this, args);
          };
          wrapped.__airFixed = true;
          ctor.prototype.load = wrapped;
          airLog("已接管 " + name + ".load");
          return true;
        } catch (e) {
          airLog("接管失败 " + name + " " + e);
          return false;
        }
      }
      var names = ["ruffle-player", "ruffle-embed", "ruffle-object"];
      for (var i = 0; i < names.length; i++) {
        var ctor = window.customElements ? window.customElements.get(names[i]) : null;
        airLog("组件 " + names[i] + (ctor ? " 已定义" : " 未定义"));
        if (ctor) airPatchLoad(ctor, names[i]);
      }
      if (window.customElements && window.customElements.whenDefined) {
        names.forEach(function (name) {
          try {
            window.customElements.whenDefined(name).then(function () {
              airPatchLoad(window.customElements.get(name), name);
            }, function () {});
          } catch (e) {}
        });
      }
      // 兜底：组件名可能被加了后缀（ruffle-embed-1），把已注册的全部扫一遍
      function airSweep() {
        if (!window.customElements || !window.customElements.get) return;
        var extra = ["ruffle-embed-1", "ruffle-object-1", "ruffle-player-1", "ruffle-embed-2", "ruffle-object-2"];
        for (var k = 0; k < extra.length; k++) {
          var extraCtor = window.customElements.get(extra[k]);
          if (extraCtor) airPatchLoad(extraCtor, extra[k]);
        }
      }
      setInterval(airSweep, 500);
      // 再兜底：polyfill 用 setAttribute / attributes.setNamedItem 写 src 时直接改写
      function airFixAttr(element, attrName, value) {
        try {
          var name = String(attrName || "").toLowerCase();
          if (name !== "src" && name !== "data" && name !== "value") return value;
          if (typeof value !== "string" || value.indexOf(".swf") < 0) return value;
          var fixed = airAbs(value);
          if (fixed !== value) {
            fixes++;
            if (fixes <= 6) airLog("属性绝对化 " + fixed.slice(0, 150));
          }
          return fixed;
        } catch (e) { return value; }
      }
      try {
        var origSetAttribute = Element.prototype.setAttribute;
        Element.prototype.setAttribute = function (name, value) {
          var fixed = airFixAttr(this, name, value);
          return origSetAttribute.call(this, name, fixed);
        };
      } catch (e) {}
      try {
        if (window.NamedNodeMap && NamedNodeMap.prototype.setNamedItem) {
          var origSetNamedItem = NamedNodeMap.prototype.setNamedItem;
          NamedNodeMap.prototype.setNamedItem = function (attr) {
            try {
              if (attr && attr.ownerElement && attr.name) {
                var fixed = airFixAttr(attr.ownerElement, attr.name, attr.value);
                if (typeof fixed === "string") attr.value = fixed;
              }
            } catch (e) {}
            return origSetNamedItem.call(this, attr);
          };
        }
      } catch (e) {}
      // 诊断：把播放器实际拿到的地址打出来，便于下一轮定位
      setTimeout(function () {
        try {
          var nodes = document.querySelectorAll("ruffle-player, ruffle-embed, ruffle-object, embed, object");
          airLog("播放器节点 " + nodes.length);
          for (var n = 0; n < nodes.length && n < 4; n++) {
            var element = nodes[n];
            var config = element.loadedConfig || {};
            var raw = config.url || "";
            if (!raw && element.getAttribute) raw = element.getAttribute("src") || element.getAttribute("data") || "";
            airLog("节点 " + element.tagName + " url=" + String(raw).slice(0, 130));
          }
        } catch (e) {}
      }, 3000);
      window.__airFixMovieOptions = airFixOptions;
    })();
    """#

    /// 屏幕日志诊断层。捕获 console / window 错误 / Promise 拒绝 / ruffle-player 事件，
    /// 加 10 秒心跳（资源数、待定请求、socket 数、播放器尺寸）。轻点左下角状态条展开全部日志。
    private func injectDiagnosticsScript(into contentController: WKUserContentController) {
        let source = #"""
        (() => {
          if (window.top !== window) return;
          var logs = [];
          var overlay = null;
          var lastBadge = "";
          function stamp() {
            var d = new Date();
            return ("0"+d.getHours()).slice(-2)+":"+("0"+d.getMinutes()).slice(-2)+":"+("0"+d.getSeconds()).slice(-2);
          }
          function push(level, text) {
            try {
              text = String(text).replace(/\s+/g, " ").slice(0, 400);
              logs.push(stamp() + " [" + level + "] " + text);
              if (logs.length > 150) logs.shift();
              if (level === "E") {
                var b = document.getElementById("air-ruffle-status");
                if (b) {
                  b.style.background = "rgba(160,40,40,.95)";
                  b.textContent = "⚠ " + text.slice(0, 90);
                  lastBadge = b.textContent;
                }
              }
            } catch (e) {}
          }
          function renderOverlay() {
            if (!overlay) return;
            overlay.textContent = "≡ 火影OL 诊断日志（共 " + logs.length + " 条，轻点任意处关闭）\n\n" + logs.join("\n");
            overlay.scrollTop = overlay.scrollHeight;
          }
          function toggleOverlay() {
            if (overlay) {
              overlay.remove();
              overlay = null;
              return;
            }
            overlay = document.createElement("div");
            overlay.style.cssText = "position:fixed;inset:0;z-index:2147483647;background:rgba(0,0,0,.96);color:#7CFC98;font:10px/1.35 Menlo,monospace;padding:14px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;pointer-events:auto;";
            overlay.textContent = "";
            (document.body || document.documentElement).appendChild(overlay);
            renderOverlay();
            overlay.addEventListener("click", function () { overlay.remove(); overlay = null; });
          }
          function wireBadge() {
            var b = document.getElementById("air-ruffle-status");
            if (!b || b.__airDiag) return;
            b.__airDiag = true;
            b.style.pointerEvents = "auto";
            b.style.cursor = "pointer";
            b.addEventListener("click", function (e) { e.stopPropagation(); toggleOverlay(); });
            if (lastBadge) b.textContent = lastBadge;
          }
          setInterval(wireBadge, 500);

          var origLog = console.log.bind(console);
          var origWarn = console.warn.bind(console);
          var origError = console.error.bind(console);
          console.log = function () { var t = [].slice.call(arguments).join(" "); push("L", t); origLog.apply(null, arguments); };
          console.warn = function () { var t = [].slice.call(arguments).join(" "); push("W", t); origWarn.apply(null, arguments); };
          console.error = function () { var t = [].slice.call(arguments).join(" "); push("E", t); origError.apply(null, arguments); };

          window.addEventListener("error", function (e) {
            var where = e.filename ? (" @ " + String(e.filename).split("/").pop() + ":" + e.lineno) : "";
            push("E", "window.onerror " + e.message + where);
          });
          window.addEventListener("unhandledrejection", function (e) {
            var reason = e.reason && e.reason.message ? e.reason.message : String(e.reason);
            push("E", "unhandled rejection " + reason);
          });

          function watchPlayer(node) {
            if (node.__airWatched) return;
            node.__airWatched = true;
            push("L", "ruffle-player 已创建");
            node.addEventListener("loaded", function () { push("L", "ruffle-player loaded 事件触发"); });
            node.addEventListener("error", function (e) { push("E", "ruffle-player error " + ((e.detail && e.detail.message) || "")); });
          }
          var mo = new MutationObserver(function (muts) {
            var players = document.querySelectorAll("ruffle-player, ruffle-embed, ruffle-object");
            for (var i = 0; i < players.length; i++) watchPlayer(players[i]);
          });
          if (document.documentElement) mo.observe(document.documentElement, { childList: true, subtree: true });
          document.addEventListener("DOMContentLoaded", function () {
            var players = document.querySelectorAll("ruffle-player, ruffle-embed, ruffle-object");
            for (var i = 0; i < players.length; i++) watchPlayer(players[i]);
          });

          setInterval(function () {
            try {
              var pending = 0, ids = window.__airNativeSlots || {};
              for (var k in ids) pending++;
              var socks = 0, map = window.__airSocketMap || {};
              for (var k2 in map) socks++;
              var player = document.querySelector("ruffle-player, ruffle-embed, ruffle-object");
              var size = "无播放器";
              if (player) {
                var r = player.getBoundingClientRect();
                size = Math.round(r.width) + "x" + Math.round(r.height);
              }
              push("W", "心跳 资源=" + (window.__airAssetCount || 0) + " 待定fetch=" + pending + " socket=" + socks + " 播放器=" + size + " 就绪wasm=" + Object.keys(window.__airWasmReady || {}).length);
            } catch (e) {}
          }, 10000);
          push("L", "诊断层已启动 v2.0 (APK 2.4 同源)");
        })();
        """#
        contentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
