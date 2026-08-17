const ROWS = [
  { name: "t3code-6da8e6e7", branch: "t3code/general-help-request", artifact: "463 kB", size: "19.6 MB", verdict: "Safe", tone: "shoot" },
  { name: "t3code-5b9b4d42", branch: "feat/convex-direct-web", artifact: "2.3 GB", size: "2.32 GB", verdict: "In use", tone: "live" },
  { name: "t3code-ca476e75", branch: "t3code/align-subpages-to-app-theme", artifact: "1.49 GB", size: "6.18 GB", verdict: "Unpushed", tone: "alarm" },
  { name: "t3code-69fa9055", branch: "t3code/react-doctor-audit-web-fixes", artifact: "1.47 GB", size: "1.49 GB", verdict: "Uncommitted", tone: "alarm" },
  { name: "agent-a6ac4f5dc7a13", branch: "fix/updater-rollback", artifact: "", size: "0 B", verdict: "Stale", tone: "muted" },
] as const;

const TONE: Record<string, string> = {
  shoot: "text-shoot",
  live: "text-[#4da6ff]",
  alarm: "text-alarm",
  muted: "text-ink-4",
};

const GLYPH: Record<string, string> = {
  shoot: "M9 12l2 2 4-4",
  live: "M13 3l-8 10h6l-2 8 8-10h-6z",
  alarm: "M6 10V7a6 6 0 1112 0v3",
  muted: "M12 8v4l3 2",
};

/**
 * The app window, built from markup rather than a screenshot so it stays sharp
 * at any density and readable to a screen reader.
 */
export function AppMock() {
  return (
    <div className="overflow-hidden rounded-xl border border-hair-2 bg-raise shadow-2xl shadow-black/80">
      <div className="flex items-center gap-2 border-b border-hair px-4 py-3">
        <span className="h-2.5 w-2.5 rounded-full bg-hair-2" />
        <span className="h-2.5 w-2.5 rounded-full bg-hair-2" />
        <span className="h-2.5 w-2.5 rounded-full bg-hair-2" />
      </div>

      <div className="grid md:grid-cols-[13rem_1fr]">
        <div className="hidden border-r border-hair p-3 text-[13px] md:block">
          {[
            ["All Worktrees", "42", true],
            ["Safe to Sweep", "8", false],
            ["Needs Attention", "37", false],
            ["Stale", "11", false],
          ].map(([label, count, active]) => (
            <div
              key={label as string}
              className={`flex items-center justify-between rounded px-2.5 py-1.5 ${
                active ? "bg-raise-2 text-ink" : "text-ink-3"
              }`}
            >
              <span>{label}</span>
              <span className="tnum text-ink-4">{count}</span>
            </div>
          ))}
          <div className="mt-5 px-2.5 text-[11px] tracking-wide text-ink-4 uppercase">
            Created by
          </div>
          {[
            ["Claude Code", "6"],
            ["T3 Code", "24"],
            ["Manual", "12"],
          ].map(([label, count]) => (
            <div key={label} className="flex items-center justify-between px-2.5 py-1.5 text-ink-3">
              <span>{label}</span>
              <span className="tnum text-ink-4">{count}</span>
            </div>
          ))}
        </div>

        <div>
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-hair px-5 py-3.5">
            <div>
              <div className="font-medium">Coppice</div>
              <div className="text-[13px] text-ink-3">42 worktrees · 76.61 GB</div>
            </div>
            <span className="rounded-md bg-ink px-3 py-1.5 text-[13px] font-medium text-black">
              Sweep 22.4 GB
            </span>
          </div>

          <div className="flex items-center justify-between border-b border-hair px-5 py-2 text-[11px] tracking-wide text-ink-4 uppercase">
            <span>ENV_Connect</span>
            <span className="tnum">27 GB</span>
          </div>

          {ROWS.map((row) => (
            <div
              key={row.name}
              className="flex items-center gap-3 border-b border-hair px-5 py-2.5 text-[13px] last:border-b-0"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden className={`shrink-0 ${TONE[row.tone]}`}>
                <path d={GLYPH[row.tone]} stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              <div className="min-w-0 flex-1">
                <div className="truncate">{row.name}</div>
                <div className="truncate text-[12px] text-ink-4">{row.branch}</div>
              </div>
              <div className="tnum hidden w-16 shrink-0 text-right text-shoot sm:block">
                {row.artifact}
              </div>
              <div className="tnum w-16 shrink-0 text-right text-ink-2">{row.size}</div>
              <div className={`w-24 shrink-0 ${TONE[row.tone]}`}>{row.verdict}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
