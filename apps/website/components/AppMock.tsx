const ROWS = [
  {
    name: "t3code-5b9b4d42",
    branch: "t3code/5b9b4d42",
    size: "1.4 GB",
    verdict: "live",
    tone: "live",
  },
  {
    name: "t3code-d000153c",
    branch: "t3code/dynamic-project-grid",
    size: "1.6 GB",
    verdict: ".env.local",
    tone: "block",
  },
  {
    name: "t3code-0dd49d63",
    branch: "feat/uptime-monitoring",
    size: "1.3 GB",
    verdict: "safe",
    tone: "safe",
  },
  {
    name: "t3code-3a9df360",
    branch: "t3code/github-action-node-check",
    size: "1.3 GB",
    verdict: "unmerged",
    tone: "caution",
  },
  {
    name: "agent-a6ac4f5dc7a13",
    branch: "fix/updater-rollback",
    size: "0 B",
    verdict: "prunable",
    tone: "ghost",
  },
] as const;

const TONE: Record<string, string> = {
  safe: "text-shoot border-shoot/35 bg-shoot/10",
  caution: "text-caution border-caution/35 bg-caution/10",
  block: "text-block border-block/35 bg-block/10",
  live: "text-live border-live/35 bg-live/10",
  ghost: "text-ghost border-ghost/35 bg-ghost/10",
};

/**
 * A representation of the app window, built from real markup rather than a
 * screenshot so it stays sharp at any density and readable to a screen reader.
 */
export function AppMock() {
  return (
    <div className="overflow-hidden rounded-xl border border-line-strong bg-panel shadow-2xl shadow-black/60">
      <div className="flex items-center gap-2 border-b border-line px-4 py-2.5">
        <span className="h-2.5 w-2.5 rounded-full bg-line-strong" />
        <span className="h-2.5 w-2.5 rounded-full bg-line-strong" />
        <span className="h-2.5 w-2.5 rounded-full bg-line-strong" />
        <span className="ml-2 font-mono text-[11px] text-faint">Coppice</span>
      </div>

      <div className="flex flex-wrap items-end justify-between gap-3 border-b border-line px-5 py-4">
        <div>
          <div className="text-base font-semibold">Worktrees</div>
          <div className="font-mono text-[11px] text-dim">
            52 across 22 repos · 36.2 GB
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span className="rounded-md border border-line-strong bg-elevated px-3 py-1.5 font-mono text-[11px] text-dim">
            Rescan
          </span>
          <span className="rounded-md bg-fg px-3 py-1.5 font-mono text-[11px] font-semibold text-black">
            Sweep 22.4 GB
          </span>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-px border-b border-line bg-line sm:grid-cols-4">
        {[
          ["22.4 GB", "reclaimable now", "text-shoot"],
          ["17", "sweepable worktrees", "text-fg"],
          ["35", "protected", "text-block"],
          ["10", "prunable", "text-ghost"],
        ].map(([value, label, tone]) => (
          <div key={label} className="bg-bg px-4 py-3">
            <div className={`font-mono text-lg font-semibold ${tone}`}>
              {value}
            </div>
            <div className="text-[10px] text-dim">{label}</div>
          </div>
        ))}
      </div>

      <div className="border-b border-line-strong bg-panel px-5 py-2 font-mono text-[10px] tracking-[0.12em] text-faint uppercase">
        ENV_Connect · T3 Code · 17 worktrees · 27 GB
      </div>

      {ROWS.map((row) => (
        <div
          key={row.name}
          className="flex items-center gap-3 border-b border-line px-5 py-2.5 text-sm last:border-b-0"
        >
          <div className="min-w-0 flex-1">
            <div className="truncate font-mono text-[12px]">{row.name}</div>
            <div className="truncate font-mono text-[10px] text-dim">
              {row.branch}
            </div>
          </div>
          <div className="w-16 shrink-0 text-right font-mono text-[11px] text-dim">
            {row.size}
          </div>
          <div className="w-28 shrink-0">
            <span
              className={`inline-block rounded border px-2 py-0.5 font-mono text-[9px] tracking-wide uppercase ${TONE[row.tone]}`}
            >
              {row.verdict}
            </span>
          </div>
        </div>
      ))}
    </div>
  );
}
