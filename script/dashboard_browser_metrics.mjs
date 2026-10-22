// Independent translation of the pinned dashboard's visible calculations.
// Run only on sanitized fixture snapshots; no app runtime or dependencies.
import fs from 'node:fs';
const data = JSON.parse(fs.readFileSync(0, 'utf8'));
const {tasks, fast, slow} = data;
const profiles = slow.profiles;
const defaultID = profiles.find(p => p.is_default)?.id == null ? null : Number(profiles.find(p => p.is_default).id);
const byName = new Map(profiles.map(p => [p.name, Number(p.id)]));
const empty = () => ({input: 0, output: 0, cache_read: 0, cache_write: 0, task_count: 0});
const scenarios = {};
for (const source of ['old', 'ledger']) {
  const totals = new Map();
  const fold = (key, tokens, count) => {
    const b = totals.get(key) ?? empty();
    b.input += tokens.input_tokens ?? 0; b.output += tokens.output_tokens ?? 0;
    b.cache_read += tokens.cache_read_tokens ?? 0; b.cache_write += tokens.cache_write_tokens ?? 0;
    b.task_count += count; totals.set(key, b);
  };
  if (source === 'old') {
    for (const t of tasks) fold(t.llm_profile_id ?? defaultID, t.tokens ?? {}, 1);
    for (const c of fast.conversations) fold(c.llm_profile_id ?? defaultID, c, 0);
  } else {
    for (const p of slow.usage.by_profile ?? []) fold(byName.get(p.profile_name) ?? defaultID, p, p.tasks);
  }
  for (const [name, selected] of [['all', 'all'], ...profiles.map(p => [p.name, Number(p.id)])]) {
    const total = empty();
    for (const [key, b] of totals) if (selected === 'all' || selected === key) {
      for (const field of Object.keys(total)) total[field] += b[field];
    }
    for (const days of [7, 30]) {
      const cutoff = new Date('2026-10-22T12:00:00Z'); cutoff.setUTCDate(cutoff.getUTCDate() - days);
      const prefix = cutoff.toISOString().slice(0, 10);
      const daily = new Map();
      const add = (date, key, tokens) => {
        if (!date || date < prefix || (selected !== 'all' && selected !== key)) return;
        const row = daily.get(date) ?? {date, input: 0, output: 0, cache_read: 0};
        row.input += tokens.input_tokens ?? 0; row.output += tokens.output_tokens ?? 0;
        row.cache_read += tokens.cache_read_tokens ?? 0; daily.set(date, row);
      };
      if (source === 'old') {
        for (const t of tasks) add(t.created_at.slice(0, 10), t.llm_profile_id ?? defaultID, t.tokens ?? {});
        for (const c of fast.conversations) add(c.created_at.slice(0, 10), c.llm_profile_id ?? defaultID, c);
      } else {
        for (const p of slow.usage.daily ?? []) add(p.date, byName.get(p.profile_name) ?? defaultID, p);
      }
      scenarios[`${source}/${name}/${days}`] = {...total, uncached_input: total.input - total.cache_read,
        cache_hit_percent: total.input > 0 ? Math.round(total.cache_read / total.input * 100) : 0,
        daily: [...daily.values()].sort((a, b) => a.date.localeCompare(b.date))};
    }
  }
}
const severities = {};
for (const f of fast.findings) severities[f.severity] = (severities[f.severity] ?? 0) + 1;
console.log(JSON.stringify({scenarios, running_tasks: tasks.filter(t => t.status === 'running').length,
  task_ids: [...tasks].sort((a,b) => (b.last_activity_unix ?? b.created_unix ?? 0) - (a.last_activity_unix ?? a.created_unix ?? 0)).slice(0,5).map(t => t.id),
  finding_ids: [...fast.findings].sort((a,b) => Date.parse(b.ts) - Date.parse(a.ts)).slice(0,8).map(f => f.id),
  activity_seq: fast.activity.filter(a => a.kind !== 'usage').sort((a,b) => b.seq-a.seq).slice(0,6).map(a => a.seq),
  severity_counts: severities, asset_total: Object.values(slow.asset_counts).reduce((a,b) => a+b, 0),
  asset_types: Object.entries(slow.asset_counts).filter(([,v]) => v>0).sort((a,b) => b[1]-a[1] || a[0].localeCompare(b[0])).slice(0,8).map(([name,count]) => ({name,count})),
  pending_count: fast.pending.length, llm_configured: fast.stats.llm_configured, traffic_capture: fast.settings.traffic_capture,
  traffic_count: slow.traffic.length}));
