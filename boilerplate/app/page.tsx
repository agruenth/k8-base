"use client";

import { useState } from "react";

export default function Home() {
  const [activeView, setActiveView] = useState<"dashboard" | "content">("dashboard");
  const [activeLens, setActiveLens] = useState("overview");
  const [showModal, setShowModal] = useState(false);
  const [activeTab, setActiveTab] = useState("details");

  return (
    <div className="app-shell">
      {/* ── Header ──────────────────────────────────────────────────────── */}
      <header className="header">
        <div style={{ display: "flex", alignItems: "center" }}>
          <span className="header-title">My Dashboard</span>
          <span className="header-subtitle">Boilerplate Preview</span>
        </div>

        <div className="view-switcher">
          <button
            className={`view-btn ${activeView === "dashboard" ? "active" : ""}`}
            onClick={() => setActiveView("dashboard")}
          >
            Dashboard
          </button>
          <button
            className={`view-btn ${activeView === "content" ? "active" : ""}`}
            onClick={() => setActiveView("content")}
          >
            Content
          </button>
        </div>

        <div className="pill-switcher">
          {["overview", "metrics", "settings"].map((lens) => (
            <button
              key={lens}
              className={`pill-btn ${activeLens === lens ? "active" : ""}`}
              onClick={() => setActiveLens(lens)}
            >
              {lens.charAt(0).toUpperCase() + lens.slice(1)}
            </button>
          ))}
        </div>
      </header>

      {/* ── Main Canvas ─────────────────────────────────────────────────── */}
      <main className="main-canvas">
        {activeView === "dashboard" ? (
          <div style={{ padding: 32 }}>
            {/* Stats */}
            <div className="stats-grid">
              {[
                { label: "Active Users", value: "2,847" },
                { label: "Revenue", value: "$48.2k" },
                { label: "Conversion", value: "3.2%" },
                { label: "Avg. Session", value: "4m 12s" },
              ].map((s) => (
                <div key={s.label} className="stat-card">
                  <div className="stat-label">{s.label}</div>
                  <div className="stat-value">{s.value}</div>
                </div>
              ))}
            </div>

            {/* Badges */}
            <div style={{ display: "flex", gap: 8, marginTop: 24, flexWrap: "wrap" }}>
              <span className="badge badge-green">Healthy</span>
              <span className="badge badge-yellow">Warning</span>
              <span className="badge badge-orange">Elevated</span>
              <span className="badge badge-red">Critical</span>
              <span className="badge badge-blue">Info</span>
              <span className="badge badge-purple">New</span>
            </div>

            {/* Cards Grid */}
            <div className="grid-3" style={{ marginTop: 24 }}>
              {[
                { title: "Card One", desc: "A reusable card component with hover elevation." },
                { title: "Card Two", desc: "Works great for feature grids, dashboards, and listings." },
                { title: "Card Three", desc: "Accent border variant for highlighted content." },
              ].map((c, i) => (
                <div key={c.title} className={`card ${i === 2 ? "card-accent" : ""}`}>
                  <div className="card-title">{c.title}</div>
                  <div className="card-desc">{c.desc}</div>
                </div>
              ))}
            </div>

            {/* Number Cards */}
            <div className="grid-3" style={{ marginTop: 24 }}>
              {[
                { value: "73%", label: "Adoption Rate", detail: "Up 12% from last quarter", color: "var(--at-green)" },
                { value: "142", label: "Open Issues", detail: "23 critical, 48 high priority", color: "var(--at-orange)" },
                { value: "4.8", label: "User Rating", detail: "Based on 1,204 reviews", color: "var(--at-accent)" },
              ].map((n) => (
                <div key={n.label} className="num-card">
                  <div className="num-card-value" style={{ color: n.color }}>{n.value}</div>
                  <div className="num-card-label">{n.label}</div>
                  <div className="num-card-detail">{n.detail}</div>
                </div>
              ))}
            </div>

            {/* Buttons */}
            <div style={{ display: "flex", gap: 8, marginTop: 24 }}>
              <button className="btn btn-primary">Primary</button>
              <button className="btn btn-ghost">Ghost</button>
              <button className="btn btn-danger">Danger</button>
              <button className="btn btn-primary" onClick={() => setShowModal(true)}>
                Open Modal
              </button>
            </div>

            {/* Form */}
            <div style={{ maxWidth: 480, marginTop: 32 }}>
              <form className="form" onSubmit={(e) => e.preventDefault()}>
                <label>
                  Name
                  <input type="text" placeholder="Enter your name" />
                </label>
                <label>
                  Category
                  <select>
                    <option>Engineering</option>
                    <option>Design</option>
                    <option>Marketing</option>
                  </select>
                </label>
                <label>
                  Notes
                  <textarea placeholder="Additional details..." />
                </label>
                <div className="form-actions">
                  <button type="button" className="btn btn-ghost">Cancel</button>
                  <button type="submit" className="btn btn-primary">Submit</button>
                </div>
              </form>
            </div>
          </div>
        ) : (
          /* ── Content / Article View ──────────────────────────────────── */
          <div className="content-container">
            <div className="hero">
              <span className="hero-badge">Boilerplate</span>
              <h1 className="hero-title">Build Dashboards Fast</h1>
              <p className="hero-lead">
                A premium design system with pre-built components for headers,
                cards, modals, forms, stats, badges, and more. Pair it with
                Caddy for instant HTTPS reverse proxying.
              </p>
            </div>

            <div className="section">
              <h2 className="section-title">What You Get</h2>
              <p className="section-desc">
                Everything you need for a polished, corporate-grade dashboard
                without reaching for a CSS framework.
              </p>
              <div className="grid-3">
                <div className="num-card">
                  <div className="num-card-value" style={{ color: "var(--at-accent)" }}>50+</div>
                  <div className="num-card-label">CSS Classes</div>
                  <div className="num-card-detail">Buttons, cards, badges, grids, modals, forms</div>
                </div>
                <div className="num-card">
                  <div className="num-card-value" style={{ color: "var(--at-green)" }}>0</div>
                  <div className="num-card-label">Dependencies</div>
                  <div className="num-card-detail">Pure CSS, no Tailwind, no CSS-in-JS</div>
                </div>
                <div className="num-card">
                  <div className="num-card-value" style={{ color: "var(--at-orange)" }}>1</div>
                  <div className="num-card-label">File</div>
                  <div className="num-card-detail">Everything lives in globals.css</div>
                </div>
              </div>
            </div>

            <div className="cta-gradient" style={{ marginTop: 32 }}>
              <h2>Ready to Build?</h2>
              <p>
                Clone this boilerplate, pick a port, add a Caddy route, and
                start shipping. Check the README for the full setup guide.
              </p>
            </div>
          </div>
        )}
      </main>

      {/* ── FAB ─────────────────────────────────────────────────────────── */}
      <button className="fab" onClick={() => setShowModal(true)}>+</button>

      {/* ── Modal ───────────────────────────────────────────────────────── */}
      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <span className="modal-title">Component Preview</span>
              <button className="modal-close" onClick={() => setShowModal(false)}>
                &times;
              </button>
            </div>

            <div className="modal-tabs">
              {["details", "stats", "code"].map((tab) => (
                <button
                  key={tab}
                  className={`modal-tab ${activeTab === tab ? "active" : ""}`}
                  onClick={() => setActiveTab(tab)}
                >
                  {tab.charAt(0).toUpperCase() + tab.slice(1)}
                </button>
              ))}
            </div>

            <div className="modal-body">
              {activeTab === "details" && (
                <>
                  <h2>Modal Content</h2>
                  <p>
                    This modal includes a <strong>spring animation</strong>, backdrop blur,
                    and tabbed navigation. It supports rich content with markdown-style
                    prose styling.
                  </p>
                  <h3>Features</h3>
                  <ul>
                    <li>Animated entrance with cubic-bezier spring</li>
                    <li>Click-outside-to-close behavior</li>
                    <li>Scrollable body with max-height constraint</li>
                    <li>Responsive at 768px breakpoint</li>
                  </ul>
                  <p>
                    Links are styled with an <a href="#">accent underline</a> and inline{" "}
                    <code>code blocks</code> use the mono font.
                  </p>
                </>
              )}
              {activeTab === "stats" && (
                <div className="stats-grid">
                  <div className="stat-card">
                    <div className="stat-label">Components</div>
                    <div className="stat-value">18</div>
                  </div>
                  <div className="stat-card">
                    <div className="stat-label">CSS Lines</div>
                    <div className="stat-value">~600</div>
                  </div>
                  <div className="stat-card">
                    <div className="stat-label">Breakpoints</div>
                    <div className="stat-value">1</div>
                  </div>
                  <div className="stat-card">
                    <div className="stat-label">Animations</div>
                    <div className="stat-value">3</div>
                  </div>
                </div>
              )}
              {activeTab === "code" && (
                <>
                  <h2>Usage</h2>
                  <p>Import <code>globals.css</code> in your layout and use the class names directly:</p>
                  <table>
                    <thead>
                      <tr><th>Component</th><th>Class</th></tr>
                    </thead>
                    <tbody>
                      <tr><td>Primary button</td><td><code>.btn .btn-primary</code></td></tr>
                      <tr><td>Card</td><td><code>.card</code></td></tr>
                      <tr><td>Stat tile</td><td><code>.stat-card</code></td></tr>
                      <tr><td>Badge</td><td><code>.badge .badge-green</code></td></tr>
                    </tbody>
                  </table>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
