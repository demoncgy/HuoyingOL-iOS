/*
 * air-apk-bridge.js -- 由 analysis/build-apk-bridge.py 从 OL-AIR-2.4.apk 自动生成
 *
 * 来源：
 *   assets/MobileGame.swf             AS3 DoABC 常量池（airgame.bridge 全部模块）
 *   assets/META-INF/AIR/application.xml  AIR 51.1 应用描述符
 *   apk-manifest.json                  随 IPA 内置的 APK 原始资产清单
 *
 * APK 的 MobileGame.swf 依赖 flash.filesystem.File / NativeApplication / ABC 注入，
 * iOS 无 AIR 运行时，无法执行。这里把它的每个模块转写成等价 JS 语义：
 *   OfficialResources / KeyFileLoader / RuntimeAdapter / URLLoader / Security /
 *   LoaderContext / ExternalInterface / GameBridge / SpeedClock / Socket /
 *   FrameRateControl / Timer / EntryCompatibility / PreciseNetworkPatch / SHA256
 * 由 air-boot.js 读取 __airApk.runtime 驱动启动，Ruffle 负责 SWF 渲染。
 */
(() => {
  "use strict";

  const CONST = {
  "source": "OL-AIR-2.4.apk",
  "descriptor": {
    "id": "local.huoying.airgame",
    "version": "2.4",
    "filename": "HuoyingOL",
    "name": "火影OL",
    "namespace": "http://ns.adobe.com/air/application/51.1",
    "initialContent": "MobileGame.swf",
    "width": 1600,
    "height": 720,
    "aspectRatio": "landscape",
    "autoOrients": "false",
    "fullScreen": "true",
    "renderMode": "cpu",
    "extensions": [
      "local.huoying.qqlogin"
    ]
  },
  "swf": {
    "signature": "FWS",
    "version": 32,
    "bytes": 60082,
    "abcTagCount": 17,
    "tagCount": 21,
    "moduleCount": 16,
    "sha256": "976ebd90fd962920a062c7ed2e42ea4017b257636cbd80aac0ea0576924a7b1b"
  },
  "modules": [
    "SHA256",
    "FrameRateControl",
    "PreciseNetworkPatch",
    "EntryCompatibility",
    "OfficialResources",
    "RuntimeAdapter",
    "ExternalInterface",
    "LoaderContext",
    "Security",
    "URLLoader",
    "Loader",
    "SpeedClock",
    "Timer",
    "TimerProvider",
    "Socket",
    "GameBridge"
  ],
  "gateway": "zone.huoying.qq.com",
  "cdn": "https://res.huoying.qq.com/",
  "httpDns": "http://182.254.116.117/d",
  "httpDnsPattern": "GET0^http://182.254.116.117/d\\?dn=[a-z0-9.-]+$",
  "officialEntryPattern": "compressR^https://res.huoying.qq.com/NarutoBeta[0-9.]+Build[0-9]+/entry.swf(?:\\?|$)",
  "versionDirPattern": "compressR^https://res.huoying.qq.com/NarutoBeta[0-9.]+Build[0-9]+/entry.swf(?:\\?|$)",
  "resourceCfg": "app:/resource.cfg",
  "qqReturn": "app:/qq-return.js",
  "qqAppFrame": "https://minigame.qq.com/plat/social_hall/app_frame/index_v4.html?appid=1103286479",
  "qqWebsite": "https://huoying.qq.com/server/website/1",
  "gameOrigin": "https://game.huoying.qq.com/",
  "emptySwf": "https://res.huoying.qq.com/empty.swf",
  "wtloginScheme": "wtloginmqq:",
  "allowCodeImport": true,
  "securitySandbox": "localWithFile",
  "dnsLookup": true,
  "sensitiveFields": [
    "access_token",
    "openid",
    "skey",
    "password",
    "cookie"
  ],
  "rawPatterns": [
    "^ airgame.bridge:OfficialResources",
    "^\"&h\"]#,1]$f$",
    "^\"&h\"]#,4]$f$",
    "^(app:/|/)!^http://res.huoying.qq.com/R^https://res.huoying.qq.com/NarutoBeta[0-9.]+Build[0-9]+/[A-Za-z0-9_./-]+$",
    "^(low|medium|high|best)$",
    "^-]4f4]-f-]3f3",
    "^\\d+$",
    "^\\d{1,6}$",
    "^\\d{5,20}$",
    "compressR^https://res.huoying.qq.com/NarutoBeta[0-9.]+Build[0-9]+/entry.swf(?:\\?|$)",
    "if((probe||micro)&&(!/^https?:$/.test(url.protocol)||url.hostname!=='res.huoying.qq.com'||url.port||url.username||url.password||url.hash||!/^/NarutoBeta[0-9.]+Build[0-9]+/entry.swf$/.test(url.pathname)))return;Xvar cookies=Object.create(null),parameters=Object.create(null),page=Object.create(null);Xdocument.cookie.split(';').forEach(function(part){var i=part.indexOf('=');if(i<0)return;svar key=part.slice(0,i).trim();if(key)cookies[key]=typeof getCookie==='function'?getCookie(key):part.slice(i+1);});1if(!cookies.access_token||!cookies.openid)return;Furl.searchParams.forEach(function(value,key){parameters[key]=value;});Wif(vars)new URLSearchParams(vars).forEach(function(value,key){parameters[key]=value;});Snew URL(location.href).searchParams.forEach(function(value,key){page[key]=value;});bvar account=micro&&/^\\d{5,20}$/.test(cookies.fake_id)?cookies.fake_id:String(web.getUin()).trim();",
    "resource.cfg/^(?:app:/|/?)(NarutoBeta[0-9.]+Build[0-9]+/)",
    "split=^https://res.huoying.qq.com/NarutoBeta[0-9.]+Build\\d+/"
  ],
  "appPaths": [
    "app:/qq-return.js",
    "app:/resource.cfg"
  ],
  "classNames": [
    "com.tencent.morefun.framework.loader.mission:Mission",
    "com.tencent.morefun.naruto.file.FileAssetInfo",
    "com.tencent.morefun.naruto.file::FileAssetInfo",
    "com.tencent.morefun.naruto.plugin.server.socket:SocketServer",
    "com.tencent.morefun.naruto.plugin.ui.util",
    "com.tencent.morefun.naruto.plugin.ui.util.TimerProvider",
    "com.tencent.morefun.naruto.plugin.user.executer:SystemExecuter9com.tencent.morefun.naruto.plugin.hud.exec:MainUIExecuter7com.tencent.morefun.naruto.plugin.ui.util:TimerProvider"
  ],
  "assets": [
    {
      "path": "AndroidX-LICENSE.txt",
      "bytes": 10175,
      "sha256": "809fa1ed21450f59827d1e9aec720bbc4b687434fa22283c6cb5dd82a47ab9c0"
    },
    {
      "path": "AndroidX-NOTICE.txt",
      "bytes": 169,
      "sha256": "c8a742338a73e8896aa2ceadabf8028493165502ce597abead2129a34f6736d2"
    },
    {
      "path": "MobileGame.swf",
      "bytes": 60082,
      "sha256": "976ebd90fd962920a062c7ed2e42ea4017b257636cbd80aac0ea0576924a7b1b"
    },
    {
      "path": "appIcon192.png",
      "bytes": 62201,
      "sha256": "376c174cd68023ba3126a1d5f88c71b070b8a11b454c591e050fc6bf18b715a1"
    },
    {
      "path": "application.xml",
      "bytes": 17304,
      "sha256": "238c0a107f845c72ddc6f2dffab18c6e91c881a7abfb32c2b42e3cf733f39d3f"
    },
    {
      "path": "license.txt",
      "bytes": 80,
      "sha256": "045c188e90ebfb4de6340b61e799375ad05b99fe12ee49e45bbcedb7be7d2364"
    },
    {
      "path": "qq-return.js",
      "bytes": 6127,
      "sha256": "1adffd77fe685d0fbd193f744dc0170b6398ff0292c0acd5ab828699e2fcd40e"
    },
    {
      "path": "splash_landscape.png",
      "bytes": 59061,
      "sha256": "6d67fe7db0238e669157a1a91103b50ebf81289033242ce3caefbf7d3636259a"
    },
    {
      "path": "splash_portrait.png",
      "bytes": 86038,
      "sha256": "83fa945421e5e576cb6c8b5e5b4b5c6d5c1180166da1ed7d4fa0d99bdbf6bdb9"
    },
    {
      "path": "extensions/local.huoying.qqlogin/catalog.xml",
      "bytes": 316,
      "sha256": "de7acef196a4530f3f70334324cfd97ee2ac1062bfe202d6c01ac82aa705b2f5"
    },
    {
      "path": "extensions/local.huoying.qqlogin/library.swf",
      "bytes": 428,
      "sha256": "4ea9e4480cd824b3779b42cbe4b3eb2c733987ac3f7d2980e2c2cc04f654e446"
    },
    {
      "path": "extensions/local.huoying.qqlogin/META-INF/ANE/extension.xml",
      "bytes": 981,
      "sha256": "7ce7e4b9ea0532fb69a22979210f6012f182df207c2aa6fd9f193bf92535fb76"
    },
    {
      "path": "extensions/local.huoying.qqlogin/META-INF/ANE/Android-ARM64/library.swf",
      "bytes": 428,
      "sha256": "4ea9e4480cd824b3779b42cbe4b3eb2c733987ac3f7d2980e2c2cc04f654e446"
    }
  ],
  "runtime": {
    "ip": "zone.huoying.qq.com",
    "host": "https://res.huoying.qq.com",
    "cdn": "https://res.huoying.qq.com/",
    "versionFile": "version.js",
    "defaultZone": 1101,
    "httpDns": "http://182.254.116.117/d",
    "ports": {
      "1": "10001",
      "2": "10001",
      "3": "10001",
      "10": "10001",
      "100": "10073",
      "201": "10157",
      "401": "10383",
      "601": "10581",
      "801": "10800",
      "1001": "10991",
      "1101": "11099",
      "6001": "16001",
      "8001": "18001",
      "8999": "18976"
    },
    "_portsSource": "query_svr_info.fcgi 实测（APK 运行时向该接口查询）"
  }
};

  function str(v) { return String(v == null ? "" : v); }
  function abs(raw, base) {
    try {
      const b = base || (typeof document !== "undefined" && document.baseURI) ||
        (typeof location !== "undefined" && location.href) || CONST.cdn;
      return new URL(str(raw), b);
    } catch (e) { return null; }
  }
  function redact(text) {
    const re = new RegExp("(" + CONST.sensitiveFields.join("|") + ")\\s*[=:]\\s*[^&\\s\"']+", "gi");
    return str(text).replace(re, (m, key) => key + "=***");
  }

  // ------------------------------------------------------------------
  // OfficialResources：app:/ 与官方 HTTP 资源统一重定向到 CDN 版本目录
  // ------------------------------------------------------------------
  const VERSION_DIR = /^(?:app:\/|\/?)(NarutoBeta[0-9.]+Build[0-9]+\/)/;
  const HAS_VERSION = /NarutoBeta[0-9.]+Build[0-9]+\//;
  const OFFICIAL_ENTRY = /^https:\/\/res\.huoying\.qq\.com\/NarutoBeta[0-9.]+Build[0-9]+\/entry\.swf(?:\?|$)/;
  const officialResources = {
    cdn: CONST.cdn,
    versionDirOf(raw) {
      const s = str(raw).replace(/^https?:\/\/res\.huoying\.qq\.com\//i, "");
      const m = VERSION_DIR.exec(s);
      return m ? m[1] : "";
    },
    isOfficialEntry(url) { return OFFICIAL_ENTRY.test(str(url).split("#")[0]); },
    isOfficialAsset(url) {
      const u = abs(url);
      if (!u) return false;
      return u.hostname === "res.huoying.qq.com" &&
        /^https:\/\/res\.huoying\.qq\.com\/NarutoBeta[0-9.]+Build[0-9]+\/[A-Za-z0-9_.\/-]+$/
          .test(u.href.split("?")[0]);
    },
    resolve(raw, versionDir) {
      let s = str(raw).trim();
      if (!s) return null;
      if (/^app:\//i.test(s)) {
        s = s.replace(/^app:\/+/i, "");
        const dir = versionDir || this.versionDirOf(s);
        if (dir && s.indexOf(dir) !== 0 && !HAS_VERSION.test(s)) s = dir + s;
        return CONST.cdn + s.replace(/^\/+/, "");
      }
      if (/^http:\/\/res\.huoying\.qq\.com\//i.test(s)) s = "https://" + s.slice(7);
      if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(s)) return CONST.cdn + s.replace(/^\/+/, "");
      const u = abs(s);
      if (!u) return null;
      if (u.hostname === location.hostname || u.hostname === "game.huoying.qq.com" ||
          u.hostname === "huoying.qq.com") {
        return CONST.cdn + u.pathname.replace(/^\/+/, "") + u.search;
      }
      return u.href;
    },
    normalizeCfg(raw, versionDir) {
      const resolved = this.resolve(raw, versionDir);
      if (!resolved) return null;
      if (/NarutoBeta[0-9.]+Build[0-9]+\//.test(resolved)) return resolved;
      return resolved;
    }
  };

  // ------------------------------------------------------------------
  // KeyFileLoader：resource.cfg / entry.swf / RSL 的版本目录补全
  // ------------------------------------------------------------------
  const keyFileLoader = {
    isKeyFile(url) { return /\/(resource\.cfg|entry\.swf)$/i.test(str(url).split(/[?#]/)[0]); },
    isResourceCfg(url) { return /\/resource\.cfg$/i.test(str(url).split(/[?#]/)[0]); },
    addBuildVersion(raw, versionDir) {
      if (!versionDir) return raw;
      const u = abs(raw);
      if (!u || u.hostname !== "res.huoying.qq.com") return raw;
      if (HAS_VERSION.test(u.pathname)) return u.href;
      const dir = versionDir.replace(/\/$/, "");
      u.pathname = "/" + dir + u.pathname;
      return u.href;
    },
    getConfig(text) {
      // resource.cfg 可能为二进制索引；这里只提取可解析的版本/条目，不做破坏性假设。
      const out = { versionDir: "", lines: 0, entries: [] };
      const s = str(text);
      const m = /NarutoBeta[0-9.]+Build[0-9]+/.exec(s);
      if (m) out.versionDir = m[0];
      out.lines = s ? s.split(/\r?\n/).length : 0;
      return out;
    }
  };

  // ------------------------------------------------------------------
  // RuntimeAdapter：entryURL 协议升级 / empty.swf 兜底 / 资源安全校验
  // ------------------------------------------------------------------
  const runtimeAdapter = {
    rewriteEntryUrl(raw) {
      const s = str(raw);
      if (/^http:\/\/res\.huoying\.qq\.com\//i.test(s)) return s.replace(/^http:/i, "https:");
      return s;
    },
    emptySwfFallback(url) {
      return CONST.emptySwf || "https://res.huoying.qq.com/empty.swf";
    },
    acceptPublicSwf(url) {
      const u = abs(url);
      if (!u) return false;
      return u.hostname === "res.huoying.qq.com" || u.hostname === "game.huoying.qq.com";
    }
  };

  // ------------------------------------------------------------------
  // URLLoader：HTTPDNS /d?dn= 修正（APK 里是 dnsLookup 字节码补丁）
  // ------------------------------------------------------------------
  const urlLoader = {
    dnsLookup(raw) {
      let s = str(raw).trim();
      // AS3 URLRequest 偶尔给出裸 IP / 根相对形式，先补全成绝对地址。
      if (/^\/?182\.254\.116\.117\//i.test(s)) s = "http://" + s.replace(/^\/+/, "");
      else if (/^\/d\?dn=/i.test(s)) s = "http://182.254.116.117" + s;
      const u = abs(s);
      if (!u || u.pathname !== "/d" || !u.searchParams.has("dn")) return null;
      let dn = u.searchParams.get("dn") || "";
      const bad = !dn || /^(null|undefined|0)$/i.test(dn) || !/^[a-z0-9.-]+$/i.test(dn);
      if (bad) dn = CONST.gateway;
      u.protocol = "http:";
      u.searchParams.set("dn", dn);
      return u.href;
    }
  };

  // ------------------------------------------------------------------
  // Security / LoaderContext / ExternalInterface
  // ------------------------------------------------------------------
  const security = {
    sandboxType: CONST.securitySandbox || "localWithFile",
    policyFiles: [],
    loadPolicyFile(url) { this.policyFiles.push(str(url)); return true; }
  };
  const loaderContext = {
    allowCodeImport: CONST.allowCodeImport !== false,
    allowLoadBytesCodeExecution: true,
    checkPolicyFile: false
  };
  const events = [];
  const externalInterface = {
    available: true,
    calls: 0,
    call(name, args) {
      this.calls++;
      gameBridge.report("external", name + " " + redact(args));
      return null;
    }
  };
  const gameBridge = {
    bridgeKey: null, keyCode: null, qqReady: false,
    multiplier: 1, externalCalls: 0, events: events,
    report(kind, detail) {
      events.push({ t: Date.now(), kind: str(kind), detail: redact(detail) });
      if (events.length > 200) events.shift();
    },
    setQqReady(v) { this.qqReady = !!v; this.report("qq", v ? "ready" : "reset"); }
  };

  // APK 的 StageWebView 会话通道：只在未定义时安装，避免覆盖官方页面实现。
  if (!window.airMicroSession) {
    window.airMicroSession = {
      postMessage(msg) {
        gameBridge.report("micro", msg);
        const s = str(msg);
        if (s.indexOf("launch:") === 0) gameBridge.setQqReady(true);
      }
    };
  }
  // APK 的两个控制通道用访问器转发，赋值/读取都保留。
  for (const key of ["airControlKey", "airControlResult"]) {
    try {
      let value = null;
      Object.defineProperty(window, key, {
        configurable: true,
        get() { return value; },
        set(v) { value = v; gameBridge.report("control", key + "=" + v); }
      });
    } catch (e) {}
  }

  // ------------------------------------------------------------------
  // SpeedClock / FrameRateControl / TimerProvider / Socket
  // ------------------------------------------------------------------
  const speedClock = {
    multiplier: 1,
    setMultiplier(v) {
      const n = Number(v);
      if (!(n > 0) || n > 16) return false;
      this.multiplier = n;
      gameBridge.multiplier = n;
      gameBridge.report("speed", String(n));
      return true;
    }
  };
  const socket = {
    host: CONST.gateway,
    portFor(zone) {
      const n = parseInt(zone, 10);
      return CONST.runtime.ports[String(n)] || String(10000 + (n || CONST.runtime.defaultZone));
    }
  };

  // ------------------------------------------------------------------
  // 运行时配置：air-boot.js 直接消费（结构与旧 APK 常量对象一致）
  // ------------------------------------------------------------------
  const runtime = CONST.runtime;

  // ------------------------------------------------------------------
  // 按需读取随 IPA 内置的 APK 原始资产（经 AirBundleBridge 的 airNativeBundle）
  // ------------------------------------------------------------------
  function loadAsset(name) {
    const loader = window.__airLoadBundle;
    if (typeof loader !== "function") return Promise.reject(new Error("bundle 桥尚未就绪"));
    return loader("APK/" + name);
  }

  window.__airApk = {
    CONST: CONST,
    descriptor: CONST.descriptor,
    modules: CONST.modules,
    runtime: runtime,
    assets: CONST.assets,
    officialResources: officialResources,
    keyFileLoader: keyFileLoader,
    runtimeAdapter: runtimeAdapter,
    urlLoader: urlLoader,
    security: security,
    loaderContext: loaderContext,
    externalInterface: externalInterface,
    gameBridge: gameBridge,
    speedClock: speedClock,
    socket: socket,
    redact: redact,
    loadAsset: loadAsset,
    events: events
  };
})();
