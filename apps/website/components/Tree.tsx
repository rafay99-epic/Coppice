type Stroke = { d: string; delay: number; dead?: boolean; faint?: boolean };

const STUMP: Stroke[] = [
  { d: "M40 470 L560 470", delay: 0, faint: true },
  { d: "M252 470 C254 444 251 420 248 398", delay: 0.2 },
  { d: "M348 470 C346 444 349 420 352 398", delay: 0.2 },
  { d: "M248 398 C262 384 338 384 352 398 C338 412 262 412 248 398", delay: 0.5 },
  { d: "M276 398 C288 391 312 391 324 398 C312 405 288 405 276 398", delay: 0.7, faint: true },
];

const SHOOTS: Stroke[] = [
  { d: "M272 394 C262 320 214 250 190 128", delay: 1.0 },
  { d: "M300 390 C302 300 296 180 304 58", delay: 1.1 },
  { d: "M330 394 C348 320 398 240 428 112", delay: 1.2 },
  { d: "M286 392 C278 340 252 300 236 230", delay: 1.35 },
  { d: "M318 392 C330 330 350 300 372 250", delay: 1.25, dead: true },
  { d: "M262 396 C236 350 200 320 150 292", delay: 1.4, dead: true },
];

const LEAVES: Stroke[] = [
  { d: "M190 128 C176 112 178 92 192 80 C204 96 202 114 190 128", delay: 2.0 },
  { d: "M205 196 C186 192 176 176 180 160 C198 164 206 180 205 196", delay: 2.1 },
  { d: "M304 58 C292 44 294 26 306 16 C318 30 316 46 304 58", delay: 2.05 },
  { d: "M300 150 C318 144 332 150 338 164 C320 170 306 164 300 150", delay: 2.2 },
  { d: "M428 112 C440 96 458 92 470 98 C462 114 444 120 428 112", delay: 2.15 },
  { d: "M404 176 C388 166 384 150 390 138 C404 146 408 162 404 176", delay: 2.25 },
  { d: "M236 230 C220 222 214 206 220 194 C234 202 240 216 236 230", delay: 2.3 },
];

function paths(strokes: Stroke[]) {
  return strokes.map(({ d, delay, dead, faint }) => (
    <path
      key={d}
      d={d}
      pathLength={1}
      className={dead ? "dead" : faint ? "faint" : undefined}
      style={{ "--d": `${delay}s` } as React.CSSProperties}
    />
  ));
}

export function Tree({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 600 490"
      className={`line-art hero-tree ${className}`}
      role="img"
      aria-label="A coppiced stump with new shoots growing from it"
    >
      {paths(STUMP)}
      {paths(SHOOTS)}
      {paths(LEAVES)}
    </svg>
  );
}

const SPROUTS: Stroke[][] = [
  [
    { d: "M0 118 C30 112 52 92 64 52", delay: 0 },
    { d: "M64 52 C56 36 60 20 72 12 C80 28 76 44 64 52", delay: 0.25 },
    { d: "M34 104 C48 108 60 118 62 130", delay: 0.1, dead: true },
  ],
  [
    { d: "M0 118 C40 116 70 96 86 70", delay: 0 },
    { d: "M86 70 C98 58 114 56 124 62 C116 76 100 80 86 70", delay: 0.25 },
    { d: "M46 110 C52 90 50 72 42 58", delay: 0.12 },
    { d: "M42 58 C30 50 26 36 30 26 C42 32 46 46 42 58", delay: 0.35 },
  ],
  [
    { d: "M0 118 C22 104 36 80 40 40", delay: 0 },
    { d: "M40 40 C30 26 32 10 44 2 C54 16 52 32 40 40", delay: 0.25 },
    { d: "M24 100 C46 96 66 100 84 90", delay: 0.12, dead: true },
    { d: "M36 70 C54 64 70 52 76 36", delay: 0.18 },
  ],
  [
    { d: "M0 118 C36 118 64 104 80 84", delay: 0 },
    { d: "M80 84 C84 66 98 56 110 56 C108 72 96 84 80 84", delay: 0.25 },
    { d: "M40 112 C44 94 40 80 30 70", delay: 0.12, dead: true },
  ],
  [
    { d: "M0 118 C28 110 48 88 58 60", delay: 0 },
    { d: "M58 60 C48 46 50 28 62 20 C72 36 70 52 58 60", delay: 0.25 },
    { d: "M50 82 C68 80 84 70 92 54", delay: 0.15 },
    { d: "M92 54 C104 46 118 46 126 54 C116 64 102 64 92 54", delay: 0.38 },
  ],
];

export function Sprout({ variant }: { variant: number }) {
  return (
    <svg viewBox="0 0 130 130" className="line-art sprout h-20 w-20" aria-hidden data-grow>
      {paths(SPROUTS[variant % SPROUTS.length])}
    </svg>
  );
}
