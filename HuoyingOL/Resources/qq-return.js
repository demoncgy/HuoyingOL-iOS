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
