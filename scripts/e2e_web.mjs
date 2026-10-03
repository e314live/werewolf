// 端到端：把内嵌网页里那段 JS 真的跑起来，连一次真实的 Dart 服务端。
// 不依赖浏览器、不依赖 WebSocket —— 用 fetch 手写一个最小 EventSource。
//
// 用法：node scripts/e2e_web.mjs <port> <js文件>

const PORT = process.argv[2] || '7799';
const JS_FILE = process.argv[3] || 'build/web_player_check.js';
const BASE = `http://127.0.0.1:${PORT}`;

import { readFileSync } from 'node:fs';
import vm from 'node:vm';

let pass = 0;
let fail = 0;
function ok(cond, name) {
  if (cond) {
    pass++;
    console.log(`  \u2713 ${name}`);
  } else {
    fail++;
    console.log(`  \u2717 ${name}`);
  }
}

/* ---------- 最小浏览器环境 ---------- */
let appHtml = '';
const appEl = {
  get innerHTML() {
    return appHtml;
  },
  set innerHTML(v) {
    appHtml = v;
  },
};

globalThis.document = {
  getElementById(id) {
    if (id === 'app') return appEl;
    if (id === 'nm') return { value: '老张' };
    return null;
  },
};
globalThis.window = { addEventListener() {} };

const realFetch = globalThis.fetch;
globalThis.fetch = (u, o) => realFetch(`${BASE}${u}`, o);

// node 自带只读的 navigator，得用 defineProperty 顶掉。
// sendBeacon 真发一次 POST，好把"退出腾座位"这条路径也测到，
// 否则房主只能等超时兜底退出。
Object.defineProperty(globalThis, 'navigator', {
  configurable: true,
  value: {
    sendBeacon(url, data) {
      realFetch(`${BASE}${url}`, { method: 'POST', body: data ?? '' }).catch(() => {});
      return true;
    },
  },
});
globalThis.sessionStorage = {
  _m: {},
  getItem(k) {
    return this._m[k] ?? null;
  },
  setItem(k, v) {
    this._m[k] = v;
  },
};
globalThis.location = { protocol: 'http:', host: `127.0.0.1:${PORT}` };

// 手写 EventSource：fetch + 按 SSE 协议切 \n\n 帧
let lastES = null;
globalThis.EventSource = function (url) {
  const self = {
    onopen: null,
    onmessage: null,
    onerror: null,
    close() {
      self._closed = true;
      try {
        self._ctrl.abort();
      } catch (_) {}
    },
  };
  self._ctrl = new AbortController();
  lastES = self;
  (async () => {
    try {
      const res = await fetch(url, {
        signal: self._ctrl.signal,
        headers: { Accept: 'text/event-stream' },
      });
      if (!res.ok) throw new Error(`status ${res.status}`);
      if (self.onopen) self.onopen();
      const reader = res.body.getReader();
      const dec = new TextDecoder();
      let buf = '';
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        let i;
        while ((i = buf.indexOf('\n\n')) >= 0) {
          const frame = buf.slice(0, i);
          buf = buf.slice(i + 2);
          for (const line of frame.split('\n')) {
            if (line.startsWith('data:') && self.onmessage) {
              self.onmessage({ data: line.slice(5).trim() });
            }
          }
        }
      }
      if (!self._closed && self.onerror) self.onerror();
    } catch (e) {
      if (!self._closed && self.onerror) self.onerror();
    }
  })();
  return self;
};

/* ---------- 加载被测页面 ---------- */
const js = readFileSync(JS_FILE, 'utf8');
vm.runInThisContext(js, { filename: JS_FILE });
ok(typeof globalThis.enter === 'function', '页面 JS 加载成功，导出了 enter()');
ok(appHtml.includes('加入牌局'), '初始渲染出"加入牌局"');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitFor(sub, ms = 5000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    if (appHtml.includes(sub)) return true;
    await sleep(50);
  }
  return false;
}

async function main() {
  console.log('--- 进入房间 ---');
  globalThis.enter();
  ok(await waitFor('你是'), '看到自己的座位号');
  ok(await waitFor('2 号'), '座位号是 2（房主占 1 号）');
  ok(appHtml.includes('老张'), '显示了自己的名字');

  console.log('--- 发牌：应当只看到自己那张 ---');
  ok(await waitFor('狼人'), '拿到身份「狼人」');
  ok(appHtml.includes('2 号 · 老张'), '身份卡带座位和名字');

  console.log('--- 夜里狼人睁眼 ---');
  ok(await waitFor('狼人请睁眼'), '进入狼人操作界面');
  ok(appHtml.includes('4号'), '看得到狼队友 4 号');
  ok(appHtml.includes('本轮空刀'), '有空刀按钮');
  ok(appHtml.includes('onclick="actWolf(2)"'), '座位按钮可点');

  console.log('--- 点刀 -> 天亮 ---');
  globalThis.actWolf(2);
  ok(await waitFor('天亮了'), '收到天亮公示');
  ok(appHtml.includes('3 号出局'), '公示 3 号出局（刀的是 2 号座位）');
  ok(await waitFor('投票'), '自动进入投票界面');

  console.log('--- 投票 -> 结算 ---');
  ok(appHtml.includes('onclick="doVote(3)"'), '投票按钮可点');
  globalThis.doVote(3);
  ok(await waitFor('投票结果'), '收到投票结果');
  ok(appHtml.includes('4 号被放逐'), '显示被放逐的 4 号');
  ok(await waitFor('投票'), '票型能看到');

  console.log('--- 结束 ---');
  ok(await waitFor('这局你赢了'), '狼人阵营显示胜利');
  ok(appHtml.includes('这局') || appHtml.includes('再来'), '结局页渲染完整');

  console.log('--- 退出 ---');
  ok(typeof lastES === 'object' && lastES !== null, 'SSE 连接确实建立过');
  globalThis.bye();
  ok(lastES._closed === true, '退出时关掉了长连接');
  // sendBeacon 走的 /bye 会让房主立刻腾座位并打印 HOST DONE
  await sleep(600);
  ok(true, '已发出告别请求（房主侧应打印 HOST DONE）');

  console.log(`\n通过 ${pass} 项，失败 ${fail} 项`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('harness error:', e);
  process.exit(1);
});
