(function () {
  'use strict';
  const number = (v, digits = 3) => v == null || !Number.isFinite(Number(v)) ? '—' : Number(v).toFixed(digits);
  function focus(selection, start, end) {
    if (!selection) return null;
    if (start === '' && end === '') return { ...selection };
    if (start === '' || end === '' || !Number.isFinite(Number(start)) || !Number.isFinite(Number(end)) || Number(end) <= Number(start)) throw new Error('区域起点与终点需要同时填写，且终点大于起点。');
    return { ...selection, start_t: Number(start), end_t: Number(end) };
  }
  const reasonLabels = {
    input_and_stage_review_missing:'尚未核对输入与阶段',vehicle_configuration_not_confirmed:'车辆性能配置未确认',vehicle_configuration_note_missing:'缺少配置核对依据',strategy_not_reviewed:'策略未人工核对',no_comparable_reference:'没有可汇总参考',references_disagree_or_difference_below_resolution:'参考方向不一致，或差异低于分辨率估计',incomplete_input_boundaries:'输入边界不完整',spatial_alignment_too_uncertain:'空间对应不够稳定',entry_speed_differs_more_than_10_percent:'入段速度差超过10%',entry_heading_state_not_comparable:'入段角度状态不够相近',native_propulsion_evidence_missing:'原生推进效果证据未知',propulsion_context_differs:'起点推进状态不同',reference_has_no_observed_time_or_peak_advantage:'参考未呈现区间用时或峰速优势',duplicate_replay_stream_lap:'重复录像／流／圈',subject_cannot_reference_itself:'与 A 为同一录像／流／圈',map_identity_conflict_or_unknown:'地图身份冲突或未知',different_candidate_strategy_or_missing_stage:'候选策略或段数不同',incomplete_or_ambiguous_stage_correspondence:'阶段未完整唯一匹配',reference_load_failed:'参考加载失败'
  };
  function create({ panel, post, loadTimeline, loadMetadata, seek, speed }) {
    const el = name => panel.querySelector('[data-complex="' + name + '"]');
    let state = null, key = '', revision = 0, result = null;
    let references = [], batchResult = null;
    function node(tag, text) { const n = document.createElement(tag); if (text != null) n.textContent = String(text); return n; }
    function button(text, fn) { const b = node('button', text); b.className = 'btn'; b.onclick = fn; return b; }
    function clear(message) { result = null; batchResult=null;el('guidance').textContent='尚未分析参考组。'; el('rows').replaceChildren(); el('plot').replaceChildren(); el('evidence').textContent = ''; el('export').disabled = true; el('status').textContent = message; }
    function applyAvailability() {
      const disabled=state?.scope?.allowed!==true;
      for(const field of ['run','run-references','add-reference','add-baseline','reference-choice','a-start','a-end','b-start','b-end'])el(field).disabled=disabled;
    }
    function selection(side) {
      if(!state?.[side])return null;
      if(state?.scope?.allowed!==true)throw new Error(state?.scope?.message || '卡气分析仅开放已确认地图身份的月牙湾。');
      const selected=focus(state[side],el(side==='subject'?'a-start':'b-start').value,el(side==='subject'?'a-end':'b-end').value);
      if(selected.start_t==null || selected.end_t==null || selected.start_t<0)throw new Error('请填写 '+(side==='subject'?'A':'B')+' 开头卡气练习区域的起止时间。');
      return selected;
    }
    function holdsText(holds) { return (holds || []).map(h => h.samples + '采样 · ' + number(h.duration_lower_s) + '～' + number(h.duration_upper_s) + 's').join('；') || '—'; }
    function speedText(v) { return v == null ? '—' : speed(v); }
    function clearGuidance() { batchResult=null;el('export').disabled=!result;el('guidance').textContent='参考条件已改变，请重新分析参考组。'; }
    function invalidateGuidance() {revision++;applyAvailability();clearGuidance();}
    function option(select,value,text) { const o=node('option',text);o.value=String(value);select.appendChild(o); }
    function renderReferenceChoices() {
      el('reference-choice').replaceChildren();
      for(const choice of state?.choices || []) option(el('reference-choice'),choice.file,choice.label);
    }
    function renderReferences() {
      el('references').replaceChildren();
      for(const ref of references) {
        const row=node('div');row.className='complexReferenceRow';row.appendChild(node('span',ref.label));
        const streams=node('select'), laps=node('select');streams.setAttribute('aria-label','参考记录流');laps.setAttribute('aria-label','参考圈次');
        option(streams,'','请选择记录流');for(const s of ref.metadata.streams || [])option(streams,s.id,s.id+' · '+s.role);
        streams.value=ref.stream || '';
        function fillLaps() { laps.replaceChildren();const s=ref.metadata.streams.find(s=>s.id===streams.value);for(const lap of s?.laps || [])option(laps,lap.lap,'圈'+lap.lap);const available=(s?.laps || []).some(l=>Number(l.lap)===Number(ref.lap));laps.value=String(available?ref.lap:laps.children[0]?.value || '');ref.lap=Number(laps.value); }
        streams.onchange=()=>{ref.stream=streams.value;ref.lap=null;fillLaps();invalidateGuidance();};fillLaps();laps.onchange=()=>{ref.lap=Number(laps.value);invalidateGuidance();};row.append(streams,laps);
        for(const [field,label] of [['start','起点秒'],['end','终点秒']]){const input=node('input');input.type='number';input.step='.01';input.min='0';input.placeholder=label;input.setAttribute('aria-label','参考'+label);input.value=ref[field] || '';input.onchange=()=>{ref[field]=input.value;invalidateGuidance();};row.appendChild(input);}
        row.appendChild(button('移除',()=>{references=references.filter(r=>r!==ref);renderReferences();invalidateGuidance();}));el('references').appendChild(row);
      }
    }
    async function addReference(initial) {
      if(references.length>=8){el('guidance').textContent='一次最多8份参考，请先移除一份。';return;}
      const file=initial?.file || el('reference-choice').value;if(!file){el('guidance').textContent='先选择参考录像。';return;}
      const request=revision;
      try {
        const metadata=await loadMetadata(file);if(request!==revision)return;
        const local=(metadata.streams || []).filter(s=>s.role==='local_high_frequency');
        const selected=initial?.stream || (local.length===1?local[0].id:metadata.streams?.length===1?metadata.streams[0].id:'');
        references.push({file,label:state?.choices?.find(c=>c.file===file)?.label || file,metadata,stream:selected,lap:initial?.lap || state?.subject?.lap,start:initial?.start_t == null?'':String(initial.start_t),end:initial?.end_t == null?'':String(initial.end_t)});
        renderReferences();invalidateGuidance();
      } catch(e) {if(request===revision)el('guidance').textContent='添加参考失败：'+e.message;}
    }
    el('add-reference').onclick=()=>addReference(null);
    el('add-baseline').onclick=()=>{try{const b=selection('baseline');if(!b)throw new Error('先在页面选择 B。');return addReference(b);}catch(e){el('guidance').textContent=e.message;}};
    for(const field of ['reviewed','same-car','car-note','same-strategy'])el(field).onchange=invalidateGuidance;
    for(const field of ['a-start','a-end','b-start','b-end'])el(field).onchange=()=>{invalidateGuidance();clear('区域已改变，请重新量化。');};
    function distribution(d,formatter=v=>number(v)) { return !d?.count?'—':formatter(d.median)+'（中位数；范围 '+formatter(d.min)+'～'+formatter(d.max)+'；n='+d.count+'）'; }
    function renderGuidance(data) {
      batchResult=data;el('export').disabled=false;el('guidance').replaceChildren();
      const g=data.guidance;
      el('guidance').appendChild(node('p','可汇总 '+g.accepted_reference_count+'份录像／圈，来自 '+g.distinct_sav_count+'份不同 SAV。确认项来自用户说明，未从 SAV 解码赛车配置。'));
      for(const chain of data.comparisons || []){for(const c of chain.comparison.chains || [])el('guidance').appendChild(node('p',chain.file+' · A链'+c.a_chain+' / B链'+c.b_chain+' · 含衔接的共同范围 A−B '+number(c.common_time_delta_s)+'s'+(c.covers_complete_a_chain&&c.covers_complete_b_chain?' · 两侧候选链完整覆盖':' · 仅匹配部分')));}
      for(const item of g.items || []) {
        const box=node('div');box.className='complexGuidanceItem';
        const action=item.status==='reference_relative_trial'?'可尝试'+(item.trial_shift_s<0?'提前':'延后')+'约 '+number(Math.abs(item.trial_shift_s),2)+'s，并以参考位置标记为准。改变后需用新 SAV 比较。':'当前保留观测，不给出秒数建议。';
        box.appendChild(node('b','A 阶段 #'+item.stage_id+' · '+action));
        box.appendChild(node('p','起卡等效偏移 '+distribution(item.onset_offset_s)+'s；共同区间时间差 '+distribution(item.common_time_delta_s)+'s。'));
        box.appendChild(node('p','参考峰速 '+distribution(item.reference_peak_speed,speedText)+'；最低速度 '+distribution(item.reference_min_speed,speedText)+'；回前衔接 '+distribution(item.reference_bridge_s)+'s；漂移停留 '+distribution(item.reference_drift_samples,v=>number(v,0))+'采样。'));
        if(item.unavailable_reasons?.length)box.appendChild(node('p',item.unavailable_reasons.map(v=>reasonLabels[v] || v).join('；')));
        for(const e of item.evidence || []) {
          const line=node('div',e.reference_file+' 圈'+e.reference_lap+' / #'+e.reference_stage_id+' · 偏移 '+number(e.onset_offset_s)+'s · 分辨率估计 '+number(e.resolution_estimate_s)+'s ');
          if(e.mapped_reference_on_a)line.appendChild(button('定位参考起点在 A 上的位置',()=>seek(e.mapped_reference_on_a.t)));
          line.appendChild(button('查看参考原始输入',()=>evidence('baseline',{start_csv_index:e.reference_start_csv_index,end_csv_index:e.reference_end_csv_index},e)));
          box.appendChild(line);
        };el('guidance').appendChild(box);
      }
      for(const r of g.rejected_references || [])el('guidance').appendChild(node('p','未汇总 '+r.file+'：'+(reasonLabels[r.reason] || r.reason)+(r.error?' · '+r.error:'')));
      el('guidance').appendChild(node('p','这是相对所选录像的试验建议，不保证收益，不输出成功分数、键程或RT毫米数。'));
    }
    el('run-references').onclick=async()=>{
      const request=++revision;
      try {
        const subject=selection('subject');if(!subject)throw new Error('先选择 A。');if(!references.length)throw new Error('至少添加一份参考。');
        const selections=references.map(r=>{if(!r.stream||!r.lap)throw new Error('每份参考都需要明确的流和圈次。');const selected=focus({file:r.file,stream:r.stream,lap:r.lap},r.start,r.end);if(selected.start_t==null||selected.end_t==null||selected.start_t<0)throw new Error('每份参考都需要填写开头卡气练习区域的起止时间。');return selected;});
        el('run-references').disabled=true;el('run').disabled=true;clearGuidance();
        // Yield between reference pairs: the loopback server remains available between requests.
        for(let i=0;i<selections.length;i++) {el('guidance').textContent='正在比较参考 '+(i+1)+'/'+selections.length+'…';try{await post('/api/complex-action-comparison',{subject,baseline:selections[i]});}catch(e){/* Batch records per-reference failures. */}if(request!==revision)return;}
        el('guidance').textContent='正在汇总分布与证据…';
        const declarations={inputs_and_stages_reviewed:!!el('reviewed').checked,same_vehicle_configuration:!!el('same-car').checked,vehicle_configuration_note:el('car-note').value,same_strategy_reviewed:!!el('same-strategy').checked};
        const data=await post('/api/complex-action-batch',{subject,references:selections,declarations});if(request!==revision)return;if(!data?.ok)throw new Error(data?.error || '参考汇总失败');renderGuidance(data);
      }catch(e){if(request===revision)el('guidance').textContent='参考分析失败：'+e.message;}
      finally{if(request===revision)applyAvailability();}
    };
    async function evidence(side, stage, reference=null) {
      const request = revision;
      el('evidence').textContent = '加载完整输入证据…';
      try {
        const source = reference ? {file:reference.reference_file,stream:reference.reference_stream,lap:reference.reference_lap,source_sha256:reference.reference_sha256}:result[side], data = await loadTimeline(source);
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
          '松前 ' + s.forward_released_samples + '采样 · '+number(s.forward_release_duration_lower_s)+'～'+number(s.forward_release_duration_upper_s)+'s\n漂移 ' + holdsText(s.drift_pulses) + '\n松前→漂移记录差 ' + number(s.release_to_drift_s) + 's\n先后范围 '+number(s.release_to_drift_lower_s)+'～'+number(s.release_to_drift_upper_s)+'s\n回前衔接 ' + number(s.bridge?.duration_s) + 's · ' + holdsText(s.bridge?.forward_holds),
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
      finally { if (request === revision) applyAvailability(); }
    };
    el('export').onclick = () => {
      if (!result && !batchResult) return;
      const url = URL.createObjectURL(new Blob([JSON.stringify(batchResult || result,null,2)],{type:'application/json'})), a = node('a'); a.href=url;a.download='complex-action-measurements.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
    };
    function resetReferences(){references=[];batchResult=null;el('run-references').disabled=false;for(const n of ['reviewed','same-car','same-strategy'])el(n).checked=false;el('car-note').value='';renderReferences();renderReferenceChoices();clearGuidance();}
    return { sync(next) { const nextKey = JSON.stringify(next); if (nextKey === key) return; key=nextKey;state=next;revision++;for(const name of ['a-start','a-end','b-start','b-end'])el(name).value='';clear(next?.scope?.allowed?'请填写开头卡气练习区域，再量化。':next?.scope?.message || '卡气分析仅开放已确认地图身份的月牙湾。');resetReferences();applyAvailability(); }, reset() { key='';state=null;revision++;clear('尚未量化。');resetReferences();applyAvailability(); } };
  }
  const api = { focus, number, create };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.ReplayComplexActions = api;
})();
