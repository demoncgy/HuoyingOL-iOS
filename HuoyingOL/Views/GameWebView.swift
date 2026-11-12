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
        
        // 允许内联媒体播放。wasm 由 AirBundleBridge 按需回传，SWF/资源走 AirNativeFetchBridge，
        // webpack 分块由 WKUserScript 预注入，全程不依赖 ruffle:// 自定义 scheme。
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(RuffleSchemeHandler(), forURLScheme: RuffleSchemeHandler.scheme)
        let assetBridge = AirNativeFetchBridge()
        context.coordinator.assetBridge = assetBridge
        configuration.userContentController.add(assetBridge, name: AirNativeFetchBridge.handlerName)
        let socketBridge = AirSocketBridge()
        context.coordinator.socketBridge = socketBridge
        configuration.userContentController.add(socketBridge, name: AirSocketBridge.handlerName)
        let bundleBridge = AirBundleBridge()
        context.coordinator.bundleBridge = bundleBridge
        configuration.userContentController.add(bundleBridge, name: AirBundleBridge.handlerName)
        
        // 顺序不可调整：APK 移植层 + iOS 启动层 -> Ruffle 运行时。
        // 运行时把两个 core.ruffle.*.js 与 ruffle.js 拼成一个 WKUserScript：
        // 分块先 push 到 self.webpackChunkruffle_selfhosted，webpack 运行时随后
        // 消费这批已排队的分块，a.e(110/993) 立即完成，不会再去页面域名请求 .js。
        injectBootScript(into: configuration.userContentController)
        injectRuffleRuntime(into: configuration.userContentController)
        // 注入 qq-return.js 脚本（所有子 frame 中执行，处理跨 iframe 登录通信）
        injectQQReturnScript(into: configuration.userContentController)
        // 主框架铺满屏幕：viewport-fit=cover，并按视口缩放选区页 / 游戏舞台
        injectFullscreenScript(into: configuration.userContentController)
        
        // 创建独立的或者持久化的 WKWebView
        let webView = WKWebView(frame: .zero, configuration: configuration)
        assetBridge.webView = webView
        socketBridge.webView = webView
        bundleBridge.webView = webView
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

    /// Ruffle 运行时 = 两个 webpack 分块 + ruffle.js，整体作为一个 WKUserScript 注入。
    /// ruffle.js 自身没有 <script src>，publicPath 为空时 a.e(110/993) 会拼出
    /// "core.ruffle.*.js" 去游戏域名请求，必然 404（这正是 wasm 加载失败的前置错误）。
    /// 分块脚本只做一件事：push 到 self.webpackChunkruffle_selfhosted 数组；
    /// webpack 运行时启动时会先 forEach 消费已排队的分块，之后 a.e() 直接 resolve。
    private func injectRuffleRuntime(into contentController: WKUserContentController) {
        let names = [
            "core.ruffle.16d61072ac7fdc4d5013.js",
            "core.ruffle.994eeef0a471a88cd0e3.js",
            "ruffle.js"
        ]
        var parts: [String] = []
        for name in names {
            guard let file = Self.ruffleResource(name),
                  let source = try? String(contentsOf: file, encoding: .utf8),
                  !source.isEmpty else {
                parts.append("console.error('[air-boot] missing \(name)');")
                continue
            }
            parts.append(source)
        }
        contentController.addUserScript(WKUserScript(
            source: parts.joined(separator: "\n;\n"),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// 把「APK 移植层 + iOS 启动层」拼成单个 WKUserScript，顺序固定、无注入竞态。
    /// air-apk-bridge.js 由 build-apk-bridge.py 从 MobileGame.swf / application.xml
    /// 自动生成；air-boot.js 读取 window.__airApk 驱动会话与网络。
    private func injectBootScript(into contentController: WKUserContentController) {
        let names = ["air-apk-bridge.js", "air-boot.js"]
        var parts: [String] = []
        for name in names {
            guard let file = Self.ruffleResource(name),
                  let source = try? String(contentsOf: file, encoding: .utf8),
                  !source.isEmpty else {
                contentController.addUserScript(WKUserScript(
                    source: "console.error('[air-boot] missing \(name)');",
                    injectionTime: .atDocumentStart, forMainFrameOnly: true))
                return
            }
            parts.append(source)
        }
        contentController.addUserScript(WKUserScript(
            source: parts.joined(separator: "\n;\n"),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
        var bundleBridge: AirBundleBridge?
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
