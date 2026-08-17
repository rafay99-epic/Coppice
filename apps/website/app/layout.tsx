import type { Metadata, Viewport } from "next";
import "./globals.css";

const description =
  "Coppice finds every worktree your coding agents left behind, works out which are safe to touch, and reclaims the space without eating uncommitted work or live sessions.";

export const metadata: Metadata = {
  metadataBase: new URL("https://coppice.rafay99.com"),
  title: "Coppice — cut agent worktrees back so they grow again",
  description,
  keywords: [
    "git worktree",
    "macOS",
    "developer tools",
    "node_modules",
    "Claude Code",
    "Codex",
    "disk cleanup",
  ],
  openGraph: {
    title: "Coppice",
    description,
    type: "website",
    siteName: "Coppice",
  },
  twitter: { card: "summary_large_image", title: "Coppice", description },
  icons: { icon: "/icon.svg" },
};

export const viewport: Viewport = {
  themeColor: "#000000",
  colorScheme: "dark",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className="dark">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin="anonymous"
        />
        <link
          href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="antialiased">{children}</body>
    </html>
  );
}
