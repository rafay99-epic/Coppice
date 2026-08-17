"use client";

import { useState } from "react";

/**
 * The install command. Styled as a soft macOS field rather than a terminal
 * block: no prompt glyph, no green-on-black, just the text you need to copy.
 */
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
    <div className="flex items-center gap-4 rounded-2xl bg-surface px-5 py-4 transition-colors hover:bg-surface-2">
      <code className="flex-1 overflow-x-auto whitespace-nowrap text-[15px] text-label">
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={`Copy: ${command}`}
        className={`shrink-0 rounded-full px-4 py-1.5 text-[14px] font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-green ${
          copied ? "bg-green text-black" : "bg-surface-2 text-label hover:bg-surface-3"
        }`}
      >
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}
