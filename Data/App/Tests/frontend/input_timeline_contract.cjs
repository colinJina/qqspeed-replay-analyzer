const assert = require("node:assert/strict");
const path = require("node:path");
const timeline = require(
  path.join(__dirname, "../../Modules/Frontend/js/input-timeline.js"),
);
class Element {
  constructor(label = "") {
    this.dataset = { input: label };
    this.textContent = "";
    this.disabled = false;
    this.value = "1";
    this.classes = new Set();
    this.classList = {
      add: (n) => this.classes.add(n),
      remove: (n) => this.classes.delete(n),
      toggle: (n, v) => (v ? this.classes.add(n) : this.classes.delete(n)),
    };
  }
  setAttribute() {}
}
function panel() {
  const names = [
    "play",
    "previous",
    "next",
    "range",
    "rate",
    "status",
    "time",
    "index",
    "speed",
    "position",
    "delta",
    "source",
    "raw",
  ];
  const els = Object.fromEntries(names.map((n) => [n, new Element()])),
    chips = Array.from({ length: 6 }, (_, i) => new Element("candidate" + i));
  return {
    els,
    chips,
    querySelector: (s) => els[s.match(/"(.*?)"/)[1]],
    querySelectorAll: () => chips,
  };
}
function sample(index, t, a, b, x = index) {
  return {
    index,
    time_s: t,
    delta_ms: index ? 17 : null,
    x,
    y: 0,
    z: 0,
    speed: 12,
    raw_inputs: [0, 0, a, 0, 0, 0, 0, b],
    pose_valid: true,
    source_stream: "s1",
  };
}
const samples = [
  sample(0, 0, 0, 1),
  sample(1, 0.017, 0, 0),
  sample(2, 0.017, 1, 0),
  sample(3, 0.034, 0, null),
];
const data = {
  contract: "replay_input_timeline_v1",
  samples,
  nondecreasing_time: true,
  source_csv: "logical_01.csv",
};
let clock = 0,
  id = 0;
const callbacks = new Map();
global.window = {
  performance: { now: () => clock },
  requestAnimationFrame: (fn) => {
    callbacks.set(++id, fn);
    return id;
  },
  cancelAnimationFrame: (n) => callbacks.delete(n),
};
function tick(now) {
  clock = now;
  const queued = [...callbacks.values()];
  callbacks.clear();
  for (const fn of queued) fn(now);
}
(async () => {
  assert.equal(timeline.forward(0, 1), true);
  assert.equal(timeline.forward(1, 0), true);
  assert.equal(timeline.forward(1, 1), true);
  assert.equal(timeline.forward(0, 0), false);
  assert.equal(timeline.forward(0, null), null);
  assert.equal(timeline.forward(2, 0), null);
  assert.equal(timeline.sampleAt(samples, 0.016), 0);
  assert.equal(timeline.sampleAt(samples, 0.017), 2);
  assert.equal(timeline.sampleAt(samples, -1), -1);
  const p = panel(),
    seen = [];
  const controller = timeline.create({
    panel: p,
    load: async () => data,
    onSample: (r) => seen.push(r),
    formatSpeed: String,
  });
  await controller.sync({ file: "a", stream: "s", lap: 1, revision: 1 });
  assert(p.chips[2].classes.has("active"), "67-only input must light forward");
  p.els.next.onclick();
  assert.equal(seen.at(-1).index, 1);
  assert(!p.chips[2].classes.has("active"));
  p.els.next.onclick();
  assert.equal(
    seen.at(-1).index,
    2,
    "equal-time second state must remain seekable",
  );
  p.els.next.onclick();
  assert(p.chips[2].classes.has("unknown"), "unknown must not look released");
  p.els.range.value = "0";
  p.els.range.oninput();
  p.els.play.onclick();
  tick(16);
  assert.equal(seen.at(-1).index, 0, "playback must not use a future sample");
  tick(17);
  assert.equal(seen.at(-1).index, 2);
  tick(34);
  assert.equal(seen.at(-1).index, 3);
  assert.equal(callbacks.size, 0);
  const pending = {},
    p2 = panel(),
    latest = [];
  const c2 = timeline.create({
    panel: p2,
    load: (s) => new Promise((resolve) => (pending[s.file] = resolve)),
    onSample: (r) => latest.push(r),
    formatSpeed: String,
  });
  const a = c2.sync({ file: "a", stream: "s", lap: 1 }),
    b = c2.sync({ file: "b", stream: "s", lap: 1 });
  pending.b({ ...data, samples: [sample(0, 0, 0, 1, 200)] });
  await b;
  pending.a({ ...data, samples: [sample(0, 0, 0, 1, 100)] });
  await a;
  assert.equal(latest.at(-1).x, 200, "stale response replaced a newer replay");
  c2.reset();
  assert(p2.els.play.disabled);
  assert.equal(latest.at(-1), null);
  console.log(
    "[OK] Input timeline frontend: OR/unknown, exact seek, duplicate states, no future samples, playback, stale requests.",
  );
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
