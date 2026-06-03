/**
 * Structured logger for Next.js apps running in a K8s + Loki stack.
 *
 * Design goals:
 *   1. Console output is human-readable with colors (dev experience)
 *   2. Every line is also valid JSON so Promtail/Loki can parse fields
 *   3. Zero dependencies — works in Node, Edge, and build steps
 *   4. Child loggers carry hierarchical context (e.g. "api:users:create")
 *
 * Environment variables:
 *   LOG_LEVEL  — minimum level to emit: "debug" | "info" | "warn" | "error"
 *                defaults to "debug" in development, "info" in production
 *   APP_NAME   — populates the `app` field; falls back to "app"
 *
 * Usage:
 *   import { logger } from "@/lib/logger";
 *   const log = logger.child("my-module");
 *   log.info("User created", { userId: "abc", email: "x@y.z" });
 *
 * Loki query examples:
 *   {app="my-app"} | json | level="error"
 *   {app="my-app"} | json | ctx="api:users" | latency > 500
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface LogEntry {
  /** ISO-8601 timestamp */
  ts: string;
  /** Log level */
  level: LogLevel;
  /** Human-readable message */
  msg: string;
  /** Application name — matches the k8s `app` label */
  app: string;
  /** Hierarchical context, e.g. "api:users:create" */
  ctx?: string;
  /** Additional structured data (merged into the JSON line) */
  [key: string]: unknown;
}

export interface Logger {
  debug(msg: string, data?: Record<string, unknown>): void;
  info(msg: string, data?: Record<string, unknown>): void;
  warn(msg: string, data?: Record<string, unknown>): void;
  error(msg: string, data?: Record<string, unknown>): void;
  /** Create a child logger with additional context */
  child(context: string): Logger;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const LEVEL_RANK: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

const LEVEL_COLOR: Record<LogLevel, string> = {
  debug: "\x1b[90m",  // gray
  info: "\x1b[36m",   // cyan
  warn: "\x1b[33m",   // yellow
  error: "\x1b[31m",  // red
};

const RESET = "\x1b[0m";
const DIM = "\x1b[90m";

// ---------------------------------------------------------------------------
// Configuration (resolved once at module load)
// ---------------------------------------------------------------------------

const IS_PRODUCTION = process.env.NODE_ENV === "production";

const APP_NAME = process.env.APP_NAME ?? "app";

const MIN_LEVEL: number =
  LEVEL_RANK[(process.env.LOG_LEVEL as LogLevel) ?? ""] ??
  (IS_PRODUCTION ? LEVEL_RANK.info : LEVEL_RANK.debug);

// ---------------------------------------------------------------------------
// Core write function
// ---------------------------------------------------------------------------

function write(entry: LogEntry): void {
  // ── Structured JSON line (what Promtail/Loki ingests) ──────────────
  // Piped to stdout so k8s captures it automatically.
  const json = JSON.stringify(entry);

  // ── Pretty console line (what developers read) ─────────────────────
  const tag = `${LEVEL_COLOR[entry.level]}[${entry.level.toUpperCase().padEnd(5)}]${RESET}`;
  const ctx = entry.ctx ? ` ${DIM}(${entry.ctx})${RESET}` : "";

  // Build a compact metadata suffix for console (skip ts/level/msg/app/ctx)
  const meta: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(entry)) {
    if (!["ts", "level", "msg", "app", "ctx"].includes(k)) meta[k] = v;
  }
  const metaStr = Object.keys(meta).length
    ? ` ${DIM}${JSON.stringify(meta)}${RESET}`
    : "";

  // In production, emit ONLY the JSON line (Loki parses it).
  // In development, emit the pretty line for readability.
  if (IS_PRODUCTION) {
    process.stdout.write(json + "\n");
  } else {
    // eslint-disable-next-line no-console
    console.log(`${tag}${ctx} ${entry.msg}${metaStr}`);
  }
}

// ---------------------------------------------------------------------------
// Logger factory
// ---------------------------------------------------------------------------

function emit(
  level: LogLevel,
  ctx: string | undefined,
  msg: string,
  data?: Record<string, unknown>,
): void {
  if (LEVEL_RANK[level] < MIN_LEVEL) return;

  const entry: LogEntry = {
    ts: new Date().toISOString(),
    level,
    msg,
    app: APP_NAME,
  };
  if (ctx) entry.ctx = ctx;
  if (data) Object.assign(entry, data);

  write(entry);
}

function createLogger(ctx?: string): Logger {
  return {
    debug: (msg, data) => emit("debug", ctx, msg, data),
    info: (msg, data) => emit("info", ctx, msg, data),
    warn: (msg, data) => emit("warn", ctx, msg, data),
    error: (msg, data) => emit("error", ctx, msg, data),
    child: (childCtx) => createLogger(ctx ? `${ctx}:${childCtx}` : childCtx),
  };
}

// ---------------------------------------------------------------------------
// Singleton export
// ---------------------------------------------------------------------------

export const logger: Logger = createLogger();
