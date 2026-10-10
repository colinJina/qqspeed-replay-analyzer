const assert=require('node:assert/strict');
const api=require('../../Modules/Frontend/js/complex-actions.js');
class Element {
  constructor(tag='div'){this.tag=tag;this.value='';this.textContent='';this.children=[];this.disabled=false;this.parentElement={open:false};this.namespaceURI='http://www.w3.org/2000/svg';}
  append(...nodes){this.children.push(...nodes);} appendChild(n){this.append(n);return n;} replaceChildren(...nodes){this.children=nodes;} setAttribute(){} click(){this.onclick?.();}
}
global.document={createElement:tag=>new Element(tag),createElementNS:(_,tag)=>new Element(tag)};
function panel(){const els=Object.fromEntries(['a-start','a-end','b-start','b-end','run','export','status','plot','rows','evidence','guidance','reference-choice','references','add-reference','add-baseline','reviewed','same-car','car-note','same-strategy','run-references'].map(n=>[n,new Element()]));return {els,querySelector:s=>els[s.match(/"(.*?)"/)[1]]};}
assert.throws(()=>api.focus({file:'a'},'0',''),/同时填写/);
assert.deepEqual(api.focus({file:'a'},'0','1'),{file:'a',start_t:0,end_t:1});assert.equal(api.number(null),'—');
const p=panel(), calls=[], pending=[], seeks=[];
const controller=api.create({panel:p,post:(url,body)=>{calls.push({url,body});return new Promise(resolve=>pending.push(resolve));},loadTimeline:async()=>({samples:[{index:39,time_s:1.56,speed:20,raw_inputs:[1,0,1,0,0,0,0,0],forward_related:true}]}),seek:t=>seeks.push(t),speed:v=>v+' units'});
const stage={id:1,chain:1,ordinal:1,kind:'released_drift_candidate',complete:true,start_t:1.6,end_t:2.4,start_csv_index:40,end_csv_index:60,forward_released_samples:20,drift_pulses:[],speed:{entry:20,end:25,minimum:18,peak:28,time_weighted_mean:22}};
const response={ok:true,subject:{file:'a',stream:'s',lap:1,stages:[stage],chain_count:1,curve:[{t:1.6,speed:20,pose_valid:true},{t:2.4,speed:25,pose_valid:true}]} };
(async()=>{
  controller.sync({subject:{file:'a',stream:'s',lap:1},baseline:null});
  const first=p.els.run.onclick();controller.sync({subject:{file:'b',stream:'s',lap:1},baseline:null});pending.shift()(response);await first;
  assert.equal(p.els.rows.children.length,0,'stale response leaked into new selection');assert.equal(p.els.export.disabled,true);
  controller.sync({subject:{file:'a',stream:'s',lap:1},baseline:null});p.els['a-start'].value='1';p.els['a-end'].value='2';
  const run=p.els.run.onclick();pending.shift()(response);await run;
  assert.equal(calls.at(-1).body.subject.start_t,1);assert.equal(p.els.rows.children.length,1);assert.equal(p.els.export.disabled,false);
  const links=p.els.rows.children[0].children[6];links.children[0].click();assert.deepEqual(seeks,[1.6]);await links.children[1].onclick();assert.match(p.els.evidence.textContent,/39\t1.560000/);
  assert.equal(p.els.plot.children[0].tag,'svg');controller.reset();assert.equal(p.els.rows.children.length,0);
  const multi=panel(), sent=[];
  const report={ok:true,subject:response.subject,comparisons:[],guidance:{accepted_reference_count:1,distinct_sav_count:1,rejected_references:[],items:[{stage_id:1,status:'observation_only',onset_offset_s:{count:1,median:.2,min:.2,max:.2},common_time_delta_s:{count:1,median:.1,min:.1,max:.1},unavailable_reasons:['vehicle_configuration_not_confirmed'],evidence:[{reference_file:'ref',reference_stream:'s',reference_lap:1,reference_stage_id:1,reference_start_csv_index:40,reference_end_csv_index:60,mapped_reference_on_a:{t:1.4}}]}]}};
  const m=api.create({panel:multi,post:async(url,body)=>{sent.push({url,body});return url.endsWith('batch')?report:response;},loadMetadata:async()=>({streams:[{id:'s',role:'local_high_frequency',laps:[{lap:1}]}]}),loadTimeline:async()=>({samples:[]}),seek:t=>seeks.push(t),speed:v=>v+' units'});
  m.sync({subject:{file:'a',stream:'s',lap:1},baseline:null,choices:[{file:'ref',label:'reference sample'}]});multi.els['reference-choice'].value='ref';await multi.els['add-reference'].onclick();assert.equal(multi.els.references.children.length,1);
  await multi.els['run-references'].onclick();assert.deepEqual(sent.map(s=>s.url),['/api/complex-action-comparison','/api/complex-action-batch']);assert.equal(sent[1].body.references[0].lap,1);assert.equal(sent[1].body.declarations.same_vehicle_configuration,false);
  assert.match(multi.els.guidance.children[1].children[0].textContent,/保留观测/);assert.equal(multi.els.export.disabled,false);
  multi.els['same-car'].checked=true;multi.els['same-car'].onchange();assert.match(multi.els.guidance.textContent,/条件已改变/);assert.equal(multi.els.export.disabled,true,'invalidated guidance remains exportable');
  m.reset();assert.equal(multi.els.references.children.length,0);
  console.log('[OK] Complex frontend: actual controller, selection invalidation, focus, seek, original input evidence and speed chart.');
})().catch(e=>{console.error(e);process.exitCode=1;});
