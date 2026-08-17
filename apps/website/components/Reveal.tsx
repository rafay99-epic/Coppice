import type { ReactNode } from "react";

/**
 * Fades content up as it scrolls into view.
 *
 * No JavaScript. The motion comes from a CSS scroll-driven animation
 * (`animation-timeline: view()`), so there is no observer, no hydration, and no
 * client bundle for what is purely decoration.
 *
 * The important part is the failure mode. An `IntersectionObserver` version
 * starts every element at `opacity: 0` and depends on JS to reveal it, so if the
 * script fails, is blocked, or simply has not run yet, the page renders blank.
 * Here the hidden state only exists inside an `@supports` block, so a browser
 * without scroll-driven animations shows the content immediately.
 */
export function Reveal({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={`reveal ${className}`}>{children}</div>;
}
