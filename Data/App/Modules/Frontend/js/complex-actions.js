(function () {
  'use strict';
  const number = (v, digits = 3) => v == null || !Number.isFinite(Number(v)) ? '—' : Number(v).toFixed(digits);
  function focus(selection, start, end) {
    if (!selection) return null;
    if (start === '' && end === '') return { ...selection };
    if (start === '' || end === '' || !Number.isFinite(Number(start)) || !Number.isFinite(Number(end)) || Number(end) <= Number(start)) throw new Error('区域起点与终点需要同时填写，且终点大于起点。');
    return { ...selection, start_t: Number(start), end_t: Number(end) };
  }
  function create({ panel, post, loadTimeline, seek, speed }) {
    const el = name => panel.querySelector('[data-complex="' + name + '"]');
    let state = null, key = '', revision = 0, result = null;
    function node(tag, text) { const n = document.createElement(tag); if (text != null) n.textContent = String(text); return n; }
    function button(text, fn) { const b = node('button', text); b.className = 'btn'; b.onclick = fn; return b; }
    function clear(message) { result = null; el('rows').replaceChildren(); el('plot').replaceChildren(); el('evidence').textContent = ''; el('export').disabled = true; el('status').textContent = message; }
    function selection(side) { return focus(state?.[side], el(side === 'subject' ? 'a-start' : 'b-start').value, el(side === 'subject' ? 'a-end' : 'b-end').value); }
    function holdsText(holds) { return (holds || []).map(h => h.samples + '采样 · ' + number(h.duration_lower_s) + '～' + number(h.duration_upper_s) + 's').join('；') || '—'; }
    function speedText(v) { return v == null ? '—' : speed(v); }
    async function evidence(side, stage) {
      const request = revision;
      el('evidence').textContent = '加载完整输入证据…';
      try {
        const source = result[side], data = await loadTimeline(source);
        if (request !== revision) return;
        const selected = data.samples.filter(s => s.index >= stage.start_csv_index - 1 && s.index <= stage.end_csv_index + 1);
        const text = [side === 'subject' ? 'A' : 'B', source.file, '圈 ' + source.lap, '来源SHA ' + (source.source_sha256 || '未知'), 'CSV索引\t时间秒\t速度m/s\t60 61 62 63 64 65 66 67\t前进合并'];
        for (const s of selected) text.push([s.index, number(s.time_s, 6), number(s.speed), (s.raw_inputs || []).map(v => v == null ? '?' : v).join(' '), s.forward_related == null ? '?' : Number(s.forward_related)].join('\t'));
        el('evidence').textContent = text.join('\n'); el('evidence').parentElement.open = true;
      } catch (e) { if (request === revision) el('evidence').textContent = '证据加载失败：' + e.message; }
    }
    function drawPlot(sides) {
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); svg.setAttribute('viewBox', '0 0 900 180'); svg.setAttribute('role', 'img'); svg.setAttribute('aria-label', '按各自首个候选起点对齐的速度曲线，横轴是各自经过时间，不是共同空间');
      const tracks = sides.filter(Boolean).map((s, side) => {
        const stages = s.stages || [], start = stages.length ? Math.min(...stages.map(v => v.start_t)) : s.curve[0]?.t || 0;
        const end = stages.length ? Math.max(...stages.map(v => v.end_t)) + .5 : start;
        return { side, source: s, start, points: (s.curve || []).filter(v => v.t >= start && v.t <= end) };
      });
      const duration = Math.max(.01, ...tracks.flatMap(t => t.points.map(p => p.t - t.start))), max = Math.max(1, ...tracks.flatMap(t => t.points.filter(p => p.pose_valid && p.speed != null).map(p => p.speed)));
      function shape(tag, attrs) { const n = document.createElementNS(svg.namespaceURI, tag); for (const [k,v] of Object.entries(attrs)) n.setAttribute(k, String(v)); svg.appendChild(n); return n; }
      shape('line', { x1:35,y1:145,x2:890,y2:145,stroke:'#8d9aa9' });
      tracks.forEach(t => {
        let path = '', connected = false;
        for (const p of t.points) {
          if (!p.pose_valid || p.speed == null) { connected = false; continue; }
          if (p.break_before) connected = false;
          path += (connected ? ' L' : ' M') + (35 + 850 * (p.t - t.start) / duration) + ',' + (145 - 125 * p.speed / max); connected = true;
        }
        shape('path', { d:path, fill:'none',stroke:t.side ? '#ea8c2b' : '#2563eb','stroke-width':2 });
        for (const s of t.source.stages || []) { const x = 35 + 850 * (s.start_t - t.start) / duration; shape('line', {x1:x,y1:15,x2:x,y2:145,stroke:t.side ? '#ea8c2b' : '#2563eb','stroke-dasharray':'3 3'}); const label = shape('text',{x:x+3,y:t.side ? 35 : 20,'font-size':10}); label.textContent = (t.side ? 'B' : 'A') + s.id; }
      });
      const caption = shape('text',{x:35,y:172,'font-size':11,fill:'#566477'}); caption.textContent = '各自首个候选起点归零 · 经过时间 0～' + number(duration,2) + 's · 速度 0～' + speedText(max) + ' · 虚线为候选起点';
      el('plot').replaceChildren(svg);
    }
    function render(data) {
      result = data; el('rows').replaceChildren(); el('export').disabled = false;
      const a = data.subject, cmp = data.comparison, matches = cmp?.matches || [];
      el('status').textContent = 'A ' + a.stages.length + '个候选 / ' + a.chain_count + '条候选链；' + (data.baseline ? 'B ' + data.baseline.stages.length + '个；唯一配对 ' + matches.length + '个。' : '当前未选 B。') + (a.requires_reanalysis || data.baseline?.requires_reanalysis ? '旧数据缺67，需要重新分析。' : '') + ' 普通漂移也可能命中，请核对候选类型。' + (cmp && !cmp.identity.comparable ? '地图身份不兼容。' : '');
      for (const s of a.stages) {
        const m = matches.find(v => v.a_stage_id === s.id), row = node('tr');
        const cells = [
          '链' + s.chain + ' / 第' + s.ordinal + '段 · #' + s.id + '\n' + (s.kind === 'sustained_drift_candidate' ? '持续漂移候选' : '卡气输入候选') + (s.complete ? '' : '\n边界或输入不完整'),
          number(s.start_t) + '～' + number(s.end_t) + 's\n入 ' + speedText(s.speed.entry) + ' / 末 ' + speedText(s.speed.end) + '\n峰 ' + speedText(s.speed.peak) + ' / 低 ' + speedText(s.speed.minimum) + ' / 均 ' + speedText(s.speed.time_weighted_mean),
          '松前 ' + s.forward_released_samples + '采样\n漂移 ' + holdsText(s.drift_pulses) + '\n松前→漂移 ' + number(s.release_to_drift_s) + 's\n回前衔接 ' + number(s.bridge?.duration_s) + 's · ' + holdsText(s.bridge?.forward_holds),
          m ? '#' + m.b_stage_id + ' · ' + number(m.b.start_t) + '～' + number(m.b.end_t) + 's\n峰 ' + speedText(m.b.speed.peak) + ' / 低 ' + speedText(m.b.speed.minimum) + '\n自然持续差 ' + number(m.natural_duration_delta_s) + 's' : '未唯一匹配',
          m ? number(m.common_time_delta_s) + 's\nA ' + number(m.common_a_duration_s) + ' / B ' + number(m.common_b_duration_s) + 's' : '—',
          m ? number(m.onset_equivalent_offset_s) + 's\n正值=相对参考较晚\n分辨率估计 ' + number(m.onset_resolution_estimate_s) + 's' : '—'
        ];
        for (const text of cells) row.appendChild(node('td', text));
        const links = node('td'); links.appendChild(button('定位 A', () => seek(s.start_t))); links.appendChild(button('A 输入证据', () => evidence('subject', s))); if (m) links.appendChild(button('B 输入证据', () => evidence('baseline', m.b)));
        const detail = node('details'), summary = node('summary','角度与原生状态'), content = node('div','完整夹角 ' + number(s.angle_start_deg,1) + '°→' + number(s.angle_end_deg,1) + '°（位移方向估算）\n原生漂移末 ' + number(s.native_drift_end_t) + 's\n地图推进激活 ' + (s.map_propulsion_samples == null ? '未知' : s.map_propulsion_samples + '采样')); detail.append(summary, content); links.appendChild(detail); row.appendChild(links); el('rows').appendChild(row);
      }
      drawPlot([a, data.baseline]);
    }
    el('run').onclick = async () => {
      const request = ++revision;
      try {
        const subject = selection('subject'); if (!subject) throw new Error('请先选择 A 录像与圈次。');
        el('run').disabled = true; clear('正在读取完整采样并量化…');
        const data = await post('/api/complex-action-comparison', {subject, baseline:selection('baseline')});
        if (request !== revision) return;
        if (!data?.ok) throw new Error(data?.error || '量化失败'); render(data);
      } catch (e) { if (request === revision) clear('量化失败：' + e.message); }
      finally { if (request === revision) el('run').disabled = false; }
    };
    el('export').onclick = () => {
      if (!result) return;
      const url = URL.createObjectURL(new Blob([JSON.stringify(result,null,2)],{type:'application/json'})), a = node('a'); a.href=url;a.download='complex-action-measurements.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
    };
    return { sync(next) { const nextKey = JSON.stringify(next); if (nextKey === key) return; key=nextKey;state=next;revision++;el('run').disabled=false;for(const name of ['a-start','a-end','b-start','b-end'])el(name).value='';clear('选择已改变，请重新量化。'); }, reset() { key='';state=null;revision++;el('run').disabled=false;clear('尚未量化。'); } };
  }
  const api = { focus, number, create };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.ReplayComplexActions = api;
})();
