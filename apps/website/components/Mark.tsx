/**
 * Three shoots regrowing from a cut stump. Same geometry as the app icon, so
 * the site and the Dock read as one thing.
 */
export function Mark({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" aria-hidden className="shrink-0">
      <rect x="10.6" y="14.5" width="2.8" height="6" rx="1.4" fill="#3ddc84" opacity="0.28" />
      <rect x="5.2" y="8.4" width="2.6" height="7" rx="1.3" fill="#3ddc84" opacity="0.55" />
      <rect x="10.7" y="4.6" width="2.6" height="10.8" rx="1.3" fill="#3ddc84" />
      <rect x="16.2" y="6.9" width="2.6" height="8.5" rx="1.3" fill="#3ddc84" opacity="0.76" />
      <rect x="3.4" y="13.6" width="17.2" height="2.5" rx="1.25" fill="#3ddc84" />
    </svg>
  );
}
