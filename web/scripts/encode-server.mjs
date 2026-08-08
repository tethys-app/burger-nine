#!/usr/bin/env bun
// Dev-only encode server for the scrub tuner. `bun run encode-server`.
//
// This is NOT part of the site. It is a separate process on its own port, so
// the storefront stays `output: 'static'` with no server route — see CLAUDE.md.
// Nothing here ships; production never learns this port exists.
//
// It re-encodes the hero clip on demand so fps / resolution / crop can be
// judged by scrolling the real thing instead of guessing. Every encode is
// all-intra (`-g 1`): that is what makes `currentTime` seeks cheap, and it is
// the whole reason scrubbing looks smooth.

import { $ } from 'bun'
import { existsSync } from 'node:fs'
import { mkdir } from 'node:fs/promises'

// 4322 is the Astro dev server and it takes the next few ports when busy; sit
// clear of that range. A constant, not an env var: check-invariants.mjs scans
// every file here for non-PUBLIC_ env reads, and it is right to — this repo
// must stay provably free of configuration that could carry a secret.
const PORT = 4325
// `bun run encode-server v3.mp4` to judge a new clip. An argument, not an env
// var, for the same reason as above.
const SOURCE = process.argv[2] ?? 'v2-trimed.mp4'
const OUT_DIR = 'public/assets/video/tune'

await mkdir(OUT_DIR, { recursive: true })

if (!existsSync(SOURCE)) {
  console.error(`✗ source clip not found: ${SOURCE}`)
  process.exit(1)
}

// Probe once — the tuner needs the source's real numbers to bound its sliders.
const probe = await $`ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,duration \
  -of json ${SOURCE}`.json()
const src = probe.streams[0]
const [num, den] = src.r_frame_rate.split('/').map(Number)
const SOURCE_INFO = {
  file: SOURCE,
  width: src.width,
  height: src.height,
  fps: +(num / den).toFixed(3),
  duration: +Number(src.duration).toFixed(3),
}
console.log(`  source: ${SOURCE_INFO.width}×${SOURCE_INFO.height} @${SOURCE_INFO.fps}fps, ${SOURCE_INFO.duration}s`)

// Clamped so a URL cannot ask for a 16k encode and wedge the machine.
// Note the null/'' guard: Number(null) is 0, which is finite, so testing
// isFinite alone would turn every absent param into 0 — and crf 0 is lossless,
// which libx264's high profile rejects outright.
const clamp = (n, lo, hi, dflt) => {
  if (n === null || n === undefined || n === '') return dflt
  const v = Number(n)
  return Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : dflt
}

/** Encode params → a stable filename, so identical requests hit the cache.
    Rounded before stringifying, or 16/9 and 1.7778 would be two cache entries
    for what is visually the same encode. */
const keyOf = (p) =>
  [
    // Source first: two clips at identical params must not share a cache entry.
    SOURCE.replace(/\.[^.]+$/, '').replace(/[^a-z0-9]+/gi, '_'),
    `h${p.height}`,
    `f${p.fps}`,
    `q${p.crf}`,
    `a${p.aspect.toFixed(3).replace('.', '_')}`,
    `y${p.focus.toFixed(2).replace('.', '_')}`,
  ].join('-')

const encode = async (p) => {
  const out = `${OUT_DIR}/${keyOf(p)}.mp4`
  // Size check, not just existence: a failed ffmpeg run leaves a 0-byte file
  // behind, and serving that as a cache hit hides the error forever.
  if (existsSync(out) && Bun.file(out).size > 0) return { out, cached: true, ms: 0 }

  // Crop to the requested aspect around a vertical focus point, then scale to
  // the target height. `min(iw, ih*a)` keeps the crop inside the frame at any
  // aspect, so widening past the source just yields the full width.
  const vf =
    `crop='min(iw,ih*${p.aspect})':'min(ih,iw/${p.aspect})':` +
    `'(iw-min(iw,ih*${p.aspect}))/2':'(ih-min(ih,iw/${p.aspect}))*${p.focus}',` +
    `scale=-2:${p.height}:flags=lanczos,fps=${p.fps}`

  const t0 = performance.now()
  try {
    await $`ffmpeg -y -v error -i ${SOURCE} -an -vf ${vf} \
      -c:v libx264 -preset veryfast -profile:v high -pix_fmt yuv420p \
      -crf ${p.crf} -g 1 -keyint_min 1 -sc_threshold 0 \
      -x264-params ref=1:bframes=0 -movflags +faststart ${out}`
  } catch (err) {
    // Do not leave the stub behind for the cache to serve later.
    await $`rm -f ${out}`.nothrow()
    throw err
  }
  return { out, cached: false, ms: Math.round(performance.now() - t0) }
}

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*' },
  })

Bun.serve({
  port: PORT,
  // 0.0.0.0, so the tuner works from a phone on the same wifi too.
  hostname: '0.0.0.0',
  // Without this a taken port is silently reused by whoever holds it, and the
  // tuner ends up talking to the Astro dev server instead.
  reusePort: false,
  idleTimeout: 120, // veryfast still needs longer than the 10s default at 1080p
  routes: {
    '/source': () => json(SOURCE_INFO),

    '/encode': async (req) => {
      const q = new URL(req.url).searchParams
      const p = {
        height: Math.round(clamp(q.get('height'), 240, 1440, 720) / 2) * 2, // h264 needs even
        fps: clamp(q.get('fps'), 8, 60, 24),
        // Floor of 8, not 0: crf 0 is lossless, which the high profile refuses,
        // and which measured 118 Mbps — far too heavy to seek in real time.
        crf: clamp(q.get('crf'), 8, 40, 14),
        aspect: clamp(q.get('aspect'), 0.5, 3.5, 16 / 9),
        focus: clamp(q.get('focus'), 0, 1, 0.5), // 0 = crop from top, 1 = bottom
      }
      try {
        const { out, cached, ms } = await encode(p)
        const size = Bun.file(out).size
        return json({
          url: `/assets/video/tune/${out.split('/').pop()}`,
          cached,
          encodeMs: ms,
          bytes: size,
          mb: +(size / 1e6).toFixed(2),
          frames: Math.round(SOURCE_INFO.duration * p.fps),
          params: p,
        })
      } catch (err) {
        return json({ error: String(err?.stderr ?? err) }, 500)
      }
    },
  },

  fetch: () => new Response('scrub encode server', { headers: { 'access-control-allow-origin': '*' } }),
})

const lan = Object.values(await import('node:os').then((os) => os.networkInterfaces()))
  .flat()
  .find((n) => n && n.family === 'IPv4' && !n.internal)?.address

console.log(`\n  encode server  http://localhost:${PORT}`)
if (lan) console.log(`  on your LAN    http://${lan}:${PORT}`)
console.log(`  output         ${OUT_DIR}/  (cached by params)\n`)
