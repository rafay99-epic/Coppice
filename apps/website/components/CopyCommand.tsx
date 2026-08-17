"use client";

import { useState } from "react";

/** Install command with a copy button. Falls back to selecting nothing loudly. */
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
    <div className="flex items-center gap-3 rounded-lg border border-line bg-panel px-4 py-3 transition-colors hover:border-line-strong">
      <span aria-hidden className="select-none font-mono text-sm text-faint">
        $
      </span>
      <code className="flex-1 overflow-x-auto whitespace-nowrap font-mono text-sm text-fg">
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={`Copy: ${command}`}
        className="shrink-0 rounded-md border border-line-strong px-2.5 py-1 font-mono text-[11px] text-dim transition-colors hover:border-shoot hover:text-shoot focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-shoot"
      >
        {copied ? "copied" : "copy"}
      </button>
    </div>
  );
}
