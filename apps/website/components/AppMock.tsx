const SIDEBAR = [
  ["All Worktrees", "42", true],
  ["Safe to Sweep", "8", false],
  ["Needs Attention", "37", false],
  ["Stale", "11", false],
] as const;

const AGENTS = [
  ["Claude Code", "6"],
  ["T3 Code", "24"],
  ["Manual", "12"],
] as const;

const ROWS = [
  { name: "t3code-6da8e6e7", branch: "t3code/general-help-request", artifact: "463 kB", size: "19.6 MB", verdict: "Safe", tone: "green" },
  { name: "t3code-99ca1d92", branch: "t3code/fix-cli-npm-publish", artifact: "463 kB", size: "19.5 MB", verdict: "Safe", tone: "green" },
  { name: "t3code-5b9b4d42", branch: "feat/convex-direct-web", artifact: "2.3 GB", size: "2.32 GB", verdict: "In use", tone: "blue" },
  { name: "t3code-ca476e75", branch: "t3code/align-subpages-to-theme", artifact: "1.49 GB", size: "6.18 GB", verdict: "Unpushed", tone: "red" },
  { name: "t3code-69fa9055", branch: "t3code/react-doctor-audit", artifact: "1.47 GB", size: "1.49 GB", verdict: "Uncommitted", tone: "red" },
  { name: "agent-a6ac4f5dc7", branch: "fix/updater-rollback", artifact: "", size: "0 B", verdict: "Stale", tone: "muted" },
] as const;

const TONE: Record<string, string> = {
  green: "text-green",
  blue: "text-blue",
  red: "text-red",
  muted: "text-label-3",
};

/** Filled check, bolt, lock and clock. Matches the SF Symbols the app uses. */
const GLYPH: Record<string, string> = {
  green: "M12 2a10 10 0 100 20 10 10 0 000-20zm-1 14l-4-4 1.5-1.5L11 13l4.5-4.5L17 10z",
  blue: "M12 2a10 10 0 100 20 10 10 0 000-20zm1 4l-5 7h3l-1 5 5-7h-3z",
  red: "M12 1a5 5 0 015 5v3h.5A1.5 1.5 0 0119 10.5v9A1.5 1.5 0 0117.5 21h-11A1.5 1.5 0 015 19.5v-9A1.5 1.5 0 016.5 9H7V6a5 5 0 015-5zm0 2a3 3 0 00-3 3v3h6V6a3 3 0 00-3-3z",
  muted: "M12 2a10 10 0 100 20 10 10 0 000-20zm1 5v5.3l3.5 2.1-.9 1.5L11 13V7z",
};

/**
 * The app window, built from markup rather than a screenshot so it stays sharp
 * at any density and is readable to a screen reader.
 */
export function AppMock() {
  return (
    <div className="mx-auto max-w-5xl overflow-hidden rounded-[18px] bg-surface shadow-[0_50px_100px_-20px_rgba(0,0,0,0.9)] ring-1 ring-white/10">
      <div className="flex items-center gap-2 px-5 py-3.5">
        <span className="h-3 w-3 rounded-full bg-[#ff5f57]" />
        <span className="h-3 w-3 rounded-full bg-[#febc2e]" />
        <span className="h-3 w-3 rounded-full bg-[#28c840]" />
      </div>

      <div className="grid sm:grid-cols-[14rem_1fr]">
        <aside className="hidden p-3 text-[14px] sm:block">
          {SIDEBAR.map(([label, count, active]) => (
            <div
              key={label}
              className={`flex items-center justify-between rounded-lg px-3 py-2 ${
                active ? "bg-surface-3 text-label" : "text-label-2"
              }`}
            >
              <span>{label}</span>
              <span className="text-label-3">{count}</span>
            </div>
          ))}
          <div className="mt-6 px-3 pb-1 text-[12px] font-medium text-label-3">
            Created By
          </div>
          {AGENTS.map(([label, count]) => (
            <div
              key={label}
              className="flex items-center justify-between px-3 py-2 text-label-2"
            >
              <span>{label}</span>
              <span className="text-label-3">{count}</span>
            </div>
          ))}
        </aside>

        <div className="bg-[#242426]">
          <div className="flex flex-wrap items-center justify-between gap-3 px-5 py-4">
            <div>
              <div className="font-semibold tracking-tight">Coppice</div>
              <div className="text-[13px] text-label-2">42 worktrees · 76.61 GB</div>
            </div>
            <span className="rounded-lg bg-blue-solid px-3.5 py-1.5 text-[14px] font-medium text-white">
              Sweep 22.4 GB
            </span>
          </div>

          <div className="px-5 pb-1 text-[12px] font-medium text-label-3">
            ENV_Connect
          </div>

          {ROWS.map((row) => (
            <div
              key={row.name}
              className="mx-2 flex items-center gap-3 rounded-lg px-3 py-2.5 text-[14px] odd:bg-white/[0.03]"
            >
              <svg
                width="17"
                height="17"
                viewBox="0 0 24 24"
                aria-hidden
                className={`shrink-0 ${TONE[row.tone]}`}
              >
                <path d={GLYPH[row.tone]} fill="currentColor" />
              </svg>
              <div className="min-w-0 flex-1">
                <div className="truncate">{row.name}</div>
                <div className="truncate text-[12px] text-label-3">{row.branch}</div>
              </div>
              <div className="hidden w-16 shrink-0 text-right text-[13px] text-green sm:block">
                {row.artifact}
              </div>
              <div className="w-16 shrink-0 text-right text-label-2">{row.size}</div>
              <div className={`hidden w-24 shrink-0 sm:block ${TONE[row.tone]}`}>
                {row.verdict}
              </div>
            </div>
          ))}
          <div className="h-3" />
        </div>
      </div>
    </div>
  );
}
