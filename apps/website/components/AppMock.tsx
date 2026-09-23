type State = "ready" | "work" | "use";

const STATE: Record<State, { label: string; glyph: React.ReactNode; weight: string }> = {
  ready: {
    label: "Ready",
    weight: "font-semibold text-label",
    glyph: <circle cx="8" cy="8" r="5" fill="currentColor" />,
  },
  work: {
    label: "Has work",
    weight: "text-label-2",
    glyph: (
      <>
        <circle cx="8" cy="8" r="4.5" fill="none" stroke="currentColor" strokeWidth="1.3" />
        <path d="M8 3.5a4.5 4.5 0 010 9z" fill="currentColor" />
      </>
    ),
  },
  use: {
    label: "In use",
    weight: "text-label-3",
    glyph: <circle cx="8" cy="8" r="4.5" fill="none" stroke="currentColor" strokeWidth="1.3" strokeDasharray="2 2" />,
  },
};

const SIDEBAR = [
  ["All Worktrees", "42", true],
  ["Ready", "9", false],
  ["Has Work", "29", false],
  ["In Use", "4", false],
] as const;

const AGENTS = [
  ["Claude Code", "6"],
  ["T3 Code", "24"],
  ["Codex", "12"],
] as const;

const ROWS: { name: string; branch: string; artifact: string; size: string; state: State }[] = [
  { name: "t3code-6da8e6e7", branch: "t3code/general-help-request", artifact: "463 MB", size: "1.2 GB", state: "ready" },
  { name: "t3code-99ca1d92", branch: "t3code/fix-cli-npm-publish", artifact: "1.1 GB", size: "1.3 GB", state: "ready" },
  { name: "t3code-5b9b4d42", branch: "feat/convex-direct-web", artifact: "2.3 GB", size: "2.32 GB", state: "use" },
  { name: "t3code-ca476e75", branch: "t3code/align-subpages-to-theme", artifact: "1.49 GB", size: "6.18 GB", state: "work" },
  { name: "t3code-69fa9055", branch: "t3code/react-doctor-audit", artifact: "1.47 GB", size: "1.49 GB", state: "work" },
  { name: "codex-a6ac4f5d", branch: "fix/updater-rollback", artifact: "812 MB", size: "840 MB", state: "ready" },
];

export function AppMock() {
  return (
    <div className="mx-auto max-w-5xl overflow-hidden rounded-[14px] bg-surface ring-1 ring-line">
      <div className="flex items-center gap-2 px-4 py-3">
        <span className="h-2.5 w-2.5 rounded-full bg-surface-3" />
        <span className="h-2.5 w-2.5 rounded-full bg-surface-3" />
        <span className="h-2.5 w-2.5 rounded-full bg-surface-3" />
      </div>

      <div className="grid sm:grid-cols-[13rem_1fr]">
        <aside className="hidden p-3 text-[14px] sm:block">
          {SIDEBAR.map(([label, count, active]) => (
            <div
              key={label}
              className={`flex items-center justify-between rounded-md px-3 py-1.5 ${
                active ? "bg-surface-3 text-label" : "text-label-2"
              }`}
            >
              <span>{label}</span>
              <span className="text-label-3 tabular-nums">{count}</span>
            </div>
          ))}
          <div className="mt-5 px-3 pb-1 text-[12px] text-label-3">Created by</div>
          {AGENTS.map(([label, count]) => (
            <div key={label} className="flex items-center justify-between px-3 py-1.5 text-label-2">
              <span>{label}</span>
              <span className="text-label-3 tabular-nums">{count}</span>
            </div>
          ))}
        </aside>

        <div className="min-w-0 bg-surface-2">
          <div className="flex flex-wrap items-center justify-between gap-3 px-4 py-3.5">
            <div>
              <div className="font-semibold">Coppice</div>
              <div className="text-[13px] text-label-2">42 worktrees, 76.6 GB</div>
            </div>
            <span className="rounded-md bg-white px-3 py-1.5 text-[14px] font-medium text-black">
              Sweep 22.4 GB
            </span>
          </div>

          <div className="px-4 pb-1 text-[12px] text-label-3">ENV_Connect</div>

          {ROWS.map((row) => {
            const state = STATE[row.state];
            return (
              <div
                key={row.name}
                className="mx-2 flex items-center gap-3 rounded-md px-2.5 py-2 text-[14px] odd:bg-white/[0.025]"
              >
                <div className="min-w-0 flex-1">
                  <div className="truncate">{row.name}</div>
                  <div className="truncate text-[12px] text-label-3">{row.branch}</div>
                </div>
                <div className="hidden w-16 shrink-0 text-right text-[13px] text-label-3 tabular-nums md:block">
                  {row.artifact}
                </div>
                <div className="w-16 shrink-0 text-right text-label-2 tabular-nums">{row.size}</div>
                <div className={`flex w-[5.5rem] shrink-0 items-center gap-1.5 text-[13px] ${state.weight}`}>
                  <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden className="shrink-0">
                    {state.glyph}
                  </svg>
                  {state.label}
                </div>
              </div>
            );
          })}
          <div className="h-2.5" />
        </div>
      </div>
    </div>
  );
}
