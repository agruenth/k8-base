# nextjs-caddy-boilerplate

> Global guidelines: see `/home/claude_worker/.claude/CLAUDE.md`

## Project
Template for scaffolding new Next.js apps. See `agent.md` for the full 13-step deployment playbook.

## Scaffold a new app
```sh
cp -r /REPOS_PRIVAT/nextjs-caddy-boilerplate /REPOS_PRIVAT/<new-app>
```
Then update: `package.json` (name, port), `next.config.ts` (basePath), `app/layout.tsx` (metadata).

## Key Details
- Dockerfile auto-detects Prisma and bakes seeded DB into the image
- CSS design system in `globals.css` (50+ component classes) + Tailwind CSS v4 + shadcn/ui
- Add shadcn components: `npx shadcn@latest add <component>` (e.g. button, dialog, input)
- shadcn components go to `components/ui/`, utility `cn()` in `lib/utils.ts`
- Structured logger at `lib/logger.ts`
