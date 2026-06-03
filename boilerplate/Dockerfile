FROM node:22-slim AS builder
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
# Copy prisma files early if present (needed for generate + seed)
COPY prisma* ./prisma/
COPY prisma.config.t[s] ./
RUN npm ci
# Generate Prisma client if schema exists
RUN test -f prisma/schema.prisma && npx prisma generate || true
COPY . .
# Create and seed the database if Prisma is present — bakes seed data into the image
# so dev and k8s databases stay in sync from the same seed.ts source of truth
RUN test -f prisma/schema.prisma && npx prisma db push && npm run db:seed || true
RUN npm run build
# Ensure prisma dir exists so the runner COPY below always succeeds (even without Prisma)
RUN mkdir -p prisma

FROM node:22-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
# next.config.ts MUST be present at runtime — next start reads it to apply assetPrefix.
# Without it the prefix is silently ignored and CSS/JS assets load with wrong paths.
COPY --from=builder /app/next.config.ts ./
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
# Include prisma config and seeded database if present
COPY --from=builder /app/prisma.config.t[s] ./
COPY --from=builder /app/prisma ./prisma/
COPY --from=builder /app/dev.d[b] ./
EXPOSE 3000
CMD ["npm", "start"]
