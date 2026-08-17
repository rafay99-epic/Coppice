import type { ReactNode } from "react";

/**
 * Fades content up as it enters the viewport.
 *
 * No JavaScript. The motion is a CSS scroll-driven animation, so it runs on the
 * compositor while the user scrolls and costs nothing when they stop. No
 * observer, no hydration, no animation loop idling in the background.
 *
 * The failure mode is the point. An IntersectionObserver version starts every
 * element at opacity 0 and needs script to reveal it, so a blocked or slow
 * script renders a blank page. Here the hidden state only exists inside an
 * `@supports` block, so a browser without scroll-driven animations shows the
 * content immediately.
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
