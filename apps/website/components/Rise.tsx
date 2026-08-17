import type { ReactNode } from "react";

/**
 * Fades content up as it enters the viewport.
 *
 * No JavaScript. The motion is a CSS scroll-driven animation, so there is no
 * observer, no hydration and no client bundle for what is purely decoration.
 *
 * The failure mode is what matters. An IntersectionObserver version starts
 * every element at opacity 0 and needs script to reveal it, so a blocked or
 * slow script renders a blank page. Here the hidden state only exists inside
 * an `@supports` block, so a browser without scroll-driven animations shows
 * the content immediately.
 */
export function Rise({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={`rise ${className}`}>{children}</div>;
}
