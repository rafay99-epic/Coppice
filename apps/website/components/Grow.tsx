"use client";

import { useEffect } from "react";

export function Grow() {
  useEffect(() => {
    if (CSS.supports("animation-timeline: view()")) return;
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    const targets = document.querySelectorAll<HTMLElement>("[data-grow]");
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          (entry.target as HTMLElement).dataset.grow = "in";
          observer.unobserve(entry.target);
        }
      },
      { rootMargin: "0px 0px -15% 0px" },
    );

    for (const target of targets) {
      target.dataset.grow = "pending";
      observer.observe(target);
    }
    return () => observer.disconnect();
  }, []);

  return null;
}
