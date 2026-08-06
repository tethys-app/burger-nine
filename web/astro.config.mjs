import { defineConfig } from 'astro/config'
import react from '@astrojs/react'

// `output: 'static'` is not optional here — it is the invariant that keeps this
// repo safe to hand to an LLM. No server, no secrets, nothing to leak.
// See CLAUDE.md.
export default defineConfig({
  output: 'static',
  integrations: [react()],
  server: { port: 4322 },
  site: process.env.PUBLIC_SITE_URL,
  build: { inlineStylesheets: 'auto' },
})
