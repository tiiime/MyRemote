import Foundation

/// 手机端单页遥控器。页面通过 HTTPS 加载，麦克风走 getUserMedia + WebSocket PCM。
/// 视觉按移动端单手操作设计：遥控区可滚动，语音键固定在底部安全区。
enum WebPage {
    static let html = #"""
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>MyRemote 遥控器</title>
<style>
:root{
  --green:#58cc02; --green-dark:#46a302; --green-soft:#efffe6;
  --ink:#2f2f2f; --muted:#7a7a7a; --line:#e6e6e6; --paper:#fff;
  --bg:#f4f7f2; --blue:#1cb0f6; --red:#ff5a5f;
  --safe-top:env(safe-area-inset-top,0px); --safe-bottom:env(safe-area-inset-bottom,0px);
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{height:100%;margin:0;overflow:hidden;overscroll-behavior:none}
body{
  background:radial-gradient(circle at 50% -10%,#e4ffd4 0,#f4f7f2 42%,#eef1ec 100%);
  color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Rounded","PingFang SC",sans-serif;
  -webkit-user-select:none;user-select:none;-webkit-touch-callout:none;
  -webkit-font-smoothing:antialiased;
}
button,span,div{ -webkit-user-select:none;user-select:none;-webkit-touch-callout:none;-webkit-user-drag:none }
button{
  appearance:none;border:0;background:none;color:inherit;font:inherit;padding:0;
  cursor:pointer;touch-action:manipulation;
}
.app{
  width:100%;max-width:430px;margin:0 auto;height:100dvh;display:flex;flex-direction:column;
  padding:calc(8px + var(--safe-top)) 14px calc(8px + var(--safe-bottom));
  gap:10px;
}
.top{display:flex;align-items:center;justify-content:space-between;min-height:40px}
.brand{display:flex;align-items:center;gap:9px;font-weight:900;font-size:19px;letter-spacing:-.4px}
.logo{width:32px;height:32px;border-radius:11px;background:var(--green);display:grid;place-items:center;color:#fff;font-size:15px;box-shadow:0 3px 0 var(--green-dark)}
.top-right{display:flex;align-items:center;gap:8px}
.status{display:flex;align-items:center;gap:5px;font-size:11px;color:var(--muted);font-weight:800}
.dot{width:7px;height:7px;border-radius:50%;background:#c9c9c9;transition:background .2s}
.dot.on{background:var(--green);box-shadow:0 0 0 4px rgba(88,204,2,.13)}
.help{width:30px;height:30px;border-radius:50%;border:1.5px solid var(--line);background:#fff;color:var(--muted);font-weight:900;font-size:13px}
.modes{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;background:#e9eee6;padding:4px;border-radius:15px}
.mode{border-radius:12px;padding:8px 4px;font-size:12px;font-weight:900;color:#8b9587;transition:.15s}
.mode.sel{background:#fff;color:var(--green-dark);box-shadow:0 2px 6px rgba(44,82,28,.10)}
.stage{flex:1;min-height:0;overflow-y:auto;overflow-x:hidden;-webkit-overflow-scrolling:touch;padding:2px 0;scrollbar-width:none}
.stage::-webkit-scrollbar{display:none}
.remote{
  background:var(--paper);border:1.5px solid #e4e8e1;border-radius:30px;
  padding:14px 16px 15px;box-shadow:0 12px 30px rgba(43,72,29,.08);
  display:flex;flex-direction:column;gap:10px;min-height:0;
}
.remote-head{display:flex;align-items:center;justify-content:space-between;min-height:44px}
.remote-label{font-size:9px;font-weight:900;letter-spacing:.11em;color:#b0b7ac;text-align:center;flex:1}
.key{
  width:56px;height:56px;border-radius:50%;background:#fff;color:#3e4a3a;
  border:1.7px solid #3e4a3a;
  display:grid;place-items:center;font-size:19px;font-weight:900;line-height:1;
  box-shadow:none;transition:transform .06s,background .15s;
  -webkit-user-select:none;user-select:none;-webkit-touch-callout:none;touch-action:manipulation;
}
.key.pressed,.key:active{transform:scale(.94);background:#f1f5ee}
.key.ghost{background:#fff;border:1.7px solid #3e4a3a;box-shadow:none;font-size:15px}
.key.mic{background:#fff;color:#3e4a3a;border-color:#3e4a3a;box-shadow:none}
.key.small{width:48px;height:48px;font-size:17px}
.icon{width:23px;height:23px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round;display:block}
.icon.sm{width:17px;height:17px;stroke-width:2.1}
.icon.lg{width:27px;height:27px;stroke-width:1.8}
.dpad{position:relative;width:min(224px,58vw);height:min(224px,58vw);margin:3px auto 1px;border-radius:50%;background:#fff;border:1.7px solid #3e4a3a}
.dpad .key{position:absolute;width:64px;height:64px;box-shadow:none;background:transparent;border:0;color:#3e4a3a}
.dpad .key:active{background:#f1f5ee;transform:scale(.92)}
.dpad .up:active{transform:translateX(-50%) scale(.92)}
.dpad .down:active{transform:translateX(-50%) scale(.92)}
.dpad .left:active{transform:translateY(-50%) scale(.92)}
.dpad .right:active{transform:translateY(-50%) scale(.92)}
.dpad .up{left:50%;top:6px;transform:translateX(-50%)}
.dpad .down{left:50%;bottom:6px;transform:translateX(-50%)}
.dpad .left{left:6px;top:50%;transform:translateY(-50%)}
.dpad .right{right:6px;top:50%;transform:translateY(-50%)}
.dpad .up:active,.dpad .down:active{transform:translateX(-50%) translateY(3px)}
.dpad .left:active,.dpad .right:active{transform:translateY(-50%) translateY(3px)}
.dpad .ok{
  left:50%;top:50%;transform:translate(-50%,-50%);width:66px;height:66px;
  background:#3e4a3a;border:0;box-shadow:none;font-size:13px;color:#fff;
}
.dpad .ok:active{transform:translate(-50%,-50%) scale(.94);background:#2f3a2c}
.controls{display:flex;align-items:center;justify-content:space-between;padding:0 2px}
.nav{display:flex;gap:9px}
.nav .key{width:50px;height:50px}
.volume{display:flex;flex-direction:column;align-items:center;justify-content:center;padding:3px;border:1.7px solid #3e4a3a;border-radius:27px;background:#fff}
.volume .key{width:42px;height:42px;box-shadow:none;background:transparent;border:0;font-size:21px}
.volume .key:active{background:#f1f5ee;transform:scale(.92)}
.volume .line{width:20px;height:1.5px;background:#3e4a3a;opacity:.5;margin:1px 0}
.tv{width:100%;height:46px;border-radius:23px;background:#fff;border:1.7px solid #3e4a3a;box-shadow:none;font-size:13px;font-weight:900;letter-spacing:.08em;display:flex;align-items:center;justify-content:center;gap:8px}
.tv:active{background:#f1f5ee;transform:scale(.99)}
.log{background:#fff;border:1.5px solid #e4e8e1;border-radius:18px;padding:10px 13px;min-height:62px;display:flex;flex-direction:column;gap:4px}
.log-head{display:flex;align-items:center;justify-content:space-between;font-size:9px;font-weight:900;letter-spacing:.08em;color:#aab2a5;text-transform:uppercase}
.log-text{font-size:14px;font-weight:750;line-height:1.35;color:var(--ink);overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;min-height:19px}
.log-text.empty{color:#b7beb3;font-weight:650}
.dock{display:flex;flex-direction:column;gap:7px}
.voice{
  position:relative;width:100%;min-height:68px;border-radius:22px;background:var(--green);color:#fff;
  box-shadow:0 5px 0 var(--green-dark);display:flex;align-items:center;justify-content:center;gap:10px;
  font-size:17px;font-weight:900;letter-spacing:.01em;
  -webkit-user-select:none;user-select:none;-webkit-touch-callout:none;touch-action:none;
  overflow:hidden;transition:background .15s,transform .06s,box-shadow .06s;
}
.voice:active{transform:translateY(2px);box-shadow:0 3px 0 var(--green-dark)}
.voice.rec{background:var(--red);box-shadow:0 5px 0 #d94449;animation:breathe 1.2s ease-in-out infinite}
@keyframes breathe{50%{filter:brightness(1.06)}}
.wave{display:flex;align-items:center;gap:2.5px;height:20px;width:34px;justify-content:center;flex:0 0 auto}
.wave i{display:block;width:3px;height:5px;border-radius:99px;background:rgba(255,255,255,.85);transition:height .12s}
.voice.rec .wave i{animation:bar .7s ease-in-out infinite}
.voice.rec .wave i:nth-child(2){animation-delay:.1s}
.voice.rec .wave i:nth-child(3){animation-delay:.2s}
.voice.rec .wave i:nth-child(4){animation-delay:.1s}
.voice.rec .wave i:nth-child(5){animation-delay:.05s}
@keyframes bar{0%,100%{height:5px}50%{height:19px}}
.duration{font-size:11px;font-weight:800;opacity:.75;font-variant-numeric:tabular-nums;min-width:28px;text-align:right}
.hint{font-size:10.5px;line-height:1.4;color:#8c9588;text-align:center;min-height:15px;padding:0 6px}
.sheet{position:fixed;inset:0;background:rgba(20,28,16,.38);display:flex;align-items:flex-end;justify-content:center;padding:14px;z-index:20;backdrop-filter:blur(3px)}
.sheet[hidden]{display:none}
.sheet-card{width:100%;max-width:430px;background:#fff;border-radius:24px;padding:20px 20px calc(18px + var(--safe-bottom));box-shadow:0 20px 50px rgba(0,0,0,.2)}
.sheet-card h2{font-size:18px;margin:0 0 10px;font-weight:900}
.sheet-card p{font-size:12px;line-height:1.65;color:#667060;margin:0 0 9px}
.sheet-card code{background:#f1f4ee;border-radius:5px;padding:1px 4px;font-size:11px}
.sheet-close{margin-top:6px;width:100%;height:46px;border-radius:14px;background:var(--green);color:#fff;font-weight:900;font-size:15px;box-shadow:0 3px 0 var(--green-dark)}
@media (max-height:720px){
  .app{gap:6px;padding-top:calc(4px + var(--safe-top));padding-bottom:calc(4px + var(--safe-bottom))}
  .top{min-height:36px}
  .brand{font-size:17px}.logo{width:29px;height:29px;border-radius:10px;font-size:14px}
  .modes{padding:3px}.mode{padding:7px 4px;font-size:11.5px}
  .remote{padding:8px 12px 9px;gap:5px;border-radius:22px}
  .remote-head{min-height:34px}
  .remote-label{font-size:8px}
  .key{width:44px;height:44px;font-size:17px;border-width:1.5px}
  .key.small{width:40px;height:40px;font-size:15px}
  .icon{width:21px;height:21px}
  .icon.lg{width:24px;height:24px}
  .dpad{width:166px;height:166px;margin:1px auto 0;border-width:1.5px}
  .dpad .key{width:52px;height:52px}
  .dpad .up{top:4px}.dpad .down{bottom:4px}.dpad .left{left:4px}.dpad .right{right:4px}
  .dpad .ok{width:54px;height:54px;font-size:12px}
  .controls .key{width:42px;height:42px}
  .nav{gap:7px}
  .volume{border-radius:23px;padding:2px}
  .volume .key{width:38px;height:38px;font-size:18px}
  .volume .line{width:17px}
  .tv{height:38px;border-radius:19px;font-size:12px;border-width:1.5px}
  .log{min-height:50px;padding:7px 11px;border-radius:15px}
  .log-text{font-size:13px;min-height:17px}
  .voice{min-height:56px;border-radius:18px;font-size:16px;box-shadow:0 4px 0 var(--green-dark)}
  .hint{font-size:9.5px}
}
</style>
</head>
<body>
<svg width="0" height="0" style="position:absolute;overflow:hidden" aria-hidden="true">
  <defs>
    <symbol id="i-power" viewBox="0 0 24 24"><path d="M12 3v9"/><path d="M6.7 6.7a8 8 0 1 0 10.6 0"/></symbol>
    <symbol id="i-mic" viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M8.5 21h7"/></symbol>
    <symbol id="i-up" viewBox="0 0 24 24"><path d="M6 15l6-6 6 6"/></symbol>
    <symbol id="i-down" viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></symbol>
    <symbol id="i-left" viewBox="0 0 24 24"><path d="M15 6l-6 6 6 6"/></symbol>
    <symbol id="i-right" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></symbol>
    <symbol id="i-back" viewBox="0 0 24 24"><path d="M9 14L4 9l5-5"/><path d="M4 9h9a7 7 0 0 1 0 14h-1"/></symbol>
    <symbol id="i-home" viewBox="0 0 24 24"><path d="M4 11l8-7 8 7v9a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z"/><path d="M9.5 21v-6h5v6"/></symbol>
    <symbol id="i-menu" viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h16"/></symbol>
    <symbol id="i-tv" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4"/></symbol>
    <symbol id="i-plus" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></symbol>
    <symbol id="i-minus" viewBox="0 0 24 24"><path d="M5 12h14"/></symbol>
  </defs>
</svg>
<div class="app">
  <header class="top">
    <div class="brand"><div class="logo">▶</div><span>MyRemote</span></div>
    <div class="top-right">
      <div class="status"><span class="dot" id="dot"></span><span id="conn">连接中…</span></div>
      <button class="help" id="help" aria-label="帮助">?</button>
    </div>
  </header>

  <div class="modes" role="tablist" aria-label="语音模式">
    <button class="mode" data-mode="forward" role="tab">音频输入</button>
    <button class="mode" data-mode="command" role="tab">命令</button>
    <button class="mode" data-mode="input" role="tab">文字输入</button>
  </div>

  <main class="stage">
    <div class="remote">
      <div class="remote-head">
        <button class="key small" data-key="power" aria-label="电源"><svg class="icon" aria-hidden="true"><use href="#i-power"/></svg></button>
        <div class="remote-label">XIAOMI REMOTE 2 PRO</div>
        <button class="key mic" id="voiceTop" aria-label="按住说话"><svg class="icon" aria-hidden="true"><use href="#i-mic"/></svg></button>
      </div>

      <div class="dpad">
        <button class="key up" data-key="up" aria-label="上"><svg class="icon" aria-hidden="true"><use href="#i-up"/></svg></button>
        <button class="key left" data-key="left" aria-label="左"><svg class="icon" aria-hidden="true"><use href="#i-left"/></svg></button>
        <button class="key ok" data-key="ok" aria-label="OK">OK</button>
        <button class="key right" data-key="right" aria-label="右"><svg class="icon" aria-hidden="true"><use href="#i-right"/></svg></button>
        <button class="key down" data-key="down" aria-label="下"><svg class="icon" aria-hidden="true"><use href="#i-down"/></svg></button>
      </div>

      <div class="controls">
        <div class="nav">
          <button class="key ghost" data-key="back" aria-label="返回"><svg class="icon" aria-hidden="true"><use href="#i-back"/></svg></button>
          <button class="key ghost" data-key="home" aria-label="主页"><svg class="icon" aria-hidden="true"><use href="#i-home"/></svg></button>
          <button class="key ghost" data-key="menu" aria-label="菜单"><svg class="icon" aria-hidden="true"><use href="#i-menu"/></svg></button>
        </div>
        <div class="volume" aria-label="音量">
          <button class="key" data-key="volUp" aria-label="音量加"><svg class="icon sm" aria-hidden="true"><use href="#i-plus"/></svg></button>
          <span class="line"></span>
          <button class="key" data-key="volDown" aria-label="音量减"><svg class="icon sm" aria-hidden="true"><use href="#i-minus"/></svg></button>
        </div>
      </div>

      <button class="tv" data-key="tv" aria-label="TV"><svg class="icon sm" aria-hidden="true"><use href="#i-tv"/></svg><span>TV</span></button>
    </div>
  </main>

  <section class="log">
    <div class="log-head"><span>识别文字</span><span id="stateText">等待输入</span></div>
    <div class="log-text empty" id="transcript">按住底部语音键说话…</div>
  </section>

  <footer class="dock">
    <button class="voice" id="voice" aria-label="按住说话">
      <span class="wave" id="wave"><i></i><i></i><i></i><i></i><i></i></span>
      <span id="voiceLabel">按住说话</span>
      <span class="duration" id="duration"></span>
    </button>
    <div class="hint" id="hint">命令 / 文字输入模式：松手后识别；音频输入模式：直接转发到 Mac。</div>
  </footer>
</div>

<div class="sheet" id="helpSheet" hidden>
  <div class="sheet-card">
    <h2>首次使用</h2>
    <p>1. Mac 设置 →「Web 遥控器」→ 打开开关。</p>
    <p>2. 点「打开 CA 文件夹」，把 <code>ca.crt</code> AirDrop 到手机。</p>
    <p>3. iPhone：设置 → 已下载描述文件 → 安装；再到 通用 → 关于本机 → 证书信任设置，对 <code>MyRemote Local CA</code> 开启完全信任。</p>
    <p>4. 用相机扫描 Mac 上的二维码，Safari 打开本页，允许麦克风。</p>
    <p>页面必须通过 HTTPS 打开；HTTP 下浏览器不会给麦克风权限。若无法连接，检查手机与 Mac 是否在同一 Wi-Fi，并允许 macOS 的本地网络 / 防火墙。</p>
    <button class="sheet-close" id="closeHelp">知道了</button>
  </div>
</div>

<script>
(() => {
  const params = new URLSearchParams(location.search);
  const token = params.get("token") || "";
  const wsURL = `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws?token=${encodeURIComponent(token)}`;
  const dot = document.getElementById("dot");
  const conn = document.getElementById("conn");
  const transcript = document.getElementById("transcript");
  const hint = document.getElementById("hint");
  const stateText = document.getElementById("stateText");
  const voiceBtn = document.getElementById("voice");
  const voiceTop = document.getElementById("voiceTop");
  const voiceLabel = document.getElementById("voiceLabel");
  const durationEl = document.getElementById("duration");
  const modeButtons = [...document.querySelectorAll(".mode")];
  const helpSheet = document.getElementById("helpSheet");

  let ws = null;
  let selectedMode = "forward";
  let recording = false;
  let stream = null;
  let audioCtx = null;
  let processor = null;
  let sourceNode = null;
  let mute = null;
  let pending = new Float32Array(0);
  let phase = 0;
  let timer = null;
  let startedAt = 0;
  let holdActive = false;

  // 长按语音键时，浏览器默认会选中文字/弹出复制菜单；整页禁用选择和系统菜单。
  ["contextmenu", "selectstart", "dragstart"].forEach(name => {
    document.addEventListener(name, event => event.preventDefault(), { capture: true });
  });

  function setStatus(text, on) {
    conn.textContent = text;
    dot.classList.toggle("on", !!on);
  }

  function setMode(mode, notify = true) {
    if (!["forward", "command", "input"].includes(mode)) return;
    selectedMode = mode;
    modeButtons.forEach(button => {
      const selected = button.dataset.mode === mode;
      button.classList.toggle("sel", selected);
      button.setAttribute("aria-selected", selected ? "true" : "false");
    });
    if (notify) send({ type: "mode", mode });
  }

  function connect() {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
      return Promise.resolve();
    }
    return new Promise((resolve, reject) => {
      setStatus("连接中…", false);
      const socket = new WebSocket(wsURL);
      socket.binaryType = "arraybuffer";
      ws = socket;
      socket.onopen = () => { setStatus("已连接", true); resolve(); };
      socket.onerror = () => { setStatus("无法连接", false); reject(new Error("WebSocket error")); };
      socket.onclose = () => {
        setStatus("已断开", false);
        ws = null;
        stopVoice(false);
        setTimeout(() => { if (!ws) connect().catch(() => {}); }, 1500);
      };
      socket.onmessage = event => {
        let msg;
        try { msg = JSON.parse(event.data); } catch { return; }
        if (msg.type === "state") setMode(msg.mode || "forward", false);
        if (msg.type === "voice_started") {
          hint.textContent = "正在录音，松手结束…";
          stateText.textContent = "录音中";
        }
        if (msg.type === "transcript") {
          transcript.textContent = msg.text || "（空）";
          transcript.classList.toggle("empty", !msg.text);
          stateText.textContent = msg.text ? "已识别" : "未识别";
          if (!recording) hint.textContent = "命令 / 文字输入模式：松手后识别；音频输入模式：直接转发到 Mac。";
        }
        if (msg.type === "error") {
          stopVoice(false, false);
          hint.textContent = msg.message || "出错了";
          stateText.textContent = "出错";
        }
      };
    });
  }

  function send(obj) {
    if (!ws || ws.readyState !== WebSocket.OPEN) return false;
    ws.send(JSON.stringify(obj));
    return true;
  }

  async function pressKey(key) {
    if (navigator.vibrate) navigator.vibrate(8);
    try { await connect(); } catch { return; }
    send({ type: "key", key });
  }

  document.querySelectorAll("[data-key]").forEach(button => {
    button.addEventListener("pointerdown", event => {
      event.preventDefault();
      button.classList.add("pressed");
      pressKey(button.dataset.key);
    });
    ["pointerup", "pointercancel", "pointerleave"].forEach(name => {
      button.addEventListener(name, () => button.classList.remove("pressed"));
    });
  });

  modeButtons.forEach(button => {
    button.addEventListener("click", () => setMode(button.dataset.mode));
  });

  document.getElementById("help").addEventListener("click", () => { helpSheet.hidden = false; });
  document.getElementById("closeHelp").addEventListener("click", () => { helpSheet.hidden = true; });
  helpSheet.addEventListener("click", event => {
    if (event.target === helpSheet) helpSheet.hidden = true;
  });

  function downsample(input) {
    const merged = new Float32Array(pending.length + input.length);
    merged.set(pending);
    merged.set(input, pending.length);
    const out = [];
    while (phase + 1 < merged.length) {
      const index = Math.floor(phase);
      const frac = phase - index;
      const sample = merged[index] * (1 - frac) + merged[index + 1] * frac;
      out.push(Math.max(-1, Math.min(1, sample)));
      phase += audioCtx.sampleRate / 16000;
    }
    const consumed = Math.min(Math.floor(phase), merged.length);
    pending = merged.slice(consumed);
    phase -= consumed;
    if (!out.length) return null;
    const pcm = new Int16Array(out.length);
    for (let i = 0; i < out.length; i++) {
      pcm[i] = Math.max(-32768, Math.min(32767, Math.round(out[i] * 32767)));
    }
    return pcm;
  }

  function updateDuration() {
    const seconds = Math.max(0, Math.floor((Date.now() - startedAt) / 1000));
    durationEl.textContent = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
  }

  function startTimer() {
    startedAt = Date.now();
    updateDuration();
    timer = setInterval(updateDuration, 250);
  }

  function stopTimer() {
    if (timer) clearInterval(timer);
    timer = null;
    durationEl.textContent = "";
  }

  async function startVoice() {
    if (recording) return;
    if (!token) {
      hint.textContent = "缺少配对 token，请用 Mac 设置里的二维码重新打开。";
      return;
    }
    try {
      // 先 getUserMedia，保留 pointerdown 的用户手势；iOS Safari 对调用顺序很敏感。
      stream = await navigator.mediaDevices.getUserMedia({
        audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true }
      });
      await connect();
      if (!holdActive) {
        stream?.getTracks().forEach(track => track.stop());
        stream = null;
        return;
      }
      audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      await audioCtx.resume();
      sourceNode = audioCtx.createMediaStreamSource(stream);
      processor = audioCtx.createScriptProcessor(4096, 1, 1);
      mute = audioCtx.createGain();
      mute.gain.value = 0;
      processor.onaudioprocess = event => {
        if (!recording || !ws || ws.readyState !== WebSocket.OPEN) return;
        const pcm = downsample(event.inputBuffer.getChannelData(0));
        if (pcm && pcm.length) ws.send(pcm.buffer);
      };
      sourceNode.connect(processor);
      processor.connect(mute);
      mute.connect(audioCtx.destination);
      recording = true;
      voiceBtn.classList.add("rec");
      voiceLabel.textContent = "松手结束";
      stateText.textContent = "录音中";
      hint.textContent = "正在录音，松手结束…";
      startTimer();
      send({ type: "voice_start", mode: selectedMode });
      if (navigator.vibrate) navigator.vibrate(12);
    } catch (error) {
      stopVoice(true, false);
      hint.textContent = "麦克风不可用：" + (error.message || error.name) +
        "。请确认用 https 打开，并已在手机信任 CA。";
      stateText.textContent = "麦克风不可用";
    }
  }

  function stopVoice(notify = true, resetHint = true) {
    if (!recording && !stream && !audioCtx) return;
    recording = false;
    voiceBtn.classList.remove("rec");
    voiceLabel.textContent = "按住说话";
    stopTimer();
    if (notify) send({ type: "voice_stop" });
    try { processor?.disconnect(); } catch {}
    try { sourceNode?.disconnect(); } catch {}
    try { mute?.disconnect(); } catch {}
    stream?.getTracks().forEach(track => track.stop());
    if (audioCtx && audioCtx.state !== "closed") audioCtx.close().catch(() => {});
    processor = null; sourceNode = null; mute = null; stream = null; audioCtx = null;
    pending = new Float32Array(0);
    phase = 0;
    if (notify) {
      stateText.textContent = selectedMode === "forward" ? "已发送" : "识别中";
      hint.textContent = selectedMode === "forward"
        ? "已把手机麦克风转发到 Mac。"
        : "正在识别刚才的语音…";
    } else if (resetHint) {
      stateText.textContent = "等待输入";
      hint.textContent = "命令 / 文字输入模式：松手后识别；音频输入模式：直接转发到 Mac。";
    }
    if (resetHint && !notify) {
      hint.textContent = "命令 / 文字输入模式：松手后识别；音频输入模式：直接转发到 Mac。";
    }
  }

  [voiceBtn, voiceTop].forEach(button => {
    button.addEventListener("pointerdown", event => {
      event.preventDefault();
      event.stopPropagation();
      holdActive = true;
      try { button.setPointerCapture(event.pointerId); } catch {}
      startVoice();
    });
    ["pointerup", "pointercancel", "lostpointercapture"].forEach(name => {
      button.addEventListener(name, event => {
        event.preventDefault();
        holdActive = false;
        stopVoice(true);
      });
    });
    button.addEventListener("contextmenu", event => event.preventDefault());
  });

  setMode("forward", false);
  connect().catch(() => {});
  window.addEventListener("beforeunload", () => stopVoice(false));
})();
</script>
</body>
</html>
"""#
}
