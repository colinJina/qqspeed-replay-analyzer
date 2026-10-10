(function () {
  "use strict";
  const binary = (v) => (v === 1 ? true : v === 0 ? false : null);
  function forward(a, b) {
    const x = binary(a),
      y = binary(b);
    return x === true || y === true
      ? true
      : x === false && y === false
        ? false
        : null;
  }
  // Choose the last saved state at/before t, never a future nearest sample.
  function sampleAt(samples, t) {
    let lo = 0,
      hi = samples.length;
    while (lo < hi) {
      const m = (lo + hi) >> 1;
      if (samples[m].time_s <= t) lo = m + 1;
      else hi = m;
    }
    return lo - 1;
  }
  function create({ panel, load, onSample, formatSpeed }) {
    const el = (name) => panel.querySelector('[data-timeline="' + name + '"]');
    let key = "",
      revision = 0,
      data = null,
      index = 0,
      frame = 0,
      playing = false;
    let originTime = 0,
      originWall = 0,
      rate = 1;
    const raf = (fn) => window.requestAnimationFrame(fn);
    function pause() {
      playing = false;
      if (frame) window.cancelAnimationFrame(frame);
      frame = 0;
      el("play").textContent = "播放";
    }
    function controls(disabled) {
      for (const name of ["previous", "next", "range", "rate"])
        el(name).disabled = disabled;
      el("play").disabled = disabled || !data?.nondecreasing_time;
    }
    function show(i) {
      if (!data?.samples?.length) return;
      index = Math.max(0, Math.min(data.samples.length - 1, i));
      const row = data.samples[index],
        raw = row.raw_inputs || [];
      el("range").value = String(index);
      el("time").textContent = (row.time_s * 1000).toFixed(0) + " ms";
      el("index").textContent =
        "采样 " +
        (index + 1) +
        "/" +
        data.samples.length +
        " · CSV索引 " +
        row.index;
      el("speed").textContent =
        row.speed == null ? "—" : formatSpeed(row.speed);
      el("position").textContent = [row.x, row.y, row.z]
        .map((n) => Number(n).toFixed(3))
        .join(", ");
      el("delta").textContent =
        row.delta_ms == null ? "—" : Number(row.delta_ms).toFixed(3) + " ms";
      el("source").textContent =
        data.source_csv + " · " + (row.source_stream || "—");
      const states = [
        binary(raw[0]),
        binary(raw[1]),
        forward(raw[2], raw[7]),
        binary(raw[3]),
        binary(raw[4]),
        binary(raw[5]),
      ];
      for (const [n, chip] of Array.from(
        panel.querySelectorAll("[data-input]"),
      ).entries()) {
        const value = states[n];
        chip.classList.toggle("active", value === true);
        chip.classList.toggle("unknown", value == null);
        chip.setAttribute(
          "aria-label",
          chip.dataset.input +
            (value == null ? "：未知" : value ? "：激活" : "：未激活"),
        );
      }
      el("raw").textContent = Array.from(
        { length: 8 },
        (_, k) => 60 + k + "=" + (raw[k] == null ? "?" : raw[k]),
      ).join("  ");
      onSample(row);
    }
    function tick(now) {
      if (!playing || !data?.samples?.length) return;
      const samples = data.samples,
        t = originTime + ((now - originWall) / 1000) * rate;
      const next = sampleAt(samples, t);
      if (next >= 0 && next !== index) show(next);
      if (t >= samples[samples.length - 1].time_s) {
        show(samples.length - 1);
        pause();
        return;
      }
      frame = raf(tick);
    }
    function start() {
      if (!data?.samples?.length || !data.nondecreasing_time) return;
      if (index === data.samples.length - 1) show(0);
      playing = true;
      originTime = data.samples[index].time_s;
      originWall = window.performance.now();
      el("play").textContent = "暂停";
      frame = raf(tick);
    }
    el("play").onclick = () => (playing ? pause() : start());
    el("previous").onclick = () => {
      pause();
      show(index - 1);
    };
    el("next").onclick = () => {
      pause();
      show(index + 1);
    };
    el("range").oninput = () => {
      pause();
      show(Number(el("range").value));
    };
    el("rate").onchange = () => {
      const resume = playing;
      pause();
      rate = Number(el("rate").value);
      if (resume) start();
    };
    function clear(message = "选择录像和圈次后加载完整采样。") {
      pause();
      data = null;
      index = 0;
      controls(true);
      el("status").textContent = message;
      for (const name of [
        "time",
        "index",
        "speed",
        "position",
        "delta",
        "source",
        "raw",
      ])
        el(name).textContent = "—";
      for (const chip of panel.querySelectorAll("[data-input]")) {
        chip.classList.remove("active");
        chip.classList.add("unknown");
      }
      el("range").value = "0";
      el("range").max = "0";
      onSample(null);
    }
    async function sync(selection) {
      const nextKey = [
        selection.file,
        selection.stream,
        selection.lap,
        selection.revision,
      ].join("|");
      if (key === nextKey) return;
      key = nextKey;
      const request = ++revision;
      clear("正在加载完整输入采样…");
      if (!selection.file || !selection.stream || !selection.lap) {
        clear();
        return;
      }
      try {
        const result = await load(selection);
        if (request !== revision) return;
        if (!result || result.contract !== "replay_input_timeline_v1")
          throw new Error("输入时间线契约不匹配");
        data = result;
        if (!data.samples?.length) {
          clear("当前圈没有可读取的完整采样。");
          return;
        }
        el("range").max = String(data.samples.length - 1);
        controls(false);
        el("status").textContent = data.requires_reanalysis
          ? "旧数据缺少67，请在设置中重新分析录像；缺失状态保持未知。"
          : !data.nondecreasing_time
            ? "存在时间倒退，仅支持逐采样查看。"
            : "完整采样 · 候选指法语义 · 同时间记录可逐条查看；播放显示该时间最后一条状态。";
        show(0);
      } catch (error) {
        if (request === revision) clear("加载失败：" + error.message);
      }
    }
    controls(true);
    return {
      sync,
      pause,
      reset() {
        key = "";
        revision++;
        clear();
      },
    };
  }
  const api = { binary, forward, sampleAt, create };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.ReplayInputTimeline = api;
})();
