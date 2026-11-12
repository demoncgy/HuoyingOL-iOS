// Keep QQ's original OAuth callback and relay only between its official frames.
(() => {
 const home="https://huoying.qq.com", graph="https://graph.qq.com";
 const login=["https://xui.ptlogin2.qq.com","https://ssl.ptlogin2.qq.com"];
 const type="huoying-air-qq-return-v1", origin=location.origin;
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
    // This official handler still verifies OAuth and CSRF on the server; Milo's cached UI state can lag after an iframe return.
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
   for(const frame of document.querySelectorAll('iframe')) {
    let target;try{target=new URL(frame.src).origin;}catch{continue;}
    if(target===graph||login.includes(target))for(const destination of [graph,...login])frame.contentWindow.postMessage(data,destination);
   }
  }
  window.airQqReturn={accepted:false,accept(url){
   this.accepted=false;
   send({type,action:"return",url});
  },mode(kind){
   if(kind!=="password"&&kind!=="qq"&&kind!=="qr")return;
   activeMode=kind;
   clearInterval(modeTimer);
   for(const frame of document.querySelectorAll('iframe')){
    let u;try{u=new URL(frame.src);}catch{continue;}
    if(u.origin===graph&&["/oauth2.0/authorize","/oauth2.0/show"].includes(u.pathname)){
     u.pathname="/oauth2.0/authorize";if(kind==="qq")u.searchParams.set("display","mobile");else u.searchParams.delete("display");
     frame.dataset.airQqMode=kind;frame.src=u.href;
    }
   }
   const attempt=String(Date.now()),started=Date.now(),deadline=started+60000;
   let opened=false,lastOpen=0;
   modeTimer=setInterval(()=>{
    wireZoneLogin();
    if(Date.now()>deadline){clearInterval(modeTimer);return;}
    const exists=[...document.querySelectorAll('iframe')].some(f=>{try{return [graph,...login].includes(new URL(f.src).origin);}catch{return false;}});
    if(exists)opened=true;
    if(!exists&&!opened&&Date.now()-started>=500&&Date.now()-lastOpen>=1000){lastOpen=Date.now();document.getElementById('dologin')?.click();}
    if(kind==="qq")for(const frame of document.querySelectorAll('iframe')){
     let u;try{u=new URL(frame.src);}catch{continue;}
     if(u.origin===graph&&["/oauth2.0/authorize","/oauth2.0/show"].includes(u.pathname)&&!frame.dataset.airQqMode){
      frame.dataset.airQqMode="1";u.pathname="/oauth2.0/authorize";u.searchParams.set("display","mobile");frame.src=u.href;
     }
    }
    send({type,action:kind,attempt});
   },250);
  }};
  addEventListener('message',e=>{
   if(e.data?.type===type&&e.data.action==="accepted"&&(e.origin===graph||login.includes(e.origin))&&
     [...document.querySelectorAll('iframe')].some(f=>f.contentWindow===e.source))window.airQqReturn.accepted=true;
   if(e.data?.type===type&&e.data.action==="mode-ready"&&(e.origin===graph||login.includes(e.origin))&&
     [...document.querySelectorAll('iframe')].some(f=>f.contentWindow===e.source)&&activeMode==="qq")clearInterval(modeTimer);
  });return;
 }
 if(origin!==graph&&!login.includes(origin))return;
 let issued,qrAttempt;
 addEventListener('message',e=>{
  const d=e.data;if(d?.type!==type)return;
  if(origin===graph&&["accepted","mode-ready"].includes(d.action)&&login.includes(e.origin)&&
    [...document.querySelectorAll('iframe')].some(f=>f.contentWindow===e.source)){
   window.parent.postMessage({type,action:d.action},home);return;
  }
  if(e.source!==window.parent)return;
  if(origin===graph){
   if(e.origin!==home)return;
   for(const f of document.querySelectorAll('iframe'))for(const target of login)f.contentWindow.postMessage(d,target);
  }else if((e.origin===home||e.origin===graph)&&d.action==="return"&&typeof d.url==="string"){
   let u;try{u=new URL(d.url);}catch{return;}
   if(u.origin!=="https://ssl.ptlogin2.qq.com"||u.pathname!=="/jump"||u.username||u.password||u.hash)return;
   window.parent.postMessage({type,action:"accepted"},e.origin);location.replace(u.href);
  }else if((e.origin===home||e.origin===graph)&&typeof d.attempt==="string"&&issued!==d.attempt){
   if(d.action==="password"&&document.getElementById('switcher_plogin')){
    if(document.readyState!=="complete"||typeof window.pt?.plogin?.switchpage!=="function")return;
    document.getElementById('switcher_plogin').click();
    if(window.pt.plogin.loginState!==1||!(document.getElementById('p')?.getBoundingClientRect().height>0))return;
    issued=d.attempt;
   }else if(d.action==="qr"){
    const button=document.getElementById('switcher_qlogin'),image=document.getElementById('qrlogin_img');
    if(document.readyState!=="complete"||!button||!image)return;
    if(!(image.getBoundingClientRect().height>0&&image.naturalWidth>0)){
     if(qrAttempt!==d.attempt){qrAttempt=d.attempt;button.click();}
     return;
    }
    issued=d.attempt;
   }else if(d.action==="qq"&&window.pt?.hasInit&&typeof window.pt.doOneKey==="function"){
    issued=d.attempt;window.pt.isAndroid=true;window.pt.doOneKey();
   }else return;
   window.parent.postMessage({type,action:"mode-ready"},e.origin);
  }
 });
})();
