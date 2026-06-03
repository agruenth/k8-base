# Next.js + Caddy Boilerplate

A fast-start boilerplate for building premium-looking dashboards with **Next.js** and serving them behind **Caddy** as a reverse proxy. The CSS design system is extracted from a real production project — no Tailwind, no CSS-in-JS, just a single `globals.css` with design tokens and reusable component classes.

---

## Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Run the dev server
npm run dev

# 3. Open in browser
open http://localhost:3010/my-app
```

---

## Project Structure

```
├── app/
│   ├── globals.css       # Design system (the good stuff)
│   ├── layout.tsx        # Root layout with Google Fonts
│   └── page.tsx          # Demo page showcasing all components
├── Caddyfile.template    # Template Caddy config
├── next.config.ts        # basePath config (must match Caddy route)
├── package.json
└── tsconfig.json
```

---

## The CSS Design System

Everything lives in `app/globals.css`. No build step, no plugins.

### Design Tokens (`:root`)

| Token | Purpose |
|---|---|
| `--at-bg`, `--at-bg-raised`, `--at-bg-muted`, `--at-bg-canvas` | Background layers |
| `--at-border`, `--at-border-mid`, `--at-divider` | Border hierarchy |
| `--at-text`, `--at-text-2`, `--at-text-3`, `--at-text-muted` | Text hierarchy |
| `--at-accent`, `--at-accent-hover`, `--at-accent-light`, `--at-accent-ring` | Brand accent (deep blue) |
| `--at-green`, `--at-yellow`, `--at-orange`, `--at-red`, etc. | Semantic colors |
| `--at-shadow`, `--at-shadow-lg`, `--at-shadow-xl` | Elevation tiers |
| `--at-font-sans`, `--at-font-mono` | Typography stacks |
| `--at-gradient` | Brand gradient (for CTA blocks) |

### Component Classes

| Component | Classes | What it does |
|---|---|---|
| **App Shell** | `.app-shell`, `.header`, `.main-canvas` | Full-viewport flex layout |
| **Pill Switcher** | `.pill-switcher`, `.pill-btn`, `.pill-btn.active` | Rounded tab group |
| **View Switcher** | `.view-switcher`, `.view-btn`, `.view-btn.active` | Segmented control |
| **Buttons** | `.btn`, `.btn-primary`, `.btn-ghost`, `.btn-danger` | Button variants |
| **Cards** | `.card`, `.card-accent`, `.card-title`, `.card-desc` | Content cards with hover |
| **Number Cards** | `.num-card`, `.num-card-value`, `.num-card-label` | Stat display cards |
| **Stats Grid** | `.stats-grid`, `.stat-card`, `.stat-label`, `.stat-value` | Auto-fill metric tiles |
| **Badges** | `.badge`, `.badge-green`, `.badge-red`, `.badge-blue`, etc. | Status indicators |
| **Tags** | `.tag`, `.tag-green`, `.tag-red`, `.tag-blue` | Inline chips |
| **Modal** | `.modal-overlay`, `.modal`, `.modal-header`, `.modal-tabs`, `.modal-body` | Animated modal with backdrop blur |
| **Tooltip** | `.tooltip`, `.tooltip-title`, `.tooltip-subtitle`, `.tooltip-body` | Hover tooltip with fade-in |
| **Form** | `.form`, `.form-actions` | Styled inputs/selects/textareas |
| **FAB** | `.fab` | Floating action button |
| **Legend** | `.legend`, `.legend-item`, `.legend-dot` | Chart legend overlay |
| **Grids** | `.grid-2`, `.grid-3` | 2- and 3-column CSS grids |
| **Hero** | `.hero`, `.hero-badge`, `.hero-title`, `.hero-lead` | Landing section |
| **Sections** | `.section`, `.section-title`, `.section-desc` | Content sections |
| **CTA** | `.cta-gradient` | Gradient call-to-action block |
| **Icon Box** | `.icon-box`, `.icon-box-lg` | Rounded icon containers |

### Theming

Override the `:root` tokens to re-skin the entire app:

```css
:root {
  --at-accent:       #e11d48;   /* rose */
  --at-accent-hover: #f43f5e;
  --at-accent-light: #ffe4e6;
  --at-accent-ring:  rgba(225, 29, 72, 0.15);
  --at-gradient:     linear-gradient(234deg, #ffe4e6, #e11d48);
}
```

---

## Caddy Setup

[Caddy](https://caddyserver.com/) gives you automatic HTTPS, security headers, and clean reverse-proxy routing — no nginx config headaches.

### Install Caddy

```bash
# Debian/Ubuntu
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install caddy

# macOS
brew install caddy

# Or download from https://caddyserver.com/download
```

### The Mental Model

Each Next.js app runs on its own port with a `basePath`. Caddy routes incoming requests by path prefix to the right port:

```
Browser                    Caddy (:443)                  Next.js Apps
──────────               ──────────────               ──────────────
/my-app/*    ──────────►  handle /my-app*  ──────────►  localhost:3010
/other-app/* ──────────►  handle /other-app* ────────►  localhost:3020
/third/*     ──────────►  handle /third*   ──────────►  localhost:3030
```

### Step-by-Step: Adding a New App

**1. Clone this boilerplate**

```bash
cp -r nextjs-caddy-boilerplate my-new-app
cd my-new-app
```

**2. Pick a name, path, and port**

| Setting | Example |
|---|---|
| App name | `my-new-app` |
| Path prefix | `/my-new-app` |
| Port | `3010` |

**3. Configure next.config.ts**

```ts
const nextConfig: NextConfig = {
  basePath: "/my-new-app",
};
```

**4. Configure package.json ports**

```json
{
  "scripts": {
    "dev": "next dev --port 3010",
    "start": "next start --port 3010"
  }
}
```

**5. Add a Caddy route**

In your main Caddyfile, add inside the server block:

```caddy
handle /my-new-app* {
    reverse_proxy localhost:3010
}
```

**6. Reload Caddy**

```bash
caddy reload --config /path/to/Caddyfile
```

**7. Done.** Visit `https://localhost/my-new-app` (or your domain).

### Adding Basic Auth

Generate a password hash:

```bash
caddy hash-password --plaintext 'your-secure-password'
```

Create a reusable auth snippet and import it:

```caddy
(auth_myapp) {
    basic_auth {
        myuser $2a$14$THE_HASH_FROM_ABOVE
    }
}

handle /my-new-app* {
    import auth_myapp
    reverse_proxy localhost:3010
}
```

### Production TLS

For a real domain with automatic Let's Encrypt:

```caddy
yourdomain.com {
    import hardened

    handle /my-app* {
        reverse_proxy localhost:3010
    }
}
```

Caddy handles certificate provisioning and renewal automatically. For a bare IP address, use `tls internal` for self-signed certs.

### Running Caddy as a Service

```bash
# Enable and start
sudo systemctl enable --now caddy

# Check status
sudo systemctl status caddy

# Reload config without downtime
sudo systemctl reload caddy

# View logs
journalctl -u caddy -f
```

The default config path when running as a service is `/etc/caddy/Caddyfile`.

---

## Workflow Summary

```
1.  cp -r nextjs-caddy-boilerplate my-app
2.  Set basePath + port
3.  npm install && npm run build
4.  Add `handle /my-app*` route to Caddyfile
5.  caddy reload
6.  Ship it
```

---

## Tips

- **One CSS file.** Don't split it. The section comments are your nav.
- **No dark mode** by design. Add it later by duplicating tokens under `@media (prefers-color-scheme: dark)` or a `.dark` class.
- **One breakpoint** at 768px. Keep it simple. Add more only when you actually need them.
- **Fonts** are loaded via `next/font/google` — Source Sans 3 + Source Code Pro. Change them in `layout.tsx` and update the `--at-font-sans` / `--at-font-mono` tokens.
- **The `--at-` prefix** keeps tokens from colliding with third-party CSS. Keep it even if you rename the project.
