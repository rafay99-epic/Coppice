"use client";

import { useState } from "react";

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
    <div className="flex min-w-0 items-center gap-3 border-b border-line py-3 transition-colors hover:border-label-3">
      <code className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap text-[14px] text-label-2">
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={`Copy: ${command}`}
        className={`shrink-0 rounded-full px-3.5 py-1 text-[13px] font-medium transition-colors duration-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white ${
          copied ? "bg-white text-black" : "bg-surface-3 text-label hover:bg-label-3"
        }`}
      >
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}
