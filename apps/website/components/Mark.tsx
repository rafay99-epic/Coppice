export function Mark({ size = 20 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="#fff"
      strokeWidth={1.4}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      className="shrink-0"
    >
      <path d="M8.4 20.6C8.7 19.3 8.6 18 8.8 16.8M15.6 20.6C15.3 19.3 15.4 18 15.2 16.8M8.8 16.8C9.6 15.9 14.4 15.9 15.2 16.8C14.4 17.7 9.6 17.7 8.8 16.8M7.2 20.6H16.8" />
      <path d="M10.7 16.6C10.2 13 8.4 9.8 7.3 7.6M12 16.4C12.1 12.6 12 9.4 12.1 6.2M13.3 16.6C13.8 13 15.6 9.8 16.7 7.6" />
      <ellipse cx="6.6" cy="5.8" rx="0.85" ry="1.8" transform="rotate(-25 6.6 5.8)" />
      <ellipse cx="12.1" cy="4.2" rx="0.85" ry="1.8" />
      <ellipse cx="17.4" cy="5.8" rx="0.85" ry="1.8" transform="rotate(25 17.4 5.8)" />
    </svg>
  );
}
