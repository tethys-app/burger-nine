import { defineConfig } from 'astro/config'
import react from '@astrojs/react'
import tailwind from '@tailwindcss/vite'

// `output: 'static'` is not optional here — it is the invariant that keeps this
// repo safe to hand to an LLM. No server, no secrets, nothing to leak.
// See CLAUDE.md.
export default defineConfig({
  output: 'static',
  integrations: [react()],
  // `host: true` binds 0.0.0.0 instead of 127.0.0.1, so the dev server is
  // reachable from a phone on the same wifi. `allowedHosts` only permits the
  // Host header — on its own it still leaves the socket bound to loopback.
  server: { port: 4322, host: true, allowedHosts: true },
  site: process.env.PUBLIC_SITE_URL,
  build: { inlineStylesheets: 'auto' },
  vite: { plugins: [tailwind()] },
})
