import { AppMock } from "@/components/AppMock";
import { CopyCommand } from "@/components/CopyCommand";
import { Mark } from "@/components/Mark";
import { Rise } from "@/components/Rise";

const REPO = "https://github.com/rafay99-epic/Coppice";
const DMG = `${REPO}/releases/latest/download/Coppice.dmg`;

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Scale />
        <Why />
        <Operations />
        <Rules />
        <Quiet />
        <OpenSource />
        <Install />
      </main>
      <Footer />
    </>
  );
}

function Nav() {
  return (
    <nav className="sticky top-0 z-50 bg-black/60 backdrop-blur-2xl">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <a href="#top" className="flex items-center gap-2.5">
          <Mark size={19} />
          <span className="font-semibold tracking-tight">Coppice</span>
        </a>
        <div className="flex items-center gap-7 text-[14px] text-label-2">
          <a href="#rules" className="transition-colors hover:text-label">
            Safety
          </a>
          <a href="#open" className="hidden transition-colors hover:text-label sm:block">
            Open source
          </a>
          <a
            href="#install"
            className="rounded-full bg-surface-2 px-4 py-1.5 text-label transition-colors hover:bg-surface-3"
          >
            Install
          </a>
        </div>
      </div>
    </nav>
  );
}

function Hero() {
  return (
    <section id="top" className="relative overflow-hidden px-6 pt-24 pb-28 sm:pt-36">
      {/* Soft light behind the window, the way a Mac app sits on a desktop.
          Decorative only, and it drifts rather than pulsing. */}
      <div
        aria-hidden
        className="bloom pointer-events-none absolute top-[18rem] left-1/2 h-[42rem] w-[70rem] -translate-x-1/2 rounded-full opacity-60 blur-[130px]"
        style={{
          background:
            "radial-gradient(closest-side, rgba(48,209,88,0.22), rgba(10,132,255,0.10) 55%, transparent)",
        }}
      />

      <div className="relative mx-auto max-w-6xl">
        <Rise>
          <h1 className="title mx-auto max-w-[15ch] text-center text-[clamp(2.9rem,8.5vw,6.75rem)]">
            Your agents leave the mess behind.
          </h1>
          <p className="mx-auto mt-8 max-w-[52ch] text-center text-xl text-label-2 sm:text-2xl">
            Every task gets its own git worktree. None of them get cleaned up. On
            the machine this was built against that is 42 worktrees and 76 GB.
          </p>
        </Rise>

        <Rise>
          <div className="mt-11 flex flex-col items-center gap-5">
            <div className="flex flex-wrap items-center justify-center gap-3">
              <a
                href={DMG}
                className="rounded-full bg-white px-7 py-3 font-medium text-black transition-transform duration-200 hover:scale-[1.03]"
              >
                Download for macOS
              </a>
              <a
                href={REPO}
                className="rounded-full bg-surface-2 px-7 py-3 font-medium transition-colors hover:bg-surface-3"
              >
                View source
              </a>
            </div>
            <p className="text-[14px] text-label-3">
              Free and MIT licensed. Requires macOS 15 on Apple Silicon.
            </p>
          </div>
        </Rise>

        <div className="settle mt-20">
          <AppMock />
        </div>
      </div>
    </section>
  );
}

const SCALE = [
  ["42", "worktrees", "text-label"],
  ["76 GB", "sitting on disk", "text-label"],
  ["37", "held real work", "text-orange"],
  ["22 GB", "safe to reclaim", "text-green"],
];

function Scale() {
  return (
    <section className="px-6 py-28">
      <div className="mx-auto max-w-6xl">
        <Rise>
          <h2 className="title-2 mx-auto max-w-[18ch] text-center text-[clamp(2rem,4.5vw,3.25rem)]">
            This is one laptop, on an ordinary Tuesday.
          </h2>
        </Rise>

        <div className="mt-16 grid gap-y-12 sm:grid-cols-2 lg:grid-cols-4">
          {SCALE.map(([value, label, tone]) => (
            <Rise key={label}>
              <div className="text-center">
                <div className={`title-2 text-[clamp(2.5rem,6vw,3.75rem)] ${tone}`}>
                  {value}
                </div>
                <div className="mt-2 text-label-2">{label}</div>
              </div>
            </Rise>
          ))}
        </div>

        <Rise>
          <p className="mx-auto mt-16 max-w-[58ch] text-center text-lg text-label-2">
            Nobody plans this. You spin up a worktree to try something, the branch
            merges, and the directory stays. Multiply by four agents working in
            parallel and the disk quietly fills with the residue of work you already
            finished.
          </p>
        </Rise>
      </div>
    </section>
  );
}

function Why() {
  return (
    <section className="px-6 py-28">
      <div className="mx-auto max-w-[54ch]">
        <Rise>
          <h2 className="title-2 text-[clamp(2rem,4.5vw,3.25rem)]">
            So why not just delete them?
          </h2>
          <p className="mt-8 text-xl leading-relaxed text-label-2">
            Because the obvious version of this tool destroys your work.
          </p>
          <p className="mt-6 text-lg leading-relaxed text-label-2">
            A script that finds old worktrees and removes the clean ones sounds
            safe enough. It asks git whether the directory is clean, git says yes,
            the directory goes. That is the whole idea, and it is wrong in a way you
            only find out afterwards.
          </p>
        </Rise>

        <Rise>
          <div className="my-14 text-center">
            <p className="text-lg text-label-2">A worktree holding this file</p>
            <p className="title-2 mt-4 text-[clamp(2.25rem,6vw,3.5rem)] text-red">
              .env.local
            </p>
            <p className="mx-auto mt-4 max-w-[44ch] text-lg text-label-2">
              reports as perfectly clean, because it is gitignored. Git has never
              seen it and holds no copy. Neither does your remote.
            </p>
          </div>
        </Rise>

        <Rise>
          <p className="text-lg leading-relaxed text-label-2">
            Delete that worktree and the secrets are gone. Not recoverable from a
            branch, not on the remote, not in a stash. The one check that would have
            caught it is the check a naive cleaner never thinks to make, and you
            learn about it when something stops authenticating.
          </p>
          <p className="mt-6 text-lg leading-relaxed text-label-2">
            Coppice exists because the careful version of this is genuinely fiddly.
            Eleven conditions decide whether a worktree is safe, and every one of
            them has to be rechecked at the instant of deletion. A background
            scanner{"'"}s verdict is already minutes old by the time you press a
            button, and in those minutes an agent can open the very worktree you
            picked.
          </p>
        </Rise>
      </div>
    </section>
  );
}

const OPERATIONS = [
  {
    name: "Sweep",
    tone: "text-green",
    dot: "bg-green",
    claim: "Reversible",
    body: "Deletes build output inside worktrees. node_modules, .next, target, DerivedData. Source, git history and local config are never touched. It runs on dirty worktrees too, because a dependency folder is not your work.",
    note: "The undo is the install command you already type.",
  },
  {
    name: "Prune",
    tone: "text-label-2",
    dot: "bg-surface-3",
    claim: "Frees nothing",
    body: "Clears git metadata for worktrees whose directories are already gone. Git considers these dead, so nothing on disk is touched. What you get back is a worktree list you can actually read.",
    note: "Ten of them were already dead on this machine.",
  },
  {
    name: "Remove",
    tone: "text-red",
    dot: "bg-red",
    claim: "Permanent",
    body: "Deletes the worktree itself, prunes the metadata, and optionally deletes the branch. Gated behind every rule below, then a typed confirmation naming the worktree.",
    note: "There is no Remove All anywhere in the app, on purpose.",
  },
];

function Operations() {
  return (
    <section id="how" className="px-6 py-28">
      <div className="mx-auto max-w-6xl">
        <Rise>
          <h2 className="title-2 mx-auto max-w-[20ch] text-center text-[clamp(2rem,4.5vw,3.25rem)]">
            Three operations, priced by what they cost you.
          </h2>
        </Rise>

        <div className="mt-18 grid gap-14 md:grid-cols-3 md:gap-10">
          {OPERATIONS.map((operation) => (
            <Rise key={operation.name}>
              <div>
                <div className="flex items-center gap-2.5">
                  <span className={`h-2 w-2 rounded-full ${operation.dot}`} />
                  <h3 className="text-2xl font-semibold tracking-tight">
                    {operation.name}
                  </h3>
                  <span className={`text-[14px] ${operation.tone}`}>
                    {operation.claim}
                  </span>
                </div>
                <p className="mt-4 leading-relaxed text-label-2">{operation.body}</p>
                <p className="mt-4 text-[15px] text-label-3">{operation.note}</p>
              </div>
            </Rise>
          ))}
        </div>
      </div>
    </section>
  );
}

const RULES: [string, string, boolean][] = [
  ["A process is working in it", "An open agent session, editor or dev server. This one also stops a sweep.", true],
  ["The main worktree", "A repository's own working copy is never removable.", true],
  ["Outside your folders", "Paths beyond the roots you configured are refused.", true],
  ["Uncommitted changes", "Modified and staged files are work that exists nowhere else yet.", false],
  ["Untracked files", "Something new that git has never seen is still yours.", false],
  ["Unpushed commits", "Work that has not reached a remote has no second copy.", false],
  ["Ahead of the default branch", "No upstream at all, and commits missing from main.", false],
  ["Gitignored config", "The .env.local case. Git calls the worktree clean and it is lying.", false],
  ["A locked worktree", "Someone ran git worktree lock. That was a deliberate act.", false],
  ["An operation in progress", "A half-finished rebase, merge, cherry-pick or bisect.", false],
  ["A dirty submodule", "Changes nested inside a submodule count as changes.", false],
];

function Rules() {
  return (
    <section id="rules" className="px-6 py-28">
      <div className="mx-auto max-w-6xl">
        <Rise>
          <h2 className="title-2 mx-auto max-w-[20ch] text-center text-[clamp(2rem,4.5vw,3.25rem)]">
            Eleven reasons it will stop you.
          </h2>
          <p className="mx-auto mt-6 max-w-[52ch] text-center text-lg text-label-2">
            Every one is recomputed at the moment of deletion, never trusted from
            the scan that built the list.
          </p>
        </Rise>

        <div className="mt-18 grid gap-x-16 gap-y-9 md:grid-cols-2">
          {RULES.map(([title, detail, absolute]) => (
            <Rise key={title}>
              <div className="flex gap-4">
                <svg
                  width="19"
                  height="19"
                  viewBox="0 0 24 24"
                  fill="none"
                  aria-hidden
                  className={`mt-0.5 shrink-0 ${absolute ? "text-red" : "text-orange"}`}
                >
                  <path
                    d="M7 10V7a5 5 0 0110 0v3"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                  />
                  <rect x="4" y="10" width="16" height="10" rx="2.5" fill="currentColor" />
                </svg>
                <div>
                  <h3 className="font-medium">{title}</h3>
                  <p className="mt-1.5 leading-relaxed text-label-2">{detail}</p>
                </div>
              </div>
            </Rise>
          ))}
        </div>

        <Rise>
          <div className="mx-auto mt-20 max-w-[64ch] text-center">
            <h3 className="text-xl font-semibold tracking-tight">
              Three refuse absolutely. The other eight are your call.
            </h3>
            <p className="mt-5 text-lg leading-relaxed text-label-2">
              A live process, the main worktree and the folder boundary corrupt
              something no confirmation can undo, so there is no button for them.
              The rest is your own work. Worktrees are scratch space, and refusing
              forever would make the tool useless on exactly the ones worth
              deleting, so each of those offers an override that states precisely
              what it destroys and shows whether the branch{"'"}s pull request has
              already merged.
            </p>
          </div>
        </Rise>
      </div>
    </section>
  );
}

const MEASURED = [
  ["0.0%", "CPU when idle"],
  ["99 MB", "memory"],
  ["3 s", "to judge 42 worktrees"],
  ["0", "dependencies"],
];

function Quiet() {
  return (
    <section className="px-6 py-28">
      <div className="mx-auto max-w-6xl">
        <Rise>
          <h2 className="title-2 mx-auto max-w-[19ch] text-center text-[clamp(2rem,4.5vw,3.25rem)]">
            It never polls, so it never costs you anything.
          </h2>
          <p className="mx-auto mt-7 max-w-[58ch] text-center text-lg text-label-2">
            A timer re-scanning 42 worktrees every minute would burn battery all day
            to learn nothing almost every time. Coppice watches with FSEvents, so
            the kernel wakes it only when a directory actually changes, and events
            coalesce so an install writing a hundred thousand files arrives as one
            callback.
          </p>
        </Rise>

        <div className="mt-16 grid gap-y-10 sm:grid-cols-2 lg:grid-cols-4">
          {MEASURED.map(([value, label]) => (
            <Rise key={label}>
              <div className="text-center">
                <div className="title-2 text-[clamp(2rem,4.5vw,3rem)]">{value}</div>
                <div className="mt-2 text-label-2">{label}</div>
              </div>
            </Rise>
          ))}
        </div>
      </div>
    </section>
  );
}

const REASONS = [
  [
    "Read the rules yourself",
    "The eleven conditions are one Swift file. You can read what counts as unsafe, disagree with it, and see the tests that build real git repositories to prove each one fires.",
  ],
  [
    "Judgment should be arguable",
    "Deciding which blockers can be overridden is a taste call, not a fact. Someone will find it too cautious and someone too loose. Both should be able to open an issue with the line number in hand.",
  ],
  [
    "MIT, so take what is useful",
    "Lift the verdict engine into your own tooling, vendor it, fork it, ship it commercially. No copyleft and no permission needed. The problem is not specific to this app.",
  ],
];

function OpenSource() {
  return (
    <section id="open" className="relative overflow-hidden px-6 py-32">
      <div
        aria-hidden
        className="drift pointer-events-none absolute inset-x-0 top-1/2 mx-auto h-[30rem] w-[60rem] -translate-y-1/2 rounded-full opacity-40 blur-[140px]"
        style={{
          background:
            "radial-gradient(closest-side, rgba(10,132,255,0.20), transparent)",
        }}
      />

      <div className="relative mx-auto max-w-6xl">
        <Rise>
          <h2 className="title-2 mx-auto max-w-[22ch] text-center text-[clamp(2rem,5vw,3.5rem)]">
            You are about to let software delete your work.
          </h2>
          <p className="mx-auto mt-8 max-w-[52ch] text-center text-xl text-label-2">
            There is one honest answer to why you should trust it, and it is not a
            promise on a landing page. It is the source.
          </p>
        </Rise>

        <div className="mt-20 grid gap-12 md:grid-cols-3 md:gap-10">
          {REASONS.map(([title, body]) => (
            <Rise key={title}>
              <div>
                <h3 className="text-lg font-semibold tracking-tight">{title}</h3>
                <p className="mt-3 leading-relaxed text-label-2">{body}</p>
              </div>
            </Rise>
          ))}
        </div>

        <Rise>
          <p className="mx-auto mt-16 max-w-[56ch] text-center text-label-3">
            It is also the only way this stays correct. Agent tools change their
            worktree layouts constantly, and the person who notices first is
            whoever it broke for.
          </p>
        </Rise>
      </div>
    </section>
  );
}

function Install() {
  return (
    <section id="install" className="px-6 py-28">
      <div className="mx-auto max-w-3xl">
        <Rise>
          <h2 className="title-2 text-center text-[clamp(2rem,4.5vw,3.25rem)]">
            Install
          </h2>
        </Rise>

        <div className="mt-14 space-y-10">
          <Rise>
            <div>
              <div className="flex items-baseline gap-3">
                <h3 className="text-lg font-semibold tracking-tight">Stable</h3>
                <span className="text-[14px] text-label-3">
                  installs clean, then updates itself
                </span>
              </div>
              <div className="mt-3">
                <CopyCommand command="brew install --cask rafay99-epic/apps/coppice" />
              </div>
            </div>
          </Rise>

          <Rise>
            <div>
              <div className="flex items-baseline gap-3">
                <h3 className="text-lg font-semibold tracking-tight">Nightly</h3>
                <span className="text-[14px] text-label-3">
                  runs beside Stable, own icon and settings
                </span>
              </div>
              <div className="mt-3">
                <CopyCommand command="brew install --cask rafay99-epic/apps/coppice-nightly" />
              </div>
            </div>
          </Rise>
        </div>

        <Rise>
          <p className="mt-12 text-center text-label-2">
            Prefer a direct download? The{" "}
            <a
              href={DMG}
              className="text-label underline decoration-label-3 underline-offset-4 transition-colors hover:decoration-green"
            >
              disk image
            </a>{" "}
            is not notarized, because there is no paid Apple Developer account
            behind it. Right click and choose Open the first time.
          </p>
        </Rise>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="px-6 py-12">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-5 text-[14px] text-label-3">
        <div className="flex items-center gap-2.5">
          <Mark size={16} />
          <span>Coppice. MIT licensed. Built by Syntax Lab Technology.</span>
        </div>
        <div className="flex gap-7">
          <a href={REPO} className="transition-colors hover:text-label">
            Source
          </a>
          <a href={`${REPO}/releases`} className="transition-colors hover:text-label">
            Releases
          </a>
          <a href={`${REPO}/issues`} className="transition-colors hover:text-label">
            Issues
          </a>
        </div>
      </div>
    </footer>
  );
}
