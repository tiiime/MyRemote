import Foundation

/// 手机端单页遥控器。页面通过 HTTPS 加载，麦克风走 getUserMedia + WebSocket PCM。
enum WebPage {
    static let html = #"""
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>MyRemote 遥控器</title>
<style>
:root{
  --green:#58cc02; --green-dark:#46a302; --ink:#3c3c3c; --muted:#777;
  --line:#e5e5e5; --paper:#fff; --bg:#f7f7f7; --blue:#1cb0f6; --yellow:#ffc800;
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{height:100%}
body{
  margin:0;background:linear-gradient(180deg,#eafbe0 0%,var(--bg) 38%,#f2f2f2 100%);
  color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Rounded","PingFang SC",sans-serif;
  display:flex;justify-content:center;padding:calc(10px + env(safe-area-inset-top)) 12px calc(14px + env(safe-area-inset-bottom));
}
.app{width:100%;max-width:430px;display:flex;flex-direction:column;gap:12px}
.top{display:flex;align-items:center;justify-content:space-between;padding:2px 4px}
.brand{display:flex;align-items:center;gap:9px;font-weight:900;font-size:19px;letter-spacing:-.3px}
.logo{width:34px;height:34px;border-radius:11px;background:var(--green);display:grid;place-items:center;color:#fff;font-size:18px;box-shadow:0 4px 0 var(--green-dark)}
.status{display:flex;align-items:center;gap:6px;font-size:12px;color:var(--muted);font-weight:700}
.dot{width:8px;height:8px;border-radius:50%;background:#c9c9c9}
.dot.on{background:var(--green);box-shadow:0 0 0 4px rgba(88,204,2,.14)}
.modes{display:grid;grid-template-columns:repeat(3,1fr);gap:7px}
.mode{border:2px solid var(--line);background:#fff;border-radius:14px;padding:9px 4px;font:800 12px/1.2 inherit;color:var(--muted)}
.mode.sel{border-color:var(--green);background:#efffe6;color:var(--green-dark)}
.remote{
  background:var(--paper);border:2px solid var(--line);border-radius:30px;padding:18px 18px 16px;
  box-shadow:0 10px 0 rgba(0,0,0,.04),0 18px 40px rgba(0,0,0,.08);display:flex;flex-direction:column;gap:14px;
}
.remote-top{display:flex;align-items:center;justify-content:space-between}
.pill{display:flex;align-items:center;gap:6px;font-size:11px;font-weight:800;color:#9a9a9a}
.key{
  appearance:none;border:0;background:#f1f1f1;color:var(--ink);border-radius:50%;
  width:56px;height:56px;display:grid;place-items:center;font:900 15px/1 inherit;
  box-shadow:0 4px 0 #dcdcdc;transition:transform .06s,box-shadow .06s;user-select:none;
}
.key:active,.key.pressed{transform:translateY(3px);box-shadow:0 1px 0 #dcdcdc}
.key.ghost{background:#fff;border:2px solid var(--line);box-shadow:0 4px 0 #ececec;font-size:13px}
.key.red{background:#ffdfe0;color:#e5484d;box-shadow:0 4px 0 #f3b9bb}
.key.green{background:var(--green);color:#fff;box-shadow:0 4px 0 var(--green-dark)}
.key.mic{background:#e8f7ff;color:#0796d9;box-shadow:0 4px 0 #b9e4f7}
.dpad{position:relative;width:214px;height:214px;margin:2px auto 0;border-radius:50%;background:#f7f7f7;border:2px solid #ededed}
.dpad .key{position:absolute;width:62px;height:62px}
.dpad .up{left:76px;top:4px}.dpad .down{left:76px;bottom:4px}
.dpad .left{left:4px;top:76px}.dpad .right{right:4px;top:76px}
.dpad .ok{left:76px;top:76px;width:62px;height:62px;background:#fff;border:2px solid var(--line);box-shadow:0 4px 0 #dcdcdc}
.mid{display:flex;justify-content:space-between;align-items:center;padding:0 3px}
.side{display:flex;gap:10px}
.side .key{width:48px;height:48px;font-size:13px}
.vol{display:flex;flex-direction:column;gap:7px;align-items:center}
.vol .key{width:46px;height:46px;font-size:18px}
.vol .label{font-size:10px;font-weight:800;color:#aaa}
.row{display:flex;gap:8px}
.row .key{width:auto;height:52px;border-radius:16px;flex:1;font-size:13px;padding:0 8px}
.voice{
  width:100%;border:0;border-radius:20px;background:var(--green);color:#fff;padding:16px;
  font:900 17px/1.1 inherit;box-shadow:0 6px 0 var(--green-dark);display:flex;align-items:center;justify-content:center;gap:9px;
  user-select:none;touch-action:none;
}
.voice.rec{background:#ff6b6b;box-shadow:0 6px 0 #d94f4f;animation:pulse 1.1s infinite}
@keyframes pulse{50%{filter:brightness(1.08)}}
.hint{font-size:11px;line-height:1.5;color:#999;text-align:center;padding:0 8px}
.log{background:#fff;border:2px solid var(--line);border-radius:18px;padding:12px 14px;min-height:68px}
.log-title{font-size:10px;font-weight:900;color:#aaa;letter-spacing:.06em;text-transform:uppercase}
.log-text{margin-top:6px;font-size:14px;font-weight:700;line-height:1.45;color:var(--ink);word-break:break-word}
.log-text.empty{color:#b5b5b5;font-weight:600}
details{font-size:11px;color:#888;line-height:1.5}
summary{cursor:pointer;font-weight:800;color:#777}
code{background:#f0f0f0;border-radius:5px;padding:1px 4px}
@media (max-height:720px){.dpad{width:190px;height:190px}.dpad .key{width:56px;height:56px}
.dpad .up{left:67px}.dpad .down{left:67px}.dpad .left{top:67px}.dpad .right{top:67px}
.dpad .ok{left:67px;top:67px;width:56px;height:56px}}
</style>
</head>
<body>
<div class="app">
  <div class="top">
    <div class="brand"><div class="logo">▶</div><span>MyRemote</span></div>
    <div class="status"><span class="dot" id="dot"></span><span id="conn">连接中…</span></div>
  </div>

  <div class="modes">
    <button class="mode" data-mode="forward">音频输入</button>
    <button class="mode" data-mode="command">命令</button>
    <button class="mode" data-mode="input">文字输入</button>
  </div>

  <div class="remote">
    <div class="remote-top">
      <button class="key ghost" data-key="power" aria-label="电源">⏻</button>
      <div class="pill">XIAOMI REMOTE 2 PRO</div>
      <button class="key mic" id="voiceTop" aria-label="语音键">🎙</button>
    </div>

    <div class="dpad">
      <button class="key up" data-key="up" aria-label="上">↑</button>
      <button class="key left" data-key="left" aria-label="左">←</button>
      <button class="key ok" data-key="ok" aria-label="OK">OK</button>
      <button class="key right" data-key="right" aria-label="右">→</button>
      <button class="key down" data-key="down" aria-label="下">↓</button>
    </div>

    <div class="mid">
      <div class="side">
        <button class="key ghost" data-key="back" aria-label="返回">↩</button>
        <button class="key ghost" data-key="home" aria-label="主页">⌂</button>
        <button class="key ghost" data-key="menu" aria-label="菜单">☰</button>
      </div>
      <div class="vol">
        <button class="key ghost" data-key="volUp" aria-label="音量加">+</button>
        <span class="label">VOL</span>
        <button class="key ghost" data-key="volDown" aria-label="音量减">−</button>
      </div>
    </div>

    <div class="row">
      <button class="key ghost" data-key="tv" aria-label="TV">TV</button>
    </div>

    <button class="voice" id="voice">🎙 <span id="voiceLabel">按住说话</span></button>
    <div class="hint" id="hint">命令/文字输入模式松手后识别；音频输入模式直接转发到 Mac 的 BlackHole。</div>
  </div>

  <div class="log">
    <div class="log-title">识别文字</div>
    <div class="log-text empty" id="transcript">等待语音输入…</div>
  </div>

  <details>
    <summary>首次使用 / 无法录音？</summary>
    <p>在 Mac 上打开「设置 → Web 遥控器」，导出 CA 证书并通过 AirDrop 发到手机；在 iPhone「设置」中安装描述文件，再到「通用 → 关于本机 → 证书信任设置」开启完全信任。然后刷新本页。</p>
    <p>本页必须通过 <code>https://</code> 打开，浏览器才允许使用麦克风。</p>
  </details>
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
  const voiceBtn = document.getElementById("voice");
  const voiceTop = document.getElementById("voiceTop");
  const voiceLabel = document.getElementById("voiceLabel");
  const modeButtons = [...document.querySelectorAll(".mode")];

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

  function setStatus(text, on) {
    conn.textContent = text;
    dot.classList.toggle("on", !!on);
  }

  function setMode(mode, notify = true) {
    if (!["forward", "command", "input"].includes(mode)) return;
    selectedMode = mode;
    modeButtons.forEach(b => b.classList.toggle("sel", b.dataset.mode === mode));
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
        setStatus("已断开，点按键重连", false);
        ws = null;
        stopVoice(false);
        setTimeout(() => { if (!ws) connect().catch(() => {}); }, 1500);
      };
      socket.onmessage = event => {
        let msg;
        try { msg = JSON.parse(event.data); } catch { return; }
        if (msg.type === "state") setMode(msg.mode || "forward", false);
        if (msg.type === "voice_started") hint.textContent = "正在录音，松手结束…";
        if (msg.type === "transcript") {
          transcript.textContent = msg.text || "（空）";
          transcript.classList.toggle("empty", !msg.text);
        }
        if (msg.type === "error") {
          stopVoice(false, false);
          hint.textContent = msg.message || "出错了";
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
    button.addEventListener("click", event => {
      event.preventDefault();
      pressKey(button.dataset.key);
    });
  });

  modeButtons.forEach(button => {
    button.addEventListener("click", () => setMode(button.dataset.mode));
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
      hint.textContent = "正在录音，松手结束…";
      send({ type: "voice_start", mode: selectedMode });
      if (navigator.vibrate) navigator.vibrate(12);
    } catch (error) {
      stopVoice(true, false);
      hint.textContent = "麦克风不可用：" + (error.message || error.name) +
        "。请确认用 https 打开，并已在手机信任 CA。";
    }
  }

  function stopVoice(notify = true, resetHint = true) {
    if (!recording && !stream && !audioCtx) return;
    recording = false;
    voiceBtn.classList.remove("rec");
    voiceLabel.textContent = "按住说话";
    if (notify) send({ type: "voice_stop" });
    try { processor?.disconnect(); } catch {}
    try { sourceNode?.disconnect(); } catch {}
    try { mute?.disconnect(); } catch {}
    stream?.getTracks().forEach(t => t.stop());
    if (audioCtx && audioCtx.state !== "closed") audioCtx.close().catch(() => {});
    processor = null; sourceNode = null; mute = null; stream = null; audioCtx = null;
    pending = new Float32Array(0);
    phase = 0;
    if (resetHint) {
      hint.textContent = "命令/文字输入模式松手后识别；音频输入模式直接转发到 Mac 的 BlackHole。";
    }
  }

  [voiceBtn, voiceTop].forEach(button => {
    button.addEventListener("pointerdown", event => {
      event.preventDefault();
      button.setPointerCapture(event.pointerId);
      startVoice();
    });
    ["pointerup", "pointercancel", "lostpointercapture"].forEach(name => {
      button.addEventListener(name, event => {
        event.preventDefault();
        stopVoice(true);
      });
    });
    button.addEventListener("contextmenu", event => event.preventDefault());
  });

  // 页面加载即尝试连接，失败时用户按任意键会重试。
  connect().catch(() => {});
  window.addEventListener("beforeunload", () => stopVoice(false));
})();
</script>
</body>
</html>
"""#
}
