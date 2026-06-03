import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // ── Set this to your app's full path prefix ─────────────────────────────
  // Must include the environment prefix: /exp/<app> or /prod/<app>
  // Must match the Caddy `handle /exp/<app>*` route.
  // IMPORTANT: this file must be present in the Docker runner image (see Dockerfile).
  // next start reads it at runtime to apply assetPrefix — without it CSS/JS will 404.
  assetPrefix: "/exp/my-app",
  env: {
    NEXT_PUBLIC_BASE_PATH: "/exp/my-app",
  },
};

export default nextConfig;
