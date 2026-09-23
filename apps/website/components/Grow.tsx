"use client";

import { useEffect } from "react";

export function Grow() {
  useEffect(() => {
    document.documentElement.dataset.motion = "ready";
    const targets = document.querySelectorAll<HTMLElement>("[data-grow]:not([data-grow='in'])");
    const observer = new IntersectionObserver(
      (entries) => {
        entries
          .filter((entry) => entry.isIntersecting)
          .forEach((entry, index) => {
            const target = entry.target as HTMLElement;
            target.style.setProperty("--stagger", `${Math.min(index, 4) * 70}ms`);
            target.dataset.grow = "in";
            observer.unobserve(target);
          });
      },
      { rootMargin: "0px 0px -12% 0px" },
    );
    targets.forEach((target) => observer.observe(target));
    return () => observer.disconnect();
  }, []);

  return null;
}
