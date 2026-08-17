import { AppMock } from "@/components/AppMock";
import { CopyCommand } from "@/components/CopyCommand";
import { Reveal } from "@/components/Reveal";

const REPO = "https://github.com/rafay99-epic/Coppice";
const DMG = `${REPO}/releases/latest/download/Coppice.dmg`;

const TIERS = [
  {
    name: "Sweep",
    tone: "text-shoot",
    border: "hover:border-shoot/40",
    claim: "Reversible",
    body: "Deletes build output inside worktrees. node_modules, .next, target, DerivedData. Never touches source or git state.",
    detail: "The undo is the install command you already run.",
  },
  {
    name: "Prune",
    tone: "text-ghost",
    border: "hover:border-ghost/40",
    claim: "Nothing on disk",
    body: "Clears git metadata for worktrees whose directories are already gone. Git itself considers these dead.",
    detail: "Frees no space. Gives you back a readable worktree list.",
  },
  {
    name: "Remove",
    tone: "text-block",
    border: "hover:border-block/40",
    claim: "Permanent",
    body: "Deletes the worktree, prunes the metadata, optionally deletes the branch. Gated behind every check below.",
    detail: "Typed confirmation, one at a time. There is no Remove All.",
  },
];

const RULES = [
  ["Live process", "An open session, editor or dev server blocks sweep and remove."],
  ["Uncommitted changes", "Modified and staged files are work that exists nowhere else."],
  ["Untracked files", "New files git has never seen are still yours."],
  ["Unpushed commits", "Work that has not reached a remote is not backed up."],
  ["Ahead of default", "No upstream, and commits missing from the default branch."],
  ["Gitignored config", ".env.local and friends. Git calls the worktree clean and it is lying."],
  ["Locked worktree", "Someone ran git worktree lock. That was on purpose."],
  ["Operation in progress", "A half-finished rebase, merge, cherry-pick or bisect."],
  ["Dirty submodule", "Changes nested inside a submodule count too."],
  ["Outside your roots", "Coppice refuses paths beyond the folders you configured."],
  ["Main worktree", "The repository's own working copy is never removable."],
];

export default function Home() {
  return (
    <main className="mx-auto max-w-6xl px-5 pb-28">
      <Nav />
      <Hero />
      <Problem />
      <Tiers />
      <Safety />
      <NoPolling />
      <Install />
      <Footer />
    </main>
  );
}

function Nav() {
  return (
    <nav className="sticky top-0 z-50 -mx-5 mb-2 border-b border-line bg-black/85 px-5 backdrop-blur-md">
      <div className="flex items-center justify-between py-3.5">
        <a href="#top" className="flex items-center gap-2.5">
          <Mark />
          <span className="font-semibold tracking-tight">Coppice</span>
        </a>
        <div className="flex items-center gap-5 font-mono text-[11px] text-dim">
          <a href="#how" className="transition-colors hover:text-fg">
            How
          </a>
          <a href="#safety" className="transition-colors hover:text-fg">
            Safety
          </a>
          <a href="#install" className="transition-colors hover:text-fg">
            Install
          </a>
          <a
            href={REPO}
            className="rounded-md border border-line-strong px-2.5 py-1 transition-colors hover:border-shoot hover:text-shoot"
          >
            GitHub
          </a>
        </div>
      </div>
    </nav>
  );
}

/** The app mark: three shoots regrowing from a cut. Same geometry as the icon. */
function Mark({ size = 20 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden
      className="shrink-0"
    >
      <rect x="10.6" y="14.5" width="2.8" height="6" rx="1.4" fill="#3ddc84" opacity="0.3" />
      <rect x="5.2" y="8.4" width="2.6" height="7" rx="1.3" fill="#3ddc84" opacity="0.55" />
      <rect x="10.7" y="4.6" width="2.6" height="10.8" rx="1.3" fill="#3ddc84" />
      <rect x="16.2" y="6.9" width="2.6" height="8.5" rx="1.3" fill="#3ddc84" opacity="0.76" />
      <rect x="3.4" y="13.6" width="17.2" height="2.5" rx="1.25" fill="#3ddc84" />
    </svg>
  );
}

function Hero() {
  return (
    <section id="top" className="pt-16 pb-20 sm:pt-24">
      <Reveal>
        <p className="mb-5 font-mono text-[11px] tracking-[0.18em] text-faint uppercase">
          macOS · Apple Silicon · menu bar
        </p>
        <h1 className="max-w-3xl text-4xl leading-[1.05] font-bold tracking-tight sm:text-6xl">
          Cut agent worktrees back
          <br />
          <span className="text-shoot">so they grow again.</span>
        </h1>
        <p className="mt-6 max-w-xl text-base text-dim sm:text-lg">
          Your coding agents create a worktree per task and never clean up. Coppice
          finds all of them, works out which are genuinely safe to touch, and
          reclaims the space without eating uncommitted work or a live session.
        </p>
      </Reveal>

      <Reveal>
        <div className="mt-9 flex max-w-xl flex-col gap-3">
          <CopyCommand command="brew install --cask rafay99-epic/apps/coppice" />
          <div className="flex flex-wrap items-center gap-3">
            <a
              href={DMG}
              className="rounded-lg bg-fg px-4 py-2.5 text-sm font-semibold text-black transition-opacity hover:opacity-85"
            >
              Download the .dmg
            </a>
            <a
              href={REPO}
              className="rounded-lg border border-line-strong px-4 py-2.5 text-sm transition-colors hover:border-fg"
            >
              Read the source
            </a>
            <span className="font-mono text-[11px] text-faint">
              Free, open source, GPL-3.0
            </span>
          </div>
        </div>
      </Reveal>

      <Reveal className="mt-16">
        <AppMock />
      </Reveal>
    </section>
  );
}

function Problem() {
  return (
    <section className="border-t border-line py-20">
      <Reveal>
        <SectionHeading
          kicker="The problem"
          title="One machine, 36 GB of forgotten worktrees."
          lede="Measured on a working laptop running Claude Code, Codex and T3 Code side by side. The space is not really in the worktrees. It is seventeen near-identical copies of the same node_modules."
        />
      </Reveal>

      <Reveal>
        <div className="mt-10 grid grid-cols-2 gap-px border border-line bg-line sm:grid-cols-4">
          {[
            ["36 GB", "in agent worktrees"],
            ["52", "worktrees, 22 repos"],
            ["~22 GB", "build artifacts alone"],
            ["10", "already prunable"],
          ].map(([value, label]) => (
            <div key={label} className="bg-bg px-5 py-6">
              <div className="font-mono text-2xl font-semibold tracking-tight">
                {value}
              </div>
              <div className="mt-1 text-xs text-dim">{label}</div>
            </div>
          ))}
        </div>
      </Reveal>

      <Reveal>
        <div className="mt-8 rounded-lg border border-line border-l-2 border-l-block bg-panel p-5">
          <p className="mb-2 font-mono text-[10px] tracking-[0.14em] text-dim uppercase">
            The failure mode that actually hurts
          </p>
          <p className="max-w-3xl text-sm leading-relaxed text-dim">
            Some worktrees hold a{" "}
            <code className="rounded border border-line bg-elevated px-1.5 py-0.5 font-mono text-[12px] text-block">
              .env.local
            </code>
            . Those files are gitignored, so{" "}
            <code className="rounded border border-line bg-elevated px-1.5 py-0.5 font-mono text-[12px] text-fg">
              git status
            </code>{" "}
            reports the worktree as perfectly clean. A cleaner that trusts git
            alone calls it safe, deletes it, and destroys live secrets with no
            warning and no copy anywhere. Coppice treats that as a hard block.
          </p>
        </div>
      </Reveal>
    </section>
  );
}

function Tiers() {
  return (
    <section id="how" className="border-t border-line py-20">
      <Reveal>
        <SectionHeading
          kicker="How it works"
          title="Three operations, sorted by what they cost you."
          lede="Each is useful on its own. The reversible one takes a single click. The permanent one takes a typed confirmation, every time."
        />
      </Reveal>

      <div className="mt-10 grid gap-4 md:grid-cols-3">
        {TIERS.map((tier, index) => (
          <Reveal key={tier.name}>
            <div
              className={`h-full rounded-lg border border-line bg-panel p-6 transition-colors ${tier.border}`}
            >
              <div className="flex items-baseline justify-between">
                <h3 className={`text-lg font-semibold ${tier.tone}`}>
                  {tier.name}
                </h3>
                <span className="font-mono text-[10px] tracking-wide text-faint uppercase">
                  {tier.claim}
                </span>
              </div>
              <p className="mt-3 text-sm leading-relaxed text-dim">{tier.body}</p>
              <p className="mt-4 border-t border-line pt-4 font-mono text-[11px] text-faint">
                {tier.detail}
              </p>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  );
}

function Safety() {
  return (
    <section id="safety" className="border-t border-line py-20">
      <Reveal>
        <SectionHeading
          kicker="Safety"
          title="Eleven reasons Coppice will refuse."
          lede="Every rule is recomputed at the moment of deletion, not when the list was built. A background app scans on its own schedule, so a verdict can be minutes old by the time you press a button, and in those minutes an agent may have opened the very worktree you picked."
        />
      </Reveal>

      {/* Cells carry their own borders rather than showing a background through
          a 1px gap. With eleven rules the last row is short, and the gap trick
          would render that gap as a filled empty tile. */}
      <div className="mt-10 grid border-t border-l border-line sm:grid-cols-2 lg:grid-cols-3">
        {RULES.map(([title, detail]) => (
          <Reveal key={title} className="border-r border-b border-line">
            <div className="h-full bg-bg p-5 transition-colors hover:bg-panel">
              <div className="flex items-center gap-2">
                <svg width="11" height="11" viewBox="0 0 24 24" aria-hidden>
                  <path
                    d="M6 10V7a6 6 0 1112 0v3h1a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2v-8a2 2 0 012-2h1zm2 0h8V7a4 4 0 10-8 0v3z"
                    fill="#ff5c5c"
                  />
                </svg>
                <h3 className="text-sm font-medium">{title}</h3>
              </div>
              <p className="mt-1.5 text-xs leading-relaxed text-dim">{detail}</p>
            </div>
          </Reveal>
        ))}
      </div>

      <Reveal>
        <p className="mt-8 max-w-3xl text-sm leading-relaxed text-dim">
          Sweeping ignores all but the first rule, and that is the point. A
          dirty worktree still sweeps, because{" "}
          <code className="rounded border border-line bg-elevated px-1.5 py-0.5 font-mono text-[12px] text-fg">
            node_modules
          </code>{" "}
          is not source and is not tracked. That is how the first run reclaims
          most of the space while removal stays slow and deliberate.
        </p>
      </Reveal>
    </section>
  );
}

function NoPolling() {
  return (
    <section className="border-t border-line py-20">
      <div className="grid gap-10 lg:grid-cols-2">
        <Reveal>
          <SectionHeading
            kicker="Built to be ignored"
            title="No polling. Zero CPU until something changes."
            lede="A timer re-scanning 52 worktrees every minute would burn battery all day to learn nothing almost every time. Coppice uses FSEvents, so the kernel wakes it only when a watched directory actually changes."
          />
          <ul className="mt-6 space-y-3 text-sm text-dim">
            {[
              "Events coalesce in the kernel, so a 100k-file install arrives as one callback rather than 100k.",
              "Size walks run at background priority, one worktree at a time, and stop at the first artifact directory.",
              "No Dock icon, no app switcher entry, no window unless you open one.",
              "Nothing is ever deleted unattended. There is no setting that enables it.",
            ].map((line) => (
              <li key={line} className="flex gap-3">
                <span aria-hidden className="mt-2 h-1 w-1 shrink-0 rounded-full bg-shoot" />
                <span className="leading-relaxed">{line}</span>
              </li>
            ))}
          </ul>
        </Reveal>

        <Reveal>
          <div className="rounded-lg border border-line bg-panel p-6">
            <p className="mb-4 font-mono text-[10px] tracking-[0.14em] text-dim uppercase">
              Measured, 52 worktrees over 36 GB
            </p>
            <dl className="space-y-4">
              {[
                ["Idle CPU", "0.0%", "text-shoot"],
                ["Memory", "99 MB", "text-fg"],
                ["Inventory + verdicts", "3s", "text-fg"],
                ["Installer size", "1.3 MB", "text-fg"],
                ["Dependencies", "0", "text-shoot"],
              ].map(([label, value, tone]) => (
                <div
                  key={label}
                  className="flex items-baseline justify-between border-b border-line pb-3 last:border-b-0 last:pb-0"
                >
                  <dt className="text-sm text-dim">{label}</dt>
                  <dd className={`font-mono text-lg font-semibold ${tone}`}>
                    {value}
                  </dd>
                </div>
              ))}
            </dl>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

function Install() {
  return (
    <section id="install" className="border-t border-line py-20">
      <Reveal>
        <SectionHeading
          kicker="Install"
          title="Two commands, three channels."
          lede="Homebrew is the smooth path: it installs to /Applications with no security prompt, and Coppice updates itself after that."
        />
      </Reveal>

      <div className="mt-10 grid gap-4 md:grid-cols-2">
        <Reveal>
          <div className="h-full rounded-lg border border-line bg-panel p-6">
            <h3 className="font-semibold">Stable</h3>
            <p className="mt-1.5 mb-4 text-sm text-dim">
              Curated, cut from the nightly branch roughly weekly.
            </p>
            <CopyCommand command="brew install --cask rafay99-epic/apps/coppice" />
          </div>
        </Reveal>
        <Reveal>
          <div className="h-full rounded-lg border border-line bg-panel p-6">
            <h3 className="font-semibold">Nightly</h3>
            <p className="mt-1.5 mb-4 text-sm text-dim">
              Installs alongside Stable with its own icon and settings.
            </p>
            <CopyCommand command="brew install --cask rafay99-epic/apps/coppice-nightly" />
          </div>
        </Reveal>
      </div>

      <Reveal>
        <p className="mt-6 text-sm text-dim">
          Prefer a direct download? The{" "}
          <a href={DMG} className="text-fg underline decoration-line-strong underline-offset-4 transition-colors hover:decoration-shoot">
            .dmg
          </a>{" "}
          is not notarized, since there is no paid Apple Developer account behind
          it, so right-click and Open the first time to get past Gatekeeper.
          Requires macOS 15 or newer on Apple Silicon.
        </p>
      </Reveal>
    </section>
  );
}

function Footer() {
  return (
    <footer className="border-t border-line pt-8">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-2.5">
          <Mark size={16} />
          <span className="font-mono text-[11px] text-faint">
            Coppice · GPL-3.0 · Syntax Lab Technology
          </span>
        </div>
        <div className="flex gap-5 font-mono text-[11px] text-faint">
          <a href={REPO} className="transition-colors hover:text-fg">
            GitHub
          </a>
          <a href={`${REPO}/releases`} className="transition-colors hover:text-fg">
            Releases
          </a>
          <a href={`${REPO}/issues`} className="transition-colors hover:text-fg">
            Issues
          </a>
        </div>
      </div>
    </footer>
  );
}

function SectionHeading({
  kicker,
  title,
  lede,
}: {
  kicker: string;
  title: string;
  lede: string;
}) {
  return (
    <div className="max-w-3xl">
      <p className="mb-3 font-mono text-[11px] tracking-[0.18em] text-faint uppercase">
        {kicker}
      </p>
      <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
        {title}
      </h2>
      <p className="mt-4 leading-relaxed text-dim">{lede}</p>
    </div>
  );
}
