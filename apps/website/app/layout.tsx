import type { Metadata, Viewport } from "next";
import { Fraunces, Instrument_Sans } from "next/font/google";
import { Grow } from "@/components/Grow";
import "./globals.css";

const display = Fraunces({
  subsets: ["latin"],
  style: ["normal", "italic"],
  axes: ["opsz"],
  variable: "--font-fraunces",
  display: "swap",
});

const body = Instrument_Sans({
  subsets: ["latin"],
  variable: "--font-instrument",
  display: "swap",
});

const description =
  "Coppice finds the git worktrees your coding agents left behind and frees the space without touching your work.";

export const metadata: Metadata = {
  metadataBase: new URL("https://coppice.rafay99.com"),
  title: "Coppice. Cut agent worktrees back so they grow again",
  description,
  keywords: [
    "git worktree",
    "macOS",
    "developer tools",
    "node_modules",
    "Claude Code",
    "Codex",
    "T3 Code",
    "Command Code",
    "OpenCode",
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
    <html lang="en" className={`${display.variable} ${body.variable}`} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: "var d=document.documentElement;d.classList.add('js');setTimeout(function(){if(!d.dataset.motion)d.classList.remove('js')},4000)" }} />
      </head>
      <body className="antialiased">
        {children}
        <Grow />
      </body>
    </html>
  );
}
