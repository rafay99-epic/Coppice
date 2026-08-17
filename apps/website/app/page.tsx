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
        <Evidence />
        <Danger />
        <Operations />
        <Rules />
        <Engineering />
        <OpenSource />
        <Install />
      </main>
      <Footer />
    </>
  );
}

/* ---------------------------------------------------------------- chrome */

function Nav() {
  return (
    <nav className="sticky top-0 z-50 border-b border-hair bg-black/80 backdrop-blur-xl">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <a href="#top" className="flex items-center gap-2.5">
          <Mark size={18} />
          <span className="font-medium tracking-tight">Coppice</span>
        </a>
        <div className="flex items-center gap-6 text-[13px] text-ink-3">
          <a href="#rules" className="transition-colors hover:text-ink">
            Safety
          </a>
          <a href="#open" className="hidden transition-colors hover:text-ink sm:block">
            Open source
          </a>
          <a href="#install" className="transition-colors hover:text-ink">
            Install
          </a>
          <a href={REPO} className="transition-colors hover:text-ink">
            GitHub
          </a>
        </div>
      </div>
    </nav>
  );
}

/* ------------------------------------------------- 1. full-bleed hero */

function Hero() {
  return (
    <section id="top" className="mx-auto max-w-6xl px-6 pt-24 pb-24 sm:pt-36">
      <Rise>
        <h1 className="display max-w-[19ch] text-[clamp(2.75rem,8vw,6.5rem)]">
          Your agents leave
          <br />
          the mess behind.
        </h1>
        <p className="mt-8 max-w-[46ch] text-lg text-ink-2 sm:text-xl">
          Every task gets its own git worktree. None of them get cleaned up. On the
          machine this was built against that is 42 worktrees and 76 GB, most of it
          the same dependency folder copied over and over.
        </p>
      </Rise>

      <Rise>
        <div className="mt-10 flex max-w-lg flex-col gap-4">
          <CopyCommand command="brew install --cask rafay99-epic/apps/coppice" />
          <div className="flex flex-wrap items-center gap-x-5 gap-y-3 text-[13px]">
            <a
              href={DMG}
              className="rounded-md bg-ink px-4 py-2 font-medium text-black transition-opacity hover:opacity-80"
            >
              Download for macOS
            </a>
            <a href={REPO} className="text-ink-2 underline-offset-4 transition-colors hover:text-ink hover:underline">
              Read every line of it
            </a>
            <span className="text-ink-4">MIT. Apple Silicon.</span>
          </div>
        </div>
      </Rise>

      <Rise>
        <div className="mt-20">
          <AppMock />
        </div>
      </Rise>
    </section>
  );
}

/* ------------------------------------------- 2. dense typographic index */

const NUMBERS = [
  ["42", "worktrees", "across 23 repositories, made by four different agents"],
  ["76 GB", "on disk", "the largest single worktree was 6.18 GB on its own"],
  ["37", "protected", "held work that existed nowhere else at the time of the scan"],
  ["3 s", "to judge them all", "inventory and verdict for every worktree, from cold"],
];

function Evidence() {
  return (
    <section className="border-t border-hair">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <Rise>
          <h2 className="display-sm max-w-[16ch] text-[clamp(1.75rem,4vw,3rem)]">
            This is one laptop, on an ordinary Tuesday.
          </h2>
        </Rise>

        <div className="mt-14">
          {NUMBERS.map(([value, label, note]) => (
            <Rise key={label}>
              <div className="grid grid-cols-1 items-baseline gap-2 border-b border-hair py-6 sm:grid-cols-[9rem_1fr] sm:gap-8 md:grid-cols-[11rem_10rem_1fr]">
                <div className="display-sm tnum text-[clamp(1.75rem,4vw,2.75rem)]">
                  {value}
                </div>
                <div className="text-ink-2">{label}</div>
                <div className="max-w-[52ch] text-[15px] text-ink-3">{note}</div>
              </div>
            </Rise>
          ))}
        </div>

        <Rise>
          <p className="mt-10 max-w-[62ch] text-lg text-ink-2">
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

/* ---------------------------------------- 3. editorial stack, narrow measure */

function Danger() {
  return (
    <section className="border-t border-hair bg-raise">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <div className="mx-auto max-w-[64ch]">
          <Rise>
            <h2 className="display-sm text-[clamp(1.75rem,4vw,3rem)]">
              So why not just delete them?
            </h2>
            <p className="mt-7 text-lg leading-relaxed text-ink-2">
              Because the obvious version of this tool destroys your work.
            </p>
            <p className="mt-5 leading-relaxed text-ink-2">
              A script that finds old worktrees and removes the clean ones sounds
              safe. It asks git whether the directory is clean, git says yes, the
              directory goes. That is the whole idea, and it is wrong in a way you
              only discover afterwards.
            </p>
          </Rise>

          <Rise>
            <figure className="my-10 border-y border-hair py-8">
              <p className="text-[15px] text-ink-3">A worktree holding this file</p>
              <p className="mt-3 font-mono text-xl text-alarm sm:text-2xl">
                .env.local
              </p>
              <p className="mt-3 text-[15px] text-ink-3">
                reports as perfectly clean, because it is gitignored. Git has never
                seen it and has no copy of it. Neither does your remote.
              </p>
            </figure>
          </Rise>

          <Rise>
            <p className="leading-relaxed text-ink-2">
              Delete that worktree and the secrets are gone. Not recoverable from a
              branch, not on the remote, not in a stash. The single check that would
              have caught it is the one check a naive cleaner does not think to make,
              and you find out when something stops authenticating.
            </p>
            <p className="mt-5 leading-relaxed text-ink-2">
              Coppice exists because the careful version of this is genuinely
              fiddly. Eleven separate conditions decide whether a worktree is safe,
              and every one of them has to be rechecked at the instant of deletion.
              A background scanner's verdict is minutes old by the time you press a
              button, and in those minutes an agent can open the very worktree you
              picked.
            </p>
          </Rise>
        </div>
      </div>
    </section>
  );
}

/* ---------------------------------------------- 4. bento, unequal weights */

function Operations() {
  return (
    <section id="how" className="border-t border-hair">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <Rise>
          <h2 className="display-sm max-w-[20ch] text-[clamp(1.75rem,4vw,3rem)]">
            Three operations, priced by what they cost you.
          </h2>
        </Rise>

        <div className="mt-14 grid gap-px overflow-hidden rounded-xl border border-hair bg-hair md:grid-cols-3">
          {/* The hero tile. Sweep is what people actually use, so it gets the
              width, the number and the accent. Equal cards would flatten that. */}
          <Rise className="md:col-span-2">
            <div className="flex h-full flex-col justify-between gap-8 bg-page p-8 sm:p-10">
              <div>
                <div className="flex items-baseline gap-3">
                  <h3 className="text-2xl font-medium tracking-tight">Sweep</h3>
                  <span className="text-[13px] text-shoot">Reversible</span>
                </div>
                <p className="mt-4 max-w-[48ch] text-ink-2">
                  Deletes build output inside worktrees. <Code>node_modules</Code>,{" "}
                  <Code>.next</Code>, <Code>target</Code>, <Code>DerivedData</Code>.
                  Source, git history and local config are never touched.
                </p>
                <p className="mt-4 max-w-[48ch] text-[15px] text-ink-3">
                  It runs on dirty worktrees too, because a dependency folder is not
                  your work. The undo is the install command you already type.
                </p>
              </div>
              <div className="flex items-baseline gap-3">
                <span className="display-sm tnum text-[clamp(2rem,5vw,3.5rem)] text-shoot">
                  22 GB
                </span>
                <span className="text-[15px] text-ink-3">freed on the first run</span>
              </div>
            </div>
          </Rise>

          <Rise>
            <div className="flex h-full flex-col gap-8 bg-page p-8">
              <div>
                <h3 className="text-lg font-medium tracking-tight">Prune</h3>
                <p className="mt-3 text-[15px] text-ink-3">
                  Clears git metadata for worktrees whose directories are already
                  gone. Git considers these dead, so nothing on disk is touched.
                </p>
              </div>
              <div className="mt-auto border-t border-hair pt-6">
                <h3 className="text-lg font-medium tracking-tight">Remove</h3>
                <p className="mt-3 text-[15px] text-ink-3">
                  Deletes the worktree itself. Typed confirmation, one at a time.
                  There is no Remove All anywhere in the app, on purpose.
                </p>
              </div>
            </div>
          </Rise>
        </div>
      </div>
    </section>
  );
}

/* ------------------------------------------------ 5. numbered dense index */

const RULES: [string, string][] = [
  ["A process is working in it", "An open agent session, editor or dev server. This one also stops a sweep."],
  ["Uncommitted changes", "Modified and staged files are work that exists nowhere else yet."],
  ["Untracked files", "Something new that git has never seen is still yours."],
  ["Unpushed commits", "Work that has not reached a remote has no second copy."],
  ["Ahead of the default branch", "No upstream at all, and commits missing from main."],
  ["Gitignored config", "The .env.local case. Git calls the worktree clean and it is lying."],
  ["A locked worktree", "Someone ran git worktree lock. That was a deliberate act."],
  ["An operation in progress", "A half-finished rebase, merge, cherry-pick or bisect."],
  ["A dirty submodule", "Changes nested inside a submodule count as changes."],
  ["Outside your folders", "Paths beyond the roots you configured are refused."],
  ["The main worktree", "A repository's own working copy is never removable."],
];

function Rules() {
  return (
    <section id="rules" className="border-t border-hair bg-raise">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <Rise>
          <div className="flex flex-col justify-between gap-6 md:flex-row md:items-end">
            <h2 className="display-sm max-w-[18ch] text-[clamp(1.75rem,4vw,3rem)]">
              Eleven reasons it will stop you.
            </h2>
            <p className="max-w-[42ch] text-[15px] text-ink-3">
              Each one is recomputed at the moment of deletion, never trusted from
              the scan that built the list.
            </p>
          </div>
        </Rise>

        <ol className="mt-14 border-t border-hair">
          {RULES.map(([title, detail], index) => (
            <Rise key={title}>
              <li className="grid grid-cols-[2rem_1fr] items-baseline gap-x-5 gap-y-1 border-b border-hair py-5 md:grid-cols-[2rem_22rem_1fr]">
                <span className="tnum text-[13px] text-ink-4">
                  {String(index + 1).padStart(2, "0")}
                </span>
                <span className="text-ink">{title}</span>
                <span className="col-start-2 max-w-[54ch] text-[15px] text-ink-3 md:col-start-3">
                  {detail}
                </span>
              </li>
            </Rise>
          ))}
        </ol>

        <Rise>
          <div className="mt-12 grid gap-10 md:grid-cols-2">
            <div>
              <h3 className="font-medium">Three of them are absolute.</h3>
              <p className="mt-3 max-w-[52ch] text-[15px] text-ink-3">
                A live process, the main worktree, and the folder boundary. Forcing
                past any of those corrupts something no confirmation can undo, so
                there is no button for it.
              </p>
            </div>
            <div>
              <h3 className="font-medium">The other eight are your call.</h3>
              <p className="mt-3 max-w-[52ch] text-[15px] text-ink-3">
                Worktrees are scratch space. Refusing forever would make the tool
                useless on exactly the ones worth deleting, so the rest offer an
                override that states precisely what it destroys, and shows whether
                the branch{"'"}s pull request is already merged.
              </p>
            </div>
          </div>
        </Rise>
      </div>
    </section>
  );
}

/* ------------------------------------------------- 6. asymmetric split */

const MEASURED = [
  ["Idle CPU", "0.0%"],
  ["Memory", "99 MB"],
  ["Installer", "1.3 MB"],
  ["Dependencies", "0"],
];

function Engineering() {
  return (
    <section className="border-t border-hair">
      <div className="mx-auto grid max-w-6xl gap-14 px-6 py-24 md:grid-cols-12">
        <div className="md:col-span-7">
          <Rise>
            <h2 className="display-sm max-w-[18ch] text-[clamp(1.75rem,4vw,3rem)]">
              It never polls, so it never costs you anything.
            </h2>
            <p className="mt-7 max-w-[54ch] text-lg text-ink-2">
              A timer re-scanning 42 worktrees every minute would burn battery all
              day to learn nothing almost every time. Coppice watches with FSEvents,
              so the kernel wakes it only when a directory actually changes.
            </p>
            <p className="mt-5 max-w-[54ch] text-ink-3">
              Events coalesce inside the kernel, so an install writing a hundred
              thousand files arrives as one callback rather than a hundred thousand.
              Size walks run at background priority and stop at the first artifact
              directory instead of descending into it.
            </p>
          </Rise>
        </div>

        <div className="md:col-span-5">
          <Rise>
            <dl className="border-t border-hair">
              {MEASURED.map(([label, value]) => (
                <div
                  key={label}
                  className="flex items-baseline justify-between border-b border-hair py-4"
                >
                  <dt className="text-ink-3">{label}</dt>
                  <dd className="tnum text-xl font-medium">{value}</dd>
                </div>
              ))}
            </dl>
            <p className="mt-4 text-[13px] text-ink-4">
              Measured after walking 76 GB across 42 worktrees, sitting idle.
            </p>
          </Rise>
        </div>
      </div>
    </section>
  );
}

/* --------------------------------------------- 7. marquee band, rhythm reset */

function OpenSource() {
  return (
    <section id="open" className="border-t border-hair bg-raise-2">
      <div className="mx-auto max-w-6xl px-6 py-28">
        <Rise>
          <h2 className="display-sm max-w-[24ch] text-[clamp(1.75rem,4.5vw,3.25rem)]">
            You are about to let software delete your work.
          </h2>
          <p className="mt-8 max-w-[58ch] text-xl text-ink-2">
            There is exactly one honest answer to why you should trust it, and it is
            not a promise on a landing page. It is the source.
          </p>
        </Rise>

        <div className="mt-16 grid gap-12 md:grid-cols-3">
          <Rise>
            <h3 className="font-medium">Read the rules yourself</h3>
            <p className="mt-3 text-[15px] leading-relaxed text-ink-3">
              The eleven conditions above are one Swift file. You can read what
              counts as unsafe, disagree with it, and see the tests that build real
              git repositories to prove each one fires.
            </p>
          </Rise>
          <Rise>
            <h3 className="font-medium">Judgment should be arguable</h3>
            <p className="mt-3 text-[15px] leading-relaxed text-ink-3">
              Deciding which blockers can be overridden is a taste call, not a fact.
              Someone will think it is too cautious and someone too loose. Both need
              to be able to open an issue with the line number in hand.
            </p>
          </Rise>
          <Rise>
            <h3 className="font-medium">MIT, so take what is useful</h3>
            <p className="mt-3 text-[15px] leading-relaxed text-ink-3">
              Lift the verdict engine into your own tooling, vendor it, fork it, ship
              it commercially. No copyleft, no permission needed. The problem is not
              specific to this app and the answer should not be locked inside it.
            </p>
          </Rise>
        </div>

        <Rise>
          <p className="mt-16 max-w-[62ch] text-ink-3">
            It is also the only way this stays correct. Agent tools change their
            worktree layouts constantly, and the person who notices first is whoever
            it broke for.
          </p>
        </Rise>
      </div>
    </section>
  );
}

/* --------------------------------------------------------- 8. install */

function Install() {
  return (
    <section id="install" className="border-t border-hair">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <Rise>
          <h2 className="display-sm text-[clamp(1.75rem,4vw,3rem)]">Install</h2>
        </Rise>

        <div className="mt-12 grid gap-10 md:grid-cols-2">
          <Rise>
            <div className="flex items-baseline justify-between">
              <h3 className="font-medium">Stable</h3>
              <span className="text-[13px] text-ink-4">cut weekly</span>
            </div>
            <p className="mt-2 mb-4 text-[15px] text-ink-3">
              Installs with no security prompt, then updates itself.
            </p>
            <CopyCommand command="brew install --cask rafay99-epic/apps/coppice" />
          </Rise>

          <Rise>
            <div className="flex items-baseline justify-between">
              <h3 className="font-medium">Nightly</h3>
              <span className="text-[13px] text-ink-4">side by side</span>
            </div>
            <p className="mt-2 mb-4 text-[15px] text-ink-3">
              Separate app, icon and settings. Does not disturb Stable.
            </p>
            <CopyCommand command="brew install --cask rafay99-epic/apps/coppice-nightly" />
          </Rise>
        </div>

        <Rise>
          <p className="mt-10 max-w-[64ch] text-[15px] text-ink-3">
            Prefer a direct download? The{" "}
            <a href={DMG} className="text-ink underline decoration-hair-2 underline-offset-4 transition-colors hover:decoration-shoot">
              disk image
            </a>{" "}
            is not notarized, because there is no paid Apple Developer account behind
            it. Right click and choose Open the first time. Requires macOS 15 or
            newer on Apple Silicon.
          </p>
        </Rise>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="border-t border-hair">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-6 py-10 text-[13px] text-ink-4">
        <div className="flex items-center gap-2.5">
          <Mark size={15} />
          <span>Coppice. MIT licensed. Built by Syntax Lab Technology.</span>
        </div>
        <div className="flex gap-6">
          <a href={REPO} className="transition-colors hover:text-ink">
            Source
          </a>
          <a href={`${REPO}/releases`} className="transition-colors hover:text-ink">
            Releases
          </a>
          <a href={`${REPO}/issues`} className="transition-colors hover:text-ink">
            Issues
          </a>
        </div>
      </div>
    </footer>
  );
}

function Code({ children }: { children: React.ReactNode }) {
  return (
    <code className="rounded border border-hair bg-raise-2 px-1.5 py-0.5 font-mono text-[0.85em] text-ink-2">
      {children}
    </code>
  );
}
