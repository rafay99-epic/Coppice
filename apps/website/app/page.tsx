import type { ReactNode } from "react";
import { AppMock } from "@/components/AppMock";
import { CopyCommand } from "@/components/CopyCommand";
import { Mark } from "@/components/Mark";
import { Sprout, Tree } from "@/components/Tree";

const REPO = "https://github.com/rafay99-epic/Coppice";
const DMG = `${REPO}/releases/latest/download/Coppice.dmg`;

export default function Home() {
  return (
    <>
      <Nav />
      <main className="relative">
        <Hero />
        <div className="relative mx-auto max-w-6xl">
          <div
            aria-hidden
            className="spine absolute top-0 bottom-0 left-4 hidden w-px bg-line sm:left-6 lg:block"
          />
          <Mess />
          <Ways />
          <Never />
          <Quiet />
          <Install />
        </div>
      </main>
      <Footer />
    </>
  );
}

function Nav() {
  return (
    <nav className="mx-auto flex max-w-6xl items-center justify-between px-4 py-5 sm:px-6">
      <a href="#top" className="flex items-center gap-2.5">
        <Mark size={18} />
        <span className="font-semibold">Coppice</span>
      </a>
      <div className="flex items-center gap-6 text-[14px] text-label-2">
        <a href="#never" className="link hidden hover:text-label sm:inline">
          Safety
        </a>
        <a href={REPO} className="link hover:text-label">
          GitHub
        </a>
        <a href="#install" className="link text-label">
          Install
        </a>
      </div>
    </nav>
  );
}

function Hero() {
  return (
    <section id="top" className="mx-auto max-w-6xl px-4 pt-10 pb-24 sm:px-6 sm:pt-20">
      <div className="grid items-end gap-10 lg:grid-cols-[1.1fr_1fr]">
        <div className="min-w-0">
          <h1 className="display intro text-[clamp(3rem,9vw,6.5rem)]">
            Cut it back.
            <br />
            <em>It grows again.</em>
          </h1>
          <p
            className="intro mt-8 max-w-[40ch] text-[19px] leading-relaxed text-label-2"
            style={{ "--i": "0.25s" } as React.CSSProperties}
          >
            Your coding agents make a git worktree for every task and never clean up.
            Coppice finds them, frees the space and leaves your work alone.
          </p>
          <div className="intro mt-10 max-w-md" style={{ "--i": "0.45s" } as React.CSSProperties}>
            <div className="flex flex-wrap items-center gap-x-6 gap-y-4">
              <a
                href={DMG}
                className="rounded-full bg-white px-6 py-2.5 font-medium text-black transition-transform duration-200 hover:-translate-y-0.5"
              >
                Download for macOS
              </a>
              <a href={REPO} className="link text-label-2 hover:text-label">
                View source
              </a>
            </div>
            <div className="mt-6">
              <CopyCommand command="brew install --cask rafay99-epic/apps/coppice" />
            </div>
            <p className="mt-3 text-[13px] text-label-3">
              Free and MIT licensed. macOS 15 on Apple Silicon.
            </p>
          </div>
        </div>
        <Tree className="mx-auto w-full max-w-[34rem]" />
      </div>
    </section>
  );
}

function Section({
  id,
  variant,
  title,
  children,
}: {
  id?: string;
  variant: number;
  title: ReactNode;
  children: ReactNode;
}) {
  return (
    <section id={id} className="px-4 py-20 sm:px-6 sm:py-28 lg:grid lg:grid-cols-[7rem_1fr] lg:gap-6">
      <div className="hidden lg:block">
        <Sprout variant={variant} />
      </div>
      <div className="min-w-0">
        <h2 className="display reveal text-[clamp(2.25rem,5.5vw,4rem)]" data-grow>
          {title}
        </h2>
        <div className="mt-12">{children}</div>
      </div>
    </section>
  );
}

const MESS = [
  ["42", "worktrees"],
  ["76 GB", "on disk"],
  ["22 GB", "safe to free"],
] as const;

function Mess() {
  return (
    <Section
      variant={0}
      title={
        <>
          One laptop. <em>An ordinary Tuesday.</em>
        </>
      }
    >
      <div className="grid gap-10 sm:grid-cols-3">
        {MESS.map(([value, label]) => (
          <div key={label} className="reveal border-t border-line pt-5" data-grow>
            <div className="display text-[clamp(3rem,7vw,4.75rem)]">{value}</div>
            <div className="mt-2 text-label-2">{label}</div>
          </div>
        ))}
      </div>
      <p className="reveal mt-14 max-w-[56ch] text-[18px] leading-relaxed text-label-2" data-grow>
        You try something in a worktree, the branch merges, the folder stays. Run four
        agents at once and the disk fills with work you already finished.
      </p>
      <div className="reveal mt-16" data-grow>
        <AppMock />
      </div>
    </Section>
  );
}

const WAYS = [
  [
    "Sweep",
    "Deletes node_modules, .next, target and other build output. Your code and history stay. One install brings it back.",
  ],
  [
    "Remove",
    "Moves the whole worktree to the Trash. Commits stay on the branch, and .env files are copied out first.",
  ],
] as const;

function Ways() {
  return (
    <Section
      variant={1}
      title={
        <>
          Two ways <em>back.</em>
        </>
      }
    >
      <div className="divide-y divide-line border-y border-line">
        {WAYS.map(([name, text]) => (
          <div key={name} className="reveal grid gap-3 py-8 sm:grid-cols-[12rem_1fr]" data-grow>
            <div className="display text-[32px]">{name}</div>
            <p className="max-w-[52ch] text-[18px] leading-relaxed text-label-2">{text}</p>
          </div>
        ))}
      </div>
    </Section>
  );
}

const NEVER = [
  "A worktree an agent is using right now.",
  "Your repository's main checkout.",
  "Anything outside the folders you chose.",
];

function Never() {
  return (
    <Section
      id="never"
      variant={2}
      title={
        <>
          Three things it <em>won&apos;t</em> touch.
        </>
      }
    >
      <ol className="space-y-6">
        {NEVER.map((item, index) => (
          <li key={item} className="reveal flex items-baseline gap-6" data-grow>
            <span className="display w-8 shrink-0 text-[28px] text-label-3">{index + 1}</span>
            <span className="text-[clamp(1.25rem,2.6vw,1.75rem)] leading-snug">{item}</span>
          </li>
        ))}
      </ol>
      <p className="reveal mt-12 max-w-[52ch] text-[17px] text-label-2" data-grow>
        Every check runs again the moment you click, not when the list was built.
      </p>
    </Section>
  );
}

const QUIET = [
  ["Menu bar", "No Dock icon, no window until you want one."],
  ["Event driven", "Wakes when git changes a worktree. Never polls. 0% CPU at idle."],
  ["Hands off", "Nothing is deleted unless you click."],
] as const;

function Quiet() {
  return (
    <Section
      variant={3}
      title={
        <>
          Quiet <em>by design.</em>
        </>
      }
    >
      <div className="grid gap-10 sm:grid-cols-3">
        {QUIET.map(([name, text]) => (
          <div key={name} className="reveal" data-grow>
            <div className="font-semibold">{name}</div>
            <p className="mt-2 text-label-2">{text}</p>
          </div>
        ))}
      </div>
    </Section>
  );
}

function Install() {
  return (
    <Section
      id="install"
      variant={4}
      title={
        <>
          Plant it <em>once.</em>
        </>
      }
    >
      <div className="max-w-2xl space-y-10">
        <div className="reveal" data-grow>
          <div className="mb-1 text-[14px] text-label-3">Stable</div>
          <CopyCommand command="brew install --cask rafay99-epic/apps/coppice" />
        </div>
        <div className="reveal" data-grow>
          <div className="mb-1 text-[14px] text-label-3">Nightly, installs alongside Stable</div>
          <CopyCommand command="brew install --cask rafay99-epic/apps/coppice-nightly" />
        </div>
        <p className="reveal text-label-2" data-grow>
          Or grab the{" "}
          <a href={DMG} className="link text-label">
            .dmg
          </a>
          . It is not notarized, so right-click and choose Open the first time. Coppice
          updates itself after that.
        </p>
        <p className="reveal text-label-2" data-grow>
          Open source under MIT. Read every rule it follows on{" "}
          <a href={REPO} className="link text-label">
            GitHub
          </a>
          .
        </p>
      </div>
    </Section>
  );
}

function Footer() {
  return (
    <footer className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 border-t border-line px-4 py-10 text-[14px] text-label-3 sm:px-6">
      <div className="flex items-center gap-2.5">
        <Mark size={16} />
        <span>Coppice. MIT, Syntax Lab Technology.</span>
      </div>
      <div className="flex gap-6">
        <a href={REPO} className="link hover:text-label">
          Source
        </a>
        <a href={`${REPO}/releases`} className="link hover:text-label">
          Releases
        </a>
        <a href={`${REPO}/issues`} className="link hover:text-label">
          Issues
        </a>
      </div>
    </footer>
  );
}
