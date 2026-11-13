import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { build } from 'esbuild';
const root = path.resolve(import.meta.dirname, '..');
const upstream = path.join(root, '.reference/t3code');
const out = path.join(import.meta.dirname, 't3-source');
fs.mkdirSync(out, {recursive: true});
const files = {
 core: 'packages/provider-core/src/server/usage.ts',
 pricing: 'apps/server/src/usage/usagePricing.ts',
 aggregation: 'apps/server/src/usage/usageAggregation.ts',
 merge: 'packages/shared/src/usageMerge.ts',
 limits: 'packages/shared/src/usageLimits.ts',
 claude: 'apps/server/src/provider/Drivers/claudeUsage.ts',
 codex: 'apps/server/src/provider/Drivers/codexUsage.ts',
 cursorCache: 'packages/provider-cursor/src/server/accountCache.ts',
};
const manifest = {repository:'https://github.com/pingdotgg/t3code', revision:'60f70d98cdeb2c692db649b9ade3adf74dd62bf9', files:{}};
const noImports = s => s.replace(/^import\b[\s\S]*?;\s*$/gm, '');
for (const [name, relative] of Object.entries(files)) {
 let raw = fs.readFileSync(path.join(upstream,relative),'utf8');
 manifest.files[relative] = crypto.createHash('sha256').update(raw).digest('hex');
 fs.writeFileSync(path.join(out,name+'.upstream.ts'),raw);
 let s = noImports(raw);
 if(name==='aggregation') s = 'import {EMPTY_TOTALS} from "./core";\nimport {priceUsage,cacheSavingsUsd} from "./pricing";\n'+s;
 if(name==='merge') s = 'const USAGE_MERGE_COMPATIBLE_SINCE = 4;\n'+s;
 if(name==='claude') s = 'import {parseTimestampMs,tokenCount} from "./core";\n'+s.slice(0,s.indexOf('export const claudeUsageFormat'));
 if(name==='codex') {
  s=s.slice(0,s.indexOf('export const codexUsageFormat'));
  const begin=s.indexOf('const TokenCount'); const end=s.indexOf('function readCodexTokenUsage');
  s=s.slice(0,begin)+`const CODEX_USAGE_FIELDS=['input_tokens','cached_input_tokens','cache_write_input_tokens','output_tokens','reasoning_output_tokens','total_tokens'];
const isCodexTokenUsage = u => CODEX_USAGE_FIELDS.every(k=>Number.isInteger(u[k])&&u[k]>=0) && u.cached_input_tokens+u.cache_write_input_tokens<=u.input_tokens && u.reasoning_output_tokens<=u.output_tokens && u.total_tokens>=u.input_tokens+u.output_tokens;\n`+s.slice(end);
  const schemaStart=s.indexOf('const CodexSpeed'); const schemaEnd=s.indexOf('function unreportedRequests');
  s=s.slice(0,schemaStart)+s.slice(schemaEnd);
  const stateStart=s.indexOf('export const CodexScanState');const stateEnd=s.indexOf('export function initialCodexScanState');
  s=s.slice(0,stateStart)+s.slice(stateEnd);
  s='import {parseTimestampMs} from "./core";\n'+s;
 }
 if(name==='cursorCache') s='import {cursorRateModel} from "./entry";\n'+s;
 fs.writeFileSync(path.join(out,name+'.ts'),s);
}
fs.writeFileSync(path.join(out,'SOURCE.json'),JSON.stringify(manifest,null,2)+'\n');
fs.copyFileSync(path.join(upstream,'LICENSE'),path.join(root,'docs/T3-LICENSE.txt'));
await build({entryPoints:[path.join(out,'entry.ts')],bundle:true,format:'iife',globalName:'T3Usage',target:'safari17',treeShaking:true,outfile:path.join(root,'Sources/Quota/Assets/T3Usage.js'),legalComments:'inline',banner:{js:'// Extracted from T3 Code '+manifest.revision+'; MIT license in T3-LICENSE.txt. Native I/O and SwiftUI replace the host and chart.'}});
console.log('Extracted T3 usage math and transcript parsers at '+manifest.revision);
