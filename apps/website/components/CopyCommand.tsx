"use client";

import { useState } from "react";

/** Install command with a copy button. */
export function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="flex items-center gap-3 rounded-md border border-hair bg-raise px-4 py-3 transition-colors hover:border-hair-2">
      <span aria-hidden className="select-none font-mono text-[13px] text-ink-4">
        $
      </span>
      <code className="flex-1 overflow-x-auto whitespace-nowrap font-mono text-[13px] text-ink">
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={`Copy: ${command}`}
        className="shrink-0 rounded px-2 py-1 font-mono text-[11px] text-ink-3 transition-colors hover:text-shoot focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-shoot"
      >
        {copied ? "copied" : "copy"}
      </button>
    </div>
  );
}
