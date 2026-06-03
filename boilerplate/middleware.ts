import { NextRequest, NextResponse } from "next/server";

/**
 * Request logging middleware.
 * Runs in Edge Runtime — uses console.log with JSON for Loki compatibility.
 * The full structured logger (lib/logger.ts) is for server-side Node.js code.
 */
export function middleware(request: NextRequest) {
  const start = Date.now();
  const response = NextResponse.next();
  const latency = Date.now() - start;

  const method = request.method;
  const path = request.nextUrl.pathname;
  const status = response.status;

  const entry = {
    ts: new Date().toISOString(),
    level: status >= 500 ? "error" : status >= 400 ? "warn" : "info",
    msg: `${method} ${path} ${status}`,
    app: process.env.APP_NAME ?? "app",
    ctx: "http",
    method,
    path,
    status,
    latency,
  };

  // Edge Runtime: console.log is the only output mechanism
  // eslint-disable-next-line no-console
  console.log(JSON.stringify(entry));

  response.headers.set("Server-Timing", `total;dur=${latency}`);
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
