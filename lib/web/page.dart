/// 浏览器玩家端：房主用同一个端口直接把它发给手机浏览器。
/// 单文件、零外部依赖、深色竖屏优先，界面与 App 内的玩家端一一对应。
///
/// 注意：这是 Dart raw string，里面不能出现连续三个英文单引号。
const String webPlayerPage = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#12101A">
<meta name="apple-mobile-web-app-capable" content="yes">
<title>狼邮杀 · 玩家</title>
<style>
:root{--bg:#12101A;--card:#1D1A28;--line:#2E2940;--txt:#EDEAF5;--dim:#9C96AE;
--wolf:#D33F49;--god:#E8A33D;--purple:#8E5BD6;--blue:#5A8FD6;--green:#4CAF7D}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--txt);
font:15px/1.6 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif}
.wrap{max-width:520px;margin:0 auto;padding:20px 16px calc(40px + env(safe-area-inset-bottom))}
h1{font-size:21px;margin:4px 0 4px;font-weight:800}
.sub{color:var(--dim);font-size:13px;margin-bottom:6px}
label{display:block;font-weight:700;font-size:14px;margin:18px 0 8px}
input{width:100%;padding:14px;border-radius:12px;border:1px solid var(--line);
background:#191623;color:var(--txt);font-size:16px;outline:none;font-family:inherit}
input:focus{border-color:var(--purple)}
button{width:100%;padding:15px;border:0;border-radius:14px;font-size:17px;font-weight:800;
background:var(--purple);color:#fff;margin-top:20px;font-family:inherit;cursor:pointer}
button:active{opacity:.82}
button.ghost{background:transparent;border:1px solid var(--line);color:var(--txt);
font-weight:600;font-size:14px;margin-top:12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin-top:14px}
.role{border-radius:22px;padding:26px 20px;text-align:center;border:1.5px solid}
.rn{font-size:36px;font-weight:900;letter-spacing:5px}
.who{font-size:15px;color:var(--dim);margin-top:8px}
.rd{font-size:13px;color:var(--dim);margin-top:12px;line-height:1.7}
.big{font-size:26px;font-weight:900}
.dir{font-size:13px;color:var(--dim);margin-top:6px}
.err{margin-top:16px;padding:12px 14px;border-radius:12px;background:#2A1620;
border:1px solid var(--wolf);color:#F09595;font-size:13.5px;line-height:1.6}
.warn{margin-top:14px;padding:10px 14px;border-radius:12px;background:#2A2416;
border:1px solid var(--god);color:#FAC775;font-size:13px}
.spin{width:26px;height:26px;margin:16px auto 12px;border:3px solid var(--line);
border-top-color:var(--purple);border-radius:50%;animation:sp .9s linear infinite}
@keyframes sp{to{transform:rotate(360deg)}}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(64px,1fr));gap:10px;margin-top:14px}
.seat{height:70px;border-radius:14px;background:#2A2538;display:flex;flex-direction:column;
align-items:center;justify-content:center;font-size:22px;font-weight:900;cursor:pointer;
border:2px solid transparent;user-select:none}
.seat span{font-size:11px;font-weight:400;color:var(--dim);line-height:1.2}
.seat.dead{background:#1A1725;color:#4A4458;cursor:default}
.seat.sel{border-color:var(--god);background:#38324A}
.seat.wolf{background:#3A1F26;color:var(--wolf)}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.chip{width:38px;height:38px;border-radius:10px;background:#38324A;display:flex;
align-items:center;justify-content:center;font-weight:700;font-size:15px}
.chip.out{background:#1A1725;color:#4A4458;text-decoration:line-through}
.row{display:flex;gap:10px;margin-top:14px}
.row button{margin-top:0}
.opt{flex:1;padding:12px;border-radius:12px;border:1.5px solid var(--line);background:#221E30;
text-align:center;font-weight:700;cursor:pointer;font-size:15px}
.opt.on{border-color:var(--god);background:#3A3222;color:var(--god)}
.blk{margin-top:16px;color:var(--dim);font-size:13.5px;line-height:1.7}
.hl{color:var(--wolf);font-weight:800}
.gd{color:var(--god);font-weight:800}
.tagline{margin-top:26px;text-align:center;color:#5C5670;font-size:11.5px;line-height:1.8}
</style>
</head>
<body>
<div class="wrap" id="app"></div>
<script>
var ROLES=["狼人","平民","预言家","女巫","猎人","守卫"];
var RDESC=["每晚可刀一人，与其他狼互认","没有技能，靠推理找出狼人",
"每晚可查验一人的身份","有一瓶解药(救)与一瓶毒药(毒)，各限一次",
"出局时可开枪带走一人（被毒死不能开枪）","每晚可守护一人（不可自守），被守的人免疫刀与毒"];
var RCOL=["#D33F49","#5A8FD6","#E8A33D","#8E5BD6","#4CAF7D","#33A1B1"];
var S={stage:"connect",seat:-1,name:"",role:null,seatCount:9,alive:[],deaths:[],
actor:null,wolves:[],seerResult:null,nightVictim:null,canHeal:true,canPoison:true,
useHeal:false,poisonTarget:null,voting:false,revote:false,ejected:null,gun:null,
tally:{},winner:null,err:null,ok:false};
var es=null;
var cid=(function(){
  var v=null;try{v=sessionStorage.getItem("wolf_cid");}catch(e){}
  if(!v){v=Math.random().toString(36).slice(2)+Date.now().toString(36);
    try{sessionStorage.setItem("wolf_cid",v);}catch(e){}}
  return v;})();

function esc(s){return String(s).replace(/[&<>"']/g,function(c){
  return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c];});}
function send(o){
  try{
    fetch("/act?cid="+encodeURIComponent(cid),{method:"POST",
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify(o)}).catch(function(){});
  }catch(e){}
}

function openStream(){
  var url="/events?cid="+encodeURIComponent(cid)+"&name="+encodeURIComponent(S.name);
  try{es=new EventSource(url);}catch(e){
    es=null;S.stage="connect";
    S.err="这个浏览器不支持长连接，换 Chrome / Safari / 华为浏览器试试";
    render();return;
  }
  es.onopen=function(){S.conn=true;S.err=null;render();};
  es.onmessage=function(ev){
    var m=null;try{m=JSON.parse(ev.data);}catch(e){return;}
    handle(m);
  };
  es.onerror=function(){
    S.conn=false;
    if(S.ok){
      S.err="和房主断开了，正在自动重连…";render();
    }else{
      try{es.close();}catch(e){}
      es=null;S.stage="connect";
      if(!S.err)S.err="连不上房主，确认你和房主连在同一个 WiFi（房间也可能已经关了）";
      render();
    }
  };
}
function enter(){
  var v=document.getElementById("nm").value.trim()||"室友";
  S.name=v;S.err=null;S.stage="wait";render();openStream();
}
function back(){
  bye();
  S.ok=false;S.stage="connect";S.seat=-1;S.err=null;render();
}

function handle(m){
  var t=m.t,d=m.d||{};
  if(t!=="gone"&&t!=="cancel")S.err=null;
  if(t==="seat"){S.seat=d.seat|0;S.seatCount=d.total||S.seatCount;S.ok=true;}
  else if(t==="full"){
    S.err="房间已经坐满了，让房主把人数加一加再进";S.stage="connect";S.ok=false;
    try{es.close();}catch(e){} es=null;}

  else if(t==="role"){
    var r=d.role;
    S.role=(typeof r==="number"&&r>=0&&r<ROLES.length)?r:1;
    if(typeof d.seat==="number")S.seat=d.seat;
    if(d.name)S.name=d.name;
    S.ok=true;S.stage="play";}
  else if(t==="roster"){if(d.seats&&d.seats.length)S.seatCount=d.seats.length;}
  else if(t==="phase"){
    var p=d.phase;
    if(Object.prototype.toString.call(d.alive)==="[object Array]")S.alive=d.alive;
    if(Object.prototype.toString.call(d.deaths)==="[object Array]")S.deaths=d.deaths;
    if(p==="night"){S.actor=null;S.voting=false;S.ejected=null;S.gun=null;S.deaths=[];}
    if(p==="dawn"){S.actor=null;S.voting=false;S.ejected=null;}}
  else if(t==="wake"){
    S.actor=d.actor||null;
    S.wolves=(d.wolves&&d.wolves.length)?d.wolves:[];
    S.seerResult=d.checked||null;
    S.nightVictim=(typeof d.target==="number")?d.target:null;
    S.canHeal=(d.canHeal!==false);S.canPoison=(d.canPoison!==false);
    S.useHeal=false;S.poisonTarget=null;}
  else if(t==="vote_open"){
    S.actor=null;S.voting=true;S.ejected=null;S.gun=null;S.revote=!!d.revote;
    if(d.seats&&d.seats.length)S.alive=d.seats;}
  else if(t==="vote_result"){
    S.voting=false;S.tally=d.tally||{};
    S.ejected=(typeof d.ejected==="number")?d.ejected:null;
    S.gun=(typeof d.gun==="number")?d.gun:null;}
  else if(t==="over"){
    S.winner=d.winner||null;S.actor=null;S.voting=false;S.stage="over";}
  else if(t==="gone"){S.err="和房主断开了，正在自动重连…";}
  else if(t==="cancel"){S.tally={};}
  render();
}

function seatGrid(dead,sel,fn,wolfish){
  var h='<div class="grid">',i,d;
  for(i=0;i<S.seatCount;i++){
    d=dead.indexOf(i)>=0;
    h+='<div class="seat'+(d?" dead":"")+(sel===i?" sel":"")+
       (wolfish&&wolfish.indexOf(i)>=0?" wolf":"")+'"'+
       (d?"":' onclick="'+fn+"("+i+')"')+'>'+(i+1)+
       "<span>"+(d?"出局":"")+"</span></div>";
  }
  return h+"</div>";
}
// alive 为空 = 还没收到过存活名单，一律按"都活着"处理，否则第一夜全变灰点不动
function isAlive(i){return S.alive.length===0?true:S.alive.indexOf(i)>=0;}
function deadList(self){
  var out=[],i;
  for(i=0;i<S.seatCount;i++){
    if(i===self)continue;
    if(!isAlive(i))out.push(i);
  }
  return out;
}

function viewConnect(){
  return "<h1>加入牌局</h1>"+
  '<div class="sub">房主的房间已经开好了，填个名字就能进</div>'+
  "<label>你的名字</label>"+
  '<input id="nm" maxlength="8" placeholder="比如 老张" value="'+esc(S.name)+'">'+
  (S.err?'<div class="err">'+esc(S.err)+"</div>":"")+
  "<button onclick=\"enter()\">进入房间</button>"+
  '<div class="tagline">狼邮杀 · 同一个 WiFi 就能玩<br>牌只发到你自己手机上，法官也看不到</div>';
}
function viewWait(){
  var h="<h1>已连上法官</h1>";
  if(S.seat>=0){
    h+='<div class="card" style="text-align:center">'+
    '<div class="dir">你是</div>'+
    '<div class="big" style="color:var(--purple)">'+(S.seat+1)+" 号</div>"+
    '<div class="dir">'+esc(S.name)+" · 共 "+S.seatCount+" 人</div></div>";
  }
  h+='<div class="card"><div class="spin"></div>'+
  '<div style="text-align:center;color:var(--dim)">等房主发牌…</div></div>'+
  (S.err?'<div class="err">'+esc(S.err)+"</div>":"")+
  '<button class="ghost" onclick="back()">返回重填名字</button>';
  return h;
}
function roleCard(){
  var i=(S.role===null)?1:S.role,c=RCOL[i];
  return '<div class="role" style="border-color:'+c+";background:linear-gradient(135deg,"+
  c+"44,"+c+'12)"><div class="rn" style="color:'+c+'">'+ROLES[i]+"</div>"+
  '<div class="who">'+(S.seat+1)+" 号 · "+esc(S.name)+"</div>"+
  '<div class="rd">'+RDESC[i]+"</div></div>";
}
function viewIdle(){
  var i,h="",alive=S.alive.length?S.alive:null;
  h+=roleCard();
  h+='<div class="card"><div style="font-weight:800">局势</div>'+
  '<div class="dir">存活：'+(alive?alive.length:S.seatCount)+" 人</div>"+
  '<div class="chips">';
  for(i=0;i<S.seatCount;i++){
    h+='<div class="chip'+(isAlive(i)?"":" out")+'"'+
       (i===S.seat?' style="border:2px solid var(--purple)"':"")+">"+(i+1)+"</div>";
  }
  h+="</div>";
  if(S.deaths.length){
    h+='<div class="blk"><span class="hl">'+
    S.deaths.map(function(x){return (x+1)+" 号出局";}).join("，")+"</span></div>";
  }
  h+="</div>";
  h+='<div class="tagline">盯紧发言，别被票出去</div>';
  return h;
}
function viewVote(){
  var h='<h1>'+(S.revote?"平票了，再投一轮":"投票")+"</h1>"+
  '<div class="sub">把你怀疑的人投出去（你投给谁，只有法官看得到）</div>'+
  seatGrid(deadList(-1),-1,"doVote");
  return h;
}
function viewResult(){
  var h='<h1>投票结果</h1><div class="card">';
  h+='<div class="big" style="color:var(--wolf)">'+
  (S.ejected===null?"本轮无人出局":(S.ejected+1)+" 号被放逐")+"</div>";
  if(S.gun!==null)h+='<div class="blk" style="color:var(--green)">猎人开枪带走了 '+(S.gun+1)+" 号</div>";
  h+="</div>";
  var k,parts=[];
  for(k in S.tally){if(S.tally.hasOwnProperty(k))parts.push((parseInt(k,10)+1)+"号 "+S.tally[k]+"票");}
  if(parts.length)h+='<div class="blk">'+parts.join("　")+"</div>";
  return h;
}
function viewDawn(){
  var h='<h1>天亮了</h1><div class="card">';
  h+=S.deaths.map(function(x){
    return '<div class="big" style="color:var(--wolf)">'+(x+1)+" 号出局</div>";}).join("");
  h+="</div>";
  return h;
}
function viewAction(){
  var h="",i;
  if(S.actor==="guard"){
    h+='<h1>守卫请睁眼</h1><div class="sub">今晚要守护谁？（不能守自己）</div>'+
    seatGrid(deadList(-1),-1,"actGuard");
  }else if(S.actor==="werewolf"){
    h+='<h1>狼人请睁眼</h1>';
    if(S.wolves.length>1){
      h+='<div class="blk">你的狼队友：<span class="hl">'+
      S.wolves.map(function(w){return (w+1)+"号";}).join("、")+"</span></div>";
    }
    h+='<div class="sub" style="margin-top:12px">今晚要刀谁？</div>'+
    seatGrid(deadList(-1),-1,"actWolf");
    h+='<button class="ghost" onclick="wolfPass()">本轮空刀</button>';
  }else if(S.actor==="seer"){
    h+='<h1>预言家请睁眼</h1><div class="sub">要验几号？</div>'+
    seatGrid(deadList(-1),-1,"actSeer");
  }else if(S.actor==="witch"){
    h+='<h1>女巫请睁眼</h1>'+
    '<div class="card"><div class="blk" style="margin-top:0">'+
    (S.nightVictim===null?"法官告诉你：今夜没有人被刀":
      '法官告诉你：今夜 <span class="hl">'+(S.nightVictim+1)+' 号</span> 被刀了')+
    "</div></div>";
    h+='<div style="font-weight:700;margin-top:18px">'+
    (S.canHeal?"① 要不要用解药救他？":"① 解药已经用掉了")+"</div>";
    if(S.canHeal&&S.nightVictim!==null){
      h+='<div class="row">'+
      '<div class="opt'+(S.useHeal?" on":"")+'" onclick="setHeal(1)">救</div>'+
      '<div class="opt'+(!S.useHeal?" on":"")+'" onclick="setHeal(0)">不救</div></div>';
    }else{
      h+='<div class="blk">（解药只能用在今夜被刀的人身上）</div>';
    }
    h+='<div style="font-weight:700;margin-top:22px">'+
    (S.canPoison?"② 要不要用毒药毒人？":"② 毒药已经用掉了")+"</div>";
    if(S.canPoison){
      h+=seatGrid(deadList(-1),S.poisonTarget===null?-1:S.poisonTarget,"setPoison");
    }
    if(S.poisonTarget!==null){
      h+='<button class="ghost" onclick="setPoison(-1)">取消毒药</button>';
    }
    h+='<button onclick="witchDone()">确认，闭眼</button>';
  }else if(S.actor==="seer_result"){
    h+='<h1>查验结果</h1><div class="card" style="text-align:center">'+
    '<div class="big" style="color:var(--god);font-size:30px">'+esc(S.seerResult||"未知")+"</div></div>"+
    '<button onclick="seerDone()">记住了，闭眼</button>';
  }else{
    h+='<h1>请稍等</h1><div class="card"><div class="spin"></div></div>';
  }
  return h;
}
function viewOver(){
  var win=(S.winner==="good")?(S.role!==0):(S.winner==="wolf"&&S.role===0);
  var c=win?"var(--green)":"var(--wolf)";
  return '<div class="card" style="text-align:center;margin-top:60px">'+
  '<div class="big" style="color:'+c+';font-size:26px">'+
  (win?"这局你赢了 🎉":"这局你输了")+"</div>"+
  '<div class="dir" style="margin-top:10px">'+
  (S.winner==="wolf"?"狼人胜利，天黑到底":(S.winner==="good"?"好人胜利，天亮了":"未知结果"))+
  "</div></div>"+roleCard()+
  '<div class="tagline">这局记完了，下局再来</div>';
}
function render(){
  var el=document.getElementById("app"),html="";
  var banner=(S.conn===false&&S.ok&&S.stage!=="connect")
    ?'<div class="warn">正在重连房主…</div>':"";
  if(S.stage==="connect"){el.innerHTML=viewConnect();return;}
  if(S.stage==="wait"){el.innerHTML=banner+viewWait();return;}
  if(S.stage==="over"){el.innerHTML=banner+viewOver();return;}
  el.innerHTML=banner+viewPlay();
}
function viewPlay(){
  if(S.actor)return viewAction();
  if(S.voting)return viewVote();
  if(S.ejected!==null||S.gun!==null)return viewResult();
  if(S.deaths.length)return viewDawn();
  return viewIdle();
}

function doVote(i){send({t:"act",d:{kind:"vote",target:i}});S.voting=false;render();}
function actGuard(i){send({t:"act",d:{kind:"guard",target:i}});S.actor=null;render();}
function actSeer(i){send({t:"act",d:{kind:"seer",target:i}});S.actor=null;render();}
function actWolf(i){send({t:"act",d:{kind:"werewolf",target:i}});S.actor=null;render();}
function wolfPass(){send({t:"act",d:{kind:"werewolf",target:null}});S.actor=null;render();}
function setHeal(v){S.useHeal=!!v;render();}
function setPoison(i){S.poisonTarget=(i<0?null:i);render();}
function witchDone(){
  send({t:"act",d:{kind:"witch",
    save:!!(S.canHeal&&S.useHeal&&S.nightVictim!==null),
    poison:S.poisonTarget}});
  S.actor=null;render();
}
function seerDone(){send({t:"pass",d:{}});S.actor=null;render();}

function bye(){
  try{navigator.sendBeacon("/bye?cid="+encodeURIComponent(cid));}catch(e){}
  try{es.close();}catch(e){}
  es=null;
}
window.addEventListener("beforeunload",bye);
window.addEventListener("pagehide",bye);
render();
</script>
</body>
</html>
''';
