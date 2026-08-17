import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Emits a fully static site into out/, so the marketing page can be hosted
  // anywhere without a Node server. Nothing here needs one.
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
