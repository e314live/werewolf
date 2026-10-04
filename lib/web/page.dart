/// 浏览器玩家端：房主用同一个端口直接把它发给手机浏览器。
/// 单文件、零外部依赖、深色竖屏优先，界面与 App 内的玩家端一一对应。
///
/// 为什么卡面是手绘 SVG 而不是网图：
///   房主是"零后端"的局域网服务，室友手机可能连外网都上不了。
///   外链图片 = 白板 + 版权风险 + 加载慢。SVG 只有几百字节、离线必显、无限缩放。
///
/// 注意：这是 Dart raw string，里面不能出现连续三个英文单引号。
const String webPlayerPage = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#0E0C15">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<title>狼邮杀 · 玩家</title>
<style>
:root{--bg:#0E0C15;--card:#1A1726;--line:#302A44;--txt:#EDEAF5;--dim:#9C96AE;
--wolf:#D33F49;--god:#E8A33D;--purple:#8E5BD6;--blue:#5A8FD6;--green:#4CAF7D}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--txt);
font:15px/1.6 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif;
-webkit-font-smoothing:antialiased;min-height:100vh}
/* 背景：一点点极光和星尘，别太吵 */
#bg{position:fixed;inset:0;z-index:0;pointer-events:none;
background:
 radial-gradient(1000px 520px at 50% -8%,rgba(142,91,214,.22),transparent 62%),
 radial-gradient(780px 460px at 10% 106%,rgba(51,161,177,.15),transparent 60%),
 radial-gradient(700px 420px at 94% 84%,rgba(211,63,73,.11),transparent 60%)}
#bg::after{content:"";position:absolute;inset:0;
background-image:
 radial-gradient(1.4px 1.4px at 12% 18%,rgba(255,255,255,.30),transparent 60%),
 radial-gradient(1.2px 1.2px at 78% 11%,rgba(255,255,255,.22),transparent 60%),
 radial-gradient(1.6px 1.6px at 34% 62%,rgba(255,255,255,.18),transparent 60%),
 radial-gradient(1.2px 1.2px at 88% 54%,rgba(255,255,255,.24),transparent 60%),
 radial-gradient(1.5px 1.5px at 58% 84%,rgba(255,255,255,.16),transparent 60%),
 radial-gradient(1.2px 1.2px at 22% 92%,rgba(255,255,255,.20),transparent 60%),
 radial-gradient(1.3px 1.3px at 66% 32%,rgba(255,255,255,.14),transparent 60%),
 radial-gradient(1.5px 1.5px at 46% 8%,rgba(255,255,255,.18),transparent 60%)}
.wrap{position:relative;z-index:1;max-width:520px;margin:0 auto;
padding:22px 16px calc(40px + env(safe-area-inset-bottom))}
h1{font-size:22px;margin:0 0 6px;font-weight:800;letter-spacing:.5px}
h1 .dot{display:inline-block;width:7px;height:7px;border-radius:50%;
background:var(--purple);margin-right:9px;vertical-align:middle;
box-shadow:0 0 12px var(--purple)}
.sub{color:var(--dim);font-size:13px;margin-bottom:4px}
label{display:block;font-weight:700;font-size:14px;margin:20px 0 8px}
input{width:100%;padding:15px;border-radius:14px;border:1px solid var(--line);
background:#171425;color:var(--txt);font-size:16px;outline:none;font-family:inherit;
transition:border-color .18s}
input:focus{border-color:var(--purple);box-shadow:0 0 0 3px rgba(142,91,214,.16)}
button{width:100%;padding:16px;border:0;border-radius:15px;font-size:17px;font-weight:800;
background:linear-gradient(160deg,#9B67E0,#7A46C4);color:#fff;margin-top:20px;
font-family:inherit;cursor:pointer;letter-spacing:.5px;
box-shadow:0 10px 26px -12px rgba(142,91,214,.9);transition:transform .1s}
button:active{transform:scale(.975);opacity:.92}
button.ghost{background:transparent;border:1px solid var(--line);color:var(--dim);
box-shadow:none;font-weight:600;font-size:14px;margin-top:12px;padding:13px}
.card{background:linear-gradient(170deg,#1D1A2B,#171425);border:1px solid var(--line);
border-radius:18px;padding:16px;margin-top:14px}
.err{margin-top:16px;padding:13px 15px;border-radius:14px;background:#2A1620;
border:1px solid var(--wolf);color:#F09595;font-size:13.5px;line-height:1.6}
.warn{margin-top:14px;padding:11px 15px;border-radius:12px;background:#2A2416;
border:1px solid var(--god);color:#FAC775;font-size:13px;text-align:center}
.spin{width:28px;height:28px;margin:18px auto 14px;border:3px solid var(--line);
border-top-color:var(--purple);border-radius:50%;animation:sp .9s linear infinite}
@keyframes sp{to{transform:rotate(360deg)}}
.big{font-size:26px;font-weight:900}
.dir{font-size:13px;color:var(--dim);margin-top:6px}
.blk{margin-top:14px;color:var(--dim);font-size:13.5px;line-height:1.7}
.hl{color:var(--wolf);font-weight:800}
.gd{color:var(--god);font-weight:800}
.tagline{margin-top:28px;text-align:center;color:#59536E;font-size:11.5px;line-height:1.9}

/* ---------- 座位：3 列牌位，号码大、名字在下 ---------- */
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:16px}
.seat{position:relative;border-radius:16px;padding:12px 6px 11px;text-align:center;
background:linear-gradient(165deg,#2D2740,#1E1A2C);border:1.5px solid #3B3452;
cursor:pointer;user-select:none;overflow:hidden;
transition:transform .1s ease,border-color .18s ease,box-shadow .18s ease}
.seat:active{transform:scale(.95)}
.seat b{display:block;font-size:25px;font-weight:900;line-height:1.05;letter-spacing:-.5px}
.seat em{display:block;font-style:normal;font-size:11.5px;color:var(--dim);
margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding:0 2px}
.seat.off{background:linear-gradient(165deg,#171425,#131020);border-color:#282340;cursor:default}
.seat.off b{color:#514A68}
.seat.off em{color:#4A4460;text-decoration:line-through}
.seat.off::after{content:"";position:absolute;left:-10%;top:50%;width:120%;height:1.5px;
background:#342E4C;transform:rotate(-18deg)}
.seat.sel{border-color:var(--god);background:linear-gradient(165deg,#4B3F22,#2C2515);
box-shadow:0 0 0 3px rgba(232,163,61,.20),0 10px 26px -10px rgba(232,163,61,.65)}
.seat.sel b{color:var(--god)}
.seat.sel em{color:#C9A867}
.seat.me{border-color:var(--purple);box-shadow:0 0 0 3px rgba(142,91,214,.18)}
.seat.me b{color:#BE95FF}
.seat.wolf{border-color:#7C2E38;background:linear-gradient(165deg,#3C1E26,#241319)}
.seat.wolf b{color:var(--wolf)}
.seat.wolf em{color:#B4767E}
.seat .tag{position:absolute;top:6px;right:7px;font-size:9.5px;font-weight:700;
color:#6E6788;letter-spacing:.3px}

/* ---------- 角色卡 ---------- */
.rcard{position:relative;border-radius:20px;overflow:hidden;margin-top:16px;
border:1.5px solid #3B3452;background:#15121F;
box-shadow:0 22px 44px -26px rgba(0,0,0,.95)}
.rcard .glow{position:absolute;inset:0;pointer-events:none}
.rcard .inner{position:relative;padding:22px 18px 20px;text-align:center}
.rcard .sig{width:78px;height:78px;display:block;margin:0 auto 6px;
filter:drop-shadow(0 6px 16px rgba(0,0,0,.55))}
.rcard .rn{font-size:34px;font-weight:900;letter-spacing:5px;line-height:1.15}
.rcard .who{font-size:13.5px;color:var(--dim);margin-top:7px}
.rcard .rd{font-size:13px;color:#B3ACC7;margin-top:13px;line-height:1.75;
padding-top:13px;border-top:1px solid rgba(255,255,255,.07)}
.rcard .corner{position:absolute;font-size:11px;font-weight:800;letter-spacing:1px;
color:rgba(255,255,255,.30)}

/* ---------- 存活小方块 ---------- */
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.chip{min-width:38px;height:38px;padding:0 7px;border-radius:11px;background:#322C48;
display:flex;align-items:center;justify-content:center;font-weight:700;font-size:15px}
.chip.out{background:#191624;color:#4A4460;text-decoration:line-through}
.chip.me{outline:1.5px solid var(--purple);outline-offset:-1px;background:#3A2E55}

.row{display:flex;gap:10px;margin-top:14px}
.row button{margin-top:0}
.opt{flex:1;padding:13px;border-radius:13px;border:1.5px solid var(--line);background:#221E30;
text-align:center;font-weight:700;cursor:pointer;font-size:15px;transition:all .15s}
.opt.on{border-color:var(--god);background:#3B3222;color:var(--god);
box-shadow:0 0 0 3px rgba(232,163,61,.16)}
.tally{margin-top:12px}
.tline{display:flex;align-items:center;justify-content:space-between;gap:10px;
padding:11px 13px;border-radius:12px;background:#1E1A2C;margin-top:8px;font-size:14px;
border:1px solid #2A2540}
.tline.top{border-color:#7C2E38;background:#2A1922}
.tline b{font-weight:800;color:var(--txt)}
.tline i{font-style:normal;color:var(--dim);font-size:12.5px}
.tline .n{color:var(--wolf);font-weight:900}
</style>
</head>
<body>
<div id="bg"></div>
<div class="wrap" id="app"></div>
<script>
var ROLES=["狼人","平民","预言家","女巫","猎人","守卫"];
var RDESC=["每晚可刀一人，与其他狼互认","没有技能，靠推理找出狼人",
"每晚可查验一人的身份","有一瓶解药(救)与一瓶毒药(毒)，各限一次",
"出局时可开枪带走一人（被毒死不能开枪）","每晚可守护一人（不可自守），被守的人免疫刀与毒"];
var RCOL=["#D33F49","#5A8FD6","#E8A33D","#8E5BD6","#4CAF7D","#33A1B1"];
var S={stage:"connect",seat:-1,name:"",role:null,seatCount:9,alive:[],deaths:[],
names:[],actor:null,wolves:[],seerResult:null,seerTarget:null,nightVictim:null,canHeal:true,canPoison:true,
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
/// 座位号 -> 名字后缀。没名字就只显示号码
function nmOf(i){var v=S.names[i];return v?(" · "+esc(v)):"";}
function nmOnly(i){var v=S.names[i];return v?esc(v):"";}

/// 六个角色的手绘矢量符号（stroke 用角色色，浅色填充）
function roleSign(i,c){
  var open='<svg class="sig" viewBox="0 0 64 64" fill="none" stroke="'+c+
    '" stroke-width="3" stroke-linejoin="round" stroke-linecap="round">';
  var p;
  if(i===0){ // 狼人：狼头
    p='<path d="M11 8 L23 21 L41 21 L53 8 L53 32 Q53 52 32 58 Q11 52 11 32 Z"/>'+
      '<circle cx="24" cy="33" r="2.8" fill="'+c+'" stroke="none"/>'+
      '<circle cx="40" cy="33" r="2.8" fill="'+c+'" stroke="none"/>'+
      '<path d="M27 46 L32 43 L37 46" stroke-width="2.4"/>';
  }else if(i===1){ // 平民：人
    p='<circle cx="32" cy="20" r="9.5"/>'+
      '<path d="M13 57 Q13 36 32 36 Q51 36 51 57"/>'+
      '<path d="M32 43 L32 50" stroke-width="2"/>';
  }else if(i===2){ // 预言家：眼
    p='<path d="M6 32 Q32 11 58 32 Q32 53 6 32 Z"/>'+
      '<circle cx="32" cy="32" r="8.5" fill="'+c+'" stroke="none" opacity=".9"/>'+
      '<circle cx="32" cy="32" r="15" stroke-width="1.8" stroke-dasharray="3 5" opacity=".75"/>';
  }else if(i===3){ // 女巫：药瓶
    p='<path d="M26 7 L26 19 L16 39 Q13 46 20 51 L44 51 Q51 46 48 39 L38 19 L38 7 Z"/>'+
      '<path d="M22 7 L42 7"/>'+
      '<path d="M18 38 L46 38" stroke-width="2"/>'+
      '<circle cx="28" cy="44" r="2.4" fill="'+c+'" stroke="none"/>'+
      '<circle cx="37" cy="45" r="1.7" fill="'+c+'" stroke="none"/>';
  }else if(i===4){ // 猎人：准星
    p='<circle cx="32" cy="32" r="17"/>'+
      '<circle cx="32" cy="32" r="3" fill="'+c+'" stroke="none"/>'+
      '<path d="M32 5 L32 17 M32 47 L32 59 M5 32 L17 32 M47 32 L59 32"/>';
  }else{ // 守卫：盾
    p='<path d="M32 6 L52 14 L52 32 Q52 50 32 60 Q12 50 12 32 L12 14 Z"/>'+
      '<path d="M23 32 L30 39 L42 25" stroke-width="3.2"/>';
  }
  return open+p+"</svg>";
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
  else if(t==="roster"){
    if(d.seats&&d.seats.length){
      S.seatCount=d.seats.length;
      S.names=d.seats.map(function(x){return (x&&x.name)||"";});
      if(d.seats[0]&&!S.names[0])S.names[0]="房主";
    }}
  else if(t==="phase"){
    var p=d.phase;
    if(Object.prototype.toString.call(d.alive)==="[object Array]")S.alive=d.alive;
    if(Object.prototype.toString.call(d.deaths)==="[object Array]")S.deaths=d.deaths;
    if(p==="night"){S.actor=null;S.voting=false;S.ejected=null;S.gun=null;S.deaths=[];}
    if(p==="dawn"){S.actor=null;S.voting=false;S.ejected=null;}}
  else if(t==="wake"){
    S.actor=d.actor||null;
    // 狼队友里不该有自己（房主那边已经过滤过，这里再兜一层，
    // 免得手机上真的看到「你的狼队友：你自己」这种鬼话）
    S.wolves=((d.wolves&&d.wolves.length)?d.wolves:[])
      .filter(function(w){return w!==S.seat;});
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

/// 号码牌位：大号码 + 下面跟名字，能点就点，出局划掉
function seatGrid(dead,sel,fn,wolfish){
  var h='<div class="grid">',i,d,w,me;
  for(i=0;i<S.seatCount;i++){
    d=dead.indexOf(i)>=0;
    w=!!(wolfish&&wolfish.indexOf(i)>=0);
    me=(i===S.seat);
    h+='<div class="seat'+(d?" off":"")+(sel===i?" sel":"")+
       (w?" wolf":"")+(me?" me":"")+'"'+
       (d?"":' onclick="'+fn+"("+i+')"')+'>'+
       "<b>"+(i+1)+"</b><em>"+esc(nmOnly(i))+"</em>"+
       (me?'<span class="tag">你</span>':"")+"</div>";
  }
  return h+"</div>";
}
// alive 为空 = 还没收到过存活名单，一律按"都活着"处理，否则第一夜所有座位灰点不动
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
  return '<h1><span class="dot"></span>加入牌局</h1>'+
  '<div class="sub">房主的房间已经开好了，填个名字就能进</div>'+
  "<label>你的名字</label>"+
  '<input id="nm" maxlength="8" placeholder="比如 老张" value="'+esc(S.name)+'">'+
  (S.err?'<div class="err">'+esc(S.err)+"</div>":"")+
  "<button onclick=\"enter()\">进入房间</button>"+
  '<div class="tagline">狼邮杀 · 同一个 WiFi 就能玩<br>牌只发到你自己手机上，法官也看不到</div>';
}
function viewWait(){
  var h='<h1><span class="dot"></span>已连上法官</h1>';
  if(S.seat>=0){
    h+='<div class="card" style="text-align:center">'+
    '<div class="dir">你是</div>'+
    '<div class="big" style="color:var(--purple);font-size:38px;letter-spacing:1px">'+
    (S.seat+1)+" 号</div>"+
    '<div class="dir">'+esc(S.name)+" · 共 "+S.seatCount+" 人</div></div>";
  }
  h+='<div class="card"><div class="spin"></div>'+
  '<div style="text-align:center;color:var(--dim)">等房主发牌…</div></div>'+
  (S.err?'<div class="err">'+esc(S.err)+"</div>":"")+
  '<button class="ghost" onclick="back()">返回重填名字</button>';
  return h;
}
/// 角色卡：卡面渐变 + 手绘符号 + 名字 + 技能说明
function roleCard(){
  var i=(S.role===null)?1:S.role,c=RCOL[i],nm=ROLES[i];
  return '<div class="rcard" style="border-color:'+c+'66">'+
  '<div class="glow" style="background:radial-gradient(120% 90% at 50% 0%,'+c+
  '4D,transparent 68%)"></div>'+
  '<div class="corner" style="left:14px;top:11px">WOLF</div>'+
  '<div class="corner" style="right:14px;top:11px">'+(i+1)+"/"+ROLES.length+"</div>"+
  '<div class="inner">'+roleSign(i,c)+
  '<div class="rn" style="color:'+c+'">'+nm+"</div>"+
  '<div class="who">'+(S.seat+1)+" 号"+nmOf(S.seat)+"</div>"+
  '<div class="rd">'+RDESC[i]+"</div></div></div>";
}
function viewIdle(){
  var i,h="",alive=S.alive.length?S.alive:null;
  h+=roleCard();
  h+='<div class="card"><div style="font-weight:800">局势</div>'+
  '<div class="dir">存活：'+(alive?alive.length:S.seatCount)+" / "+S.seatCount+" 人</div>"+
  '<div class="chips">';
  for(i=0;i<S.seatCount;i++){
    h+='<div class="chip'+(isAlive(i)?"":" out")+(i===S.seat?" me":"")+'">'+(i+1)+"</div>";
  }
  h+="</div>";
  if(S.deaths.length){
    h+='<div class="blk"><span class="hl">'+
    S.deaths.map(function(x){return (x+1)+" 号"+nmOf(x);}).join("，")+
    " 出局</span></div>";
  }
  h+="</div>";
  h+='<div class="tagline">盯紧发言，别被票出去</div>';
  return h;
}
function viewVote(){
  return '<h1><span class="dot"></span>'+(S.revote?"平票了，再投一轮":"投票")+"</h1>"+
  '<div class="sub">把你怀疑的人投出去（你投给谁，只有法官看得到）</div>'+
  seatGrid(deadList(-1),-1,"doVote");
}
function viewResult(){
  var h='<h1><span class="dot"></span>投票结果</h1><div class="card">';
  h+='<div class="big" style="color:var(--wolf);font-size:23px">'+
  (S.ejected===null?"本轮无人出局":(S.ejected+1)+" 号"+nmOf(S.ejected)+" 被放逐")+"</div>";
  if(S.gun!==null){
    h+='<div class="blk" style="color:var(--green)">猎人开枪带走了 '+
    (S.gun+1)+" 号"+nmOf(S.gun)+"</div>";
  }
  h+="</div>";
  var k,parts=[];
  for(k in S.tally){
    if(S.tally.hasOwnProperty(k)){
      parts.push({s:parseInt(k,10),n:S.tally[k]});
    }
  }
  if(parts.length){
    parts.sort(function(a,b){return b.n-a.n;});
    h+='<div class="tally">';
    for(k=0;k<parts.length;k++){
      h+='<div class="tline'+(k===0?" top":"")+'"><b>'+(parts[k].s+1)+" 号"+
      nmOf(parts[k].s)+'</b><i>得票</i> <span class="n">'+parts[k].n+"</span></div>";
    }
    h+="</div>";
  }
  return h;
}
function viewDawn(){
  var h='<h1><span class="dot"></span>天亮了</h1><div class="card">';
  if(!S.deaths.length){
    h+='<div class="dir">昨夜是平安夜</div>';
  }else{
    h+=S.deaths.map(function(x){
      return '<div class="big" style="color:var(--wolf);font-size:23px">'+
      (x+1)+" 号"+nmOf(x)+" 出局</div>";}).join("");
  }
  h+="</div>";
  return h;
}
function viewAction(){
  var h="",i;
  if(S.actor==="guard"){
    h+='<h1><span class="dot"></span>守卫请睁眼</h1>'+
    '<div class="sub">今晚要守护谁？（不能守自己）</div>'+
    seatGrid(deadList(-1),-1,"actGuard");
  }else if(S.actor==="werewolf"){
    h+='<h1><span class="dot"></span>狼人请睁眼</h1>';
    if(S.wolves.length){
      h+='<div class="blk">你的狼队友：<span class="hl">'+
      S.wolves.map(function(w){return (w+1)+" 号"+nmOf(w);}).join("、")+"</span></div>";
    }
    h+='<div class="sub" style="margin-top:14px">今晚要刀谁？</div>'+
    seatGrid(deadList(S.seat),-1,"actWolf",S.wolves);
    h+='<button class="ghost" onclick="wolfPass()">本轮空刀</button>';
  }else if(S.actor==="seer"){
    h+='<h1><span class="dot"></span>预言家请睁眼</h1><div class="sub">要验几号？</div>'+
    seatGrid(deadList(S.seat),-1,"actSeer");
  }else if(S.actor==="witch"){
    h+='<h1><span class="dot"></span>女巫请睁眼</h1>'+
    '<div class="card"><div class="blk" style="margin-top:0">'+
    (S.nightVictim===null?"法官告诉你：今夜没有人被刀":
      '法官告诉你：今夜 <span class="hl">'+(S.nightVictim+1)+" 号"+nmOf(S.nightVictim)+
      "</span> 被刀了")+
    "</div></div>";
    h+='<div style="font-weight:700;margin-top:20px">'+
    (S.canHeal?"① 要不要用解药救他？":"① 解药已经用掉了")+"</div>";
    if(S.canHeal&&S.nightVictim!==null){
      h+='<div class="row">'+
      '<div class="opt'+(S.useHeal?" on":"")+'" onclick="setHeal(1)">救</div>'+
      '<div class="opt'+(!S.useHeal?" on":"")+'" onclick="setHeal(0)">不救</div></div>';
    }else{
      h+='<div class="blk">（解药只能用在今夜被刀的人身上）</div>';
    }
    h+='<div style="font-weight:700;margin-top:24px">'+
    (S.canPoison?"② 要不要用毒药毒人？":"② 毒药已经用掉了")+"</div>";
    if(S.canPoison){
      h+=seatGrid(deadList(-1),S.poisonTarget===null?-1:S.poisonTarget,"setPoison");
    }
    if(S.poisonTarget!==null){
      h+='<button class="ghost" onclick="setPoison(-1)">取消毒药</button>';
    }
    h+='<button onclick="witchDone()">确认，闭眼</button>';
  }else if(S.actor==="seer_result"){
    h+='<h1><span class="dot"></span>查验结果</h1>'+
    '<div class="card" style="text-align:center">'+
    (S.seerTarget!==null&&S.seerTarget!==undefined?
      '<div class="dir">'+(S.seerTarget+1)+" 号"+nmOf(S.seerTarget)+"</div>":"")+
    '<div class="big" style="color:var(--god);font-size:32px;letter-spacing:2px">'+
    esc(S.seerResult||"未知")+"</div></div>"+
    '<button onclick="seerDone()">记住了，闭眼</button>';
  }else{
    h+='<h1><span class="dot"></span>请稍等</h1><div class="card"><div class="spin"></div></div>';
  }
  return h;
}
function viewOver(){
  var win=(S.winner==="good")?(S.role!==0):(S.winner==="wolf"&&S.role===0);
  var c=win?"var(--green)":"var(--wolf)";
  return '<div class="card" style="text-align:center;margin-top:46px">'+
  '<div class="big" style="color:'+c+';font-size:27px">'+
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
function actSeer(i){S.seerTarget=i;send({t:"act",d:{kind:"seer",target:i}});S.actor=null;render();}
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
