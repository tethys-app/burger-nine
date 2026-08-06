#!/usr/bin/env node
// Runs before every build, locally and in CI.
//
// This repo is safe to hand to an LLM only because it holds nothing sensitive
// and has no server. An LLM asked to "add a contact form" will reach for a
// server route by reflex, and that is the change that quietly breaks the whole
// security model. These checks make that fail loudly instead.

import { readdir, readFile } from 'node:fs/promises'
import { join, relative } from 'node:path'

const root = process.cwd()
const failures = []

async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    if (['node_modules', 'dist', '.astro', '.git'].includes(entry.name)) continue
    const full = join(dir, entry.name)
    if (entry.isDirectory()) files.push(...(await walk(full)))
    else files.push(full)
  }
  return files
}

const files = await walk(root)

// 1. No server-side code.
const SERVER_MARKERS = [
  { pattern: /export\s+const\s+prerender\s*=\s*false/, why: 'disables static output for this route' },
  { pattern: /output:\s*['"](server|hybrid)['"]/, why: 'switches Astro out of static mode' },
  { pattern: /@astrojs\/(node|vercel|cloudflare|netlify)/, why: 'adds an SSR adapter' },
]
for (const file of files.filter((f) => /\.(astro|ts|tsx|js|mjs)$/.test(f))) {
  if (file.endsWith('check-invariants.mjs')) continue
  const source = await readFile(file, 'utf8')
  for (const { pattern, why } of SERVER_MARKERS) {
    if (pattern.test(source)) {
      failures.push(`${relative(root, file)}: ${why}. This site must stay 100% static.`)
    }
  }
}

// 2. No endpoint files — Astro treats these as server routes.
for (const file of files) {
  if (/src\/pages\/.*\.(js|ts)$/.test(file) && !/\.d\.ts$/.test(file)) {
    failures.push(`${relative(root, file)}: files under src/pages/ that are not .astro are server endpoints.`)
  }
}

// 3. Every env var must be public. A secret here would ship in the bundle.
const ENV_REFERENCE = /(?:import\.meta\.env|process\.env)\.([A-Z0-9_]+)/g
const ALLOWED_PREFIXES = ['PUBLIC_', 'VITE_']
const BUILTINS = new Set(['MODE', 'BASE_URL', 'PROD', 'DEV', 'SSR', 'NODE_ENV', 'ASSETS_PREFIX'])
for (const file of files.filter((f) => /\.(astro|ts|tsx|js|mjs)$/.test(f))) {
  if (file.endsWith('check-invariants.mjs')) continue
  const source = await readFile(file, 'utf8')
  for (const [, name] of source.matchAll(ENV_REFERENCE)) {
    if (BUILTINS.has(name)) continue
    if (!ALLOWED_PREFIXES.some((prefix) => name.startsWith(prefix))) {
      failures.push(
        `${relative(root, file)}: env var ${name} is not PUBLIC_/VITE_ prefixed. ` +
          'Secrets must never live in this repo — the API only accepts publishable keys.',
      )
    }
  }
}

// 4. Anything that looks like a secret key.
const SECRET_SHAPES = [/\bsk_live_[A-Za-z0-9]/, /\bsk_test_[A-Za-z0-9]/, /\bwhsec_[A-Za-z0-9]/, /\brk_live_[A-Za-z0-9]/]
for (const file of files.filter((f) => !/\.(png|jpe?g|webp|avif|ico|woff2?)$/.test(f))) {
  const source = await readFile(file, 'utf8').catch(() => '')
  if (SECRET_SHAPES.some((shape) => shape.test(source))) {
    failures.push(`${relative(root, file)}: contains something shaped like a secret key.`)
  }
}

if (failures.length > 0) {
  console.error('\n✗ Storefront invariants violated:\n')
  for (const failure of failures) console.error(`  • ${failure}`)
  console.error('\nSee CLAUDE.md for why these rules exist.\n')
  process.exit(1)
}

console.log('✓ storefront invariants hold (static-only, no secrets)')
