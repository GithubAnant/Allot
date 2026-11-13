import {UsageAggregator, resolveModelAliases} from './aggregation';
import {parseRateTable, createOverrideRateTable} from './pricing';
import {mergeUsage} from './merge';
import {collectLimitPools, displayLimitWindows, cursorUsageWindowDetails, paceRemainingPercent, remainingPercent, formatResetsIn} from './limits';
import {parseClaudeLine} from './claude';
import {parseCodexLine, initialCodexScanState} from './codex';
import {decodeCursorAccountCaches} from './cursorCache';

export function cursorRateModel(model:string) {
 const base=model.replace(/^cursor-/, '').replace(/(?:-thinking)?(?:-(?:none|minimal|low|medium|high|xhigh|max))?(?:-fast)?$/, '');
 return base.startsWith('grok-') ? 'xai/'+base : base;
}
export function poolJSON(json:string) {
 const input=JSON.parse(json);
 const groups=collectLimitPools(input.accounts,input.now);
 return JSON.stringify(groups.map(group=>({driver:group.driver,windows:displayLimitWindows(group).map(window=>{
  const details=group.driver==='cursor' ? cursorUsageWindowDetails(window.id,group) : undefined;
  return {id:window.id,label:details?.label===null ? '' : details?.label??window.label,description:details?.description,remaining:window.remainingPercent,pace:window.pace,
   segments:window.columns.map(member=>member.window===null ? null : ({key:member.account.key,name:member.account.displayName??member.account.email??member.account.key,remaining:remainingPercent(member.window),used:member.window.usedPercent,pace:paceRemainingPercent(member.window,input.now),reset:member.window.resetsAt,resetLabel:formatResetsIn(member.window,input.now),refill:member.refillPercent,credits:member.account.limits.resetCredits?.availableCount??0}))};
 })})));
}
function parseTranscript(input:any) {
 const records=[];
 const state=initialCodexScanState();
 for(const line of input.lines) records.push(...(input.provider==='claude'?parseClaudeLine(line):parseCodexLine(line,state)));
 return records;
}
export function parseTranscriptJSON(json:string) { return JSON.stringify(parseTranscript(JSON.parse(json))); }
const historyFiles=new Map<string,any>();
export function summaryJSON(json:string) {
 const input=JSON.parse(json);
 const rates=parseRateTable(input.rates);
 const aggregator=new UsageAggregator({...(input.sinceTimeMs===undefined?{}:{resolution:'hour',sinceTimeMs:input.sinceTimeMs,untilTimeMs:input.now}),timeZone:input.timeZone,sinceDay:input.sinceDay,untilDay:input.untilDay,rates,priceOverrides:createOverrideRateTable(input.settings?.usagePriceOverrides??{}),modelAliases:resolveModelAliases(input.settings?.usageModelAliases??{}),modelFilter:input.settings?.usageModelFilter??undefined});
 const providers=new Set<string>(); const sessions=new Map<string,Set<string>>();
 for(const file of input.files??historyFiles.values()) {
  for(const record of file.records) {
   if(input.provider && record.provider!==input.provider)continue;
   providers.add(record.provider);
   let set=sessions.get(record.provider);if(!set){set=new Set; sessions.set(record.provider,set)}
   if(aggregator.add(record,record.provider)&&record.sessionId)set.add(record.sessionId);
  }
 }
 if(input.cursorCache && (!input.provider || input.provider==='cursor')) for(const cache of decodeCursorAccountCaches(input.cursorCache).values()) {
  providers.add('cursor');
  let set=sessions.get('cursor');if(!set){set=new Set;sessions.set('cursor',set)}
  for(const record of cache.records){if(aggregator.add(record,'cursor')&&record.sessionId)set.add(record.sessionId)}
 }
 const buckets=aggregator.finish().buckets;
 const sources=[...providers].map(provider=>({fingerprint:{hostId:'local',provider,resolvedHomePath:provider,volumeId:'local'},status:'ok',scannedFiles:1,skippedFiles:0,malformedRecords:0,distinctSessions:sessions.get(provider)?.size??0,message:null}));
 const merged=mergeUsage([{environmentId:'local',label:'This Mac',summary:{contractVersion:6,readAt:new Date(input.now).toISOString(),buckets,sources,modelFilter:input.settings?.usageModelFilter??undefined}}],6);
 return JSON.stringify({costUsd:merged.costUsd,totalTokens:merged.totalTokens,records:merged.records,sessions:merged.sessions,providers:merged.providers,models:merged.models,costQuality:merged.costQuality,categoryCost:merged.categoryCost});
}
function decodeCache(root:any) {
 const files=[];
 if(!Number.isInteger(root.version)||root.version<4||root.version>15||!Array.isArray(root.models)||!Array.isArray(root.sessions))throw Error('Unsupported T3 usage cache');
 const speeds=['standard','fast','ultrafast'];
 for(const [path,file] of Object.entries(root.files??{})) {
  const records=[];let valid=true;
  for(const row of [...(file.r??[]),...(file.t??[])]) {
   const [timestampMs,modelIndex,sessionIndex,uncached,cached,creation,output,reasoning,key,cost,speedIndex,rateModelIndex,unresolved,creation1h=0]=row;
   const model=root.models[modelIndex],speed=speeds[speedIndex];
   if(![timestampMs,uncached,cached,creation,output,reasoning,creation1h].every(Number.isFinite)||typeof model!=='string'||!speed){valid=false;break}
   if(file.p==='claude'&&model==='<synthetic>')continue;
   records.push({provider:file.p,timestampMs,model,sessionId:root.sessions[sessionIndex]??'',totals:{uncachedInputTokens:uncached,cachedInputTokens:cached,cacheCreationTokens:creation,outputTokens:output,reasoningTokens:reasoning},reportedCostUsd:typeof cost==='number'?cost:null,speed,dedupeKey:typeof key==='string'?key:null,...(rateModelIndex==null?{}:{rateModel:root.models[rateModelIndex]}),...(creation1h>0?{cacheCreation1hTokens:creation1h}:{})});
  }
  if(valid)files.push({path,provider:file.p,size:file.s,mtimeMs:file.m,records});
 }
 return files;
}
export function decodeCacheJSON(json:string) { return JSON.stringify(decodeCache(JSON.parse(json))); }
export function loadHistoryCacheJSON(json:string) {
 for(const file of decodeCache(JSON.parse(json))) {
  if((historyFiles.get(file.path)?.mtimeMs??0)<=file.mtimeMs)historyFiles.set(file.path,file);
 }
 return JSON.stringify([...historyFiles.values()].map(({path,provider,size,mtimeMs})=>({path,provider,size,mtimeMs})));
}
export function updateHistoryTranscriptJSON(json:string) {
 const input=JSON.parse(json);
 historyFiles.set(input.path,{path:input.path,provider:input.provider,size:input.size,mtimeMs:input.mtimeMs,records:parseTranscript(input)});
 return '{}';
}
