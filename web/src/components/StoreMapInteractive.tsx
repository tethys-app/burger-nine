// Real interactive map (Leaflet + CARTO dark tiles) replacing the old
// hand-rolled SVG département projection. client:only — Leaflet touches
// `window` at import time, so this must never run during the static build.
//
// The city list used to live as a separate card grid below the map — pure
// duplication of what the pins already show. It's folded into the map itself
// as a docked, scrollable panel: click a city, the map flies to its pin and
// opens the popup. One surface instead of two disconnected ones.
import { useEffect, useRef, useState } from 'react'
import type { Located } from '../lib/stores'
import { coordsFor, cityOf, deptLabel } from '../lib/stores'
import 'leaflet/dist/leaflet.css'

interface Props {
  stores: Located[]
  /** Slugs with a real menu page — everyone else still shows on the map, just without a link. */
  liveSlugs: string[]
}

export default function StoreMapInteractive({ stores, liveSlugs }: Props) {
  const elRef = useRef<HTMLDivElement>(null)
  const mapRef = useRef<import('leaflet').Map | null>(null)
  const markersRef = useRef<Record<string, import('leaflet').Marker>>({})
  const [activeSlug, setActiveSlug] = useState<string | null>(null)

  const located = stores.flatMap((store) => {
    const point = coordsFor(store)
    return point ? [{ store, ...point }] : []
  })

  useEffect(() => {
    let cancelled = false

    ;(async () => {
      const L = (await import('leaflet')).default
      if (cancelled || !elRef.current) return

      const live = new Set(liveSlugs)
      const map = L.map(elRef.current, {
        zoomControl: true,
        scrollWheelZoom: true,
        attributionControl: false,
      })
      mapRef.current = map
      // prefix: false drops Leaflet's own default byline (a flag icon +
      // "Leaflet" link baked into every map) so only our own credit shows.
      L.control.attribution({ prefix: false }).addTo(map)

      L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        subdomains: 'abcd',
        maxZoom: 20,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>',
      }).addTo(map)

      const pinIcon = L.divIcon({
        className: 'b9-pin',
        html: `<span class="b9-pin-halo"></span><span class="b9-pin-dot"></span>`,
        iconSize: [26, 26],
        iconAnchor: [13, 13],
      })

      for (const { store, lat, lon } of located) {
        const isLive = live.has(store.slug)
        const label = cityOf(store)
        const marker = L.marker([lat, lon], { icon: pinIcon, keyboard: true, alt: label })
        marker.bindPopup(
          isLive
            ? `<div class="b9-popup"><b>${label}</b><a href="/${store.slug}">Voir la carte →</a></div>`
            : `<div class="b9-popup"><b>${label}</b></div>`,
        )
        marker.on('click', () => setActiveSlug(store.slug))
        marker.addTo(map)
        markersRef.current[store.slug] = marker
      }

      if (located.length) {
        const bounds = L.latLngBounds(located.map((p) => [p.lat, p.lon] as [number, number]))
        map.fitBounds(bounds, { padding: [36, 36], maxZoom: 10 })
      } else {
        map.setView([45.5, 4.7], 8)
      }
    })()

    return () => {
      cancelled = true
      mapRef.current?.remove()
      mapRef.current = null
      markersRef.current = {}
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const flyTo = (slug: string) => {
    const map = mapRef.current
    const marker = markersRef.current[slug]
    if (!map || !marker) return
    setActiveSlug(slug)
    map.flyTo(marker.getLatLng(), Math.max(map.getZoom(), 9), { duration: 0.6 })
    marker.openPopup()
  }

  return (
    <div className="b9-map-shell">
      <div ref={elRef} className="b9-map" />

      <aside className="b9-city-list" aria-label="Nos restaurants">
        <div className="b9-city-list-head">
          <span className="b9-legend-dot" />
          {located.length} restaurant{located.length > 1 ? 's' : ''}
        </div>
        <ul>
          {located.map(({ store }) => (
            <li key={store.slug}>
              <button type="button" className={store.slug === activeSlug ? 'active' : ''} onClick={() => flyTo(store.slug)}>
                <span className="dep">{deptLabel(store)}</span>
                <span className="city">{cityOf(store)}</span>
              </button>
            </li>
          ))}
        </ul>
      </aside>

      <style>{`
        .b9-map-shell {
          position: relative;
          display: grid;
          grid-template-columns: minmax(0, 1fr) 240px;
          gap: 0;
          border-radius: 16px;
          overflow: hidden;
        }
        .b9-map { width: 100%; height: 460px; }
        .b9-map .leaflet-container {
          background: var(--ink-900);
          font-family: var(--body);
        }
        .b9-map .leaflet-control-attribution {
          background: rgba(10, 3, 8, 0.65);
          color: rgba(255, 255, 255, 0.55);
        }
        .b9-map .leaflet-control-attribution a { color: rgba(255, 255, 255, 0.75); }
        .b9-map .leaflet-control-zoom a {
          background: rgba(10, 3, 8, 0.72);
          color: #fff;
          border-color: rgba(255, 255, 255, 0.18);
        }
        .b9-map .leaflet-control-zoom a:hover { background: rgba(255, 45, 158, 0.35); }
        .b9-pin-dot {
          position: absolute;
          inset: 7px;
          border-radius: 50%;
          background: var(--pink, #ff2d9e);
          border: 2px solid #fff;
          box-shadow: 0 2px 6px rgba(0, 0, 0, 0.5);
        }
        .b9-pin-halo {
          position: absolute;
          inset: 0;
          border-radius: 50%;
          background: var(--pink, #ff2d9e);
          opacity: 0.35;
          animation: b9-pin-pulse 2.2s ease-out infinite;
        }
        @keyframes b9-pin-pulse {
          0% { transform: scale(0.6); opacity: 0.5; }
          100% { transform: scale(1.9); opacity: 0; }
        }
        .b9-popup {
          display: flex;
          flex-direction: column;
          gap: 4px;
          font-family: var(--display);
          font-weight: 800;
          text-transform: uppercase;
          font-size: 13px;
        }
        .b9-popup a {
          font-size: 11px;
          letter-spacing: 0.04em;
          color: var(--pink, #ff2d9e);
        }
        .b9-map .leaflet-popup-content-wrapper {
          background: var(--ink-700);
          color: #fff;
          border-radius: 12px;
        }
        .b9-map .leaflet-popup-tip { background: var(--ink-700); }
        .b9-legend-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background: var(--pink, #ff2d9e);
          box-shadow: 0 0 8px var(--pink, #ff2d9e);
          flex: none;
        }

        .b9-city-list {
          display: flex;
          flex-direction: column;
          height: 460px;
          background: var(--ink-900);
          border-left: 1px solid rgba(255, 255, 255, 0.1);
        }
        .b9-city-list-head {
          display: flex;
          align-items: center;
          gap: 8px;
          padding: 14px 16px;
          font-family: var(--display);
          font-weight: 800;
          font-size: 11px;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: #fff;
          border-bottom: 1px solid rgba(255, 255, 255, 0.08);
          flex: none;
        }
        .b9-city-list ul {
          list-style: none;
          margin: 0;
          padding: 6px;
          overflow-y: auto;
        }
        .b9-city-list button {
          all: unset;
          box-sizing: border-box;
          display: flex;
          flex-direction: column;
          gap: 2px;
          width: 100%;
          padding: 9px 10px;
          border-radius: 10px;
          cursor: pointer;
          transition: background 0.15s;
        }
        .b9-city-list button:hover,
        .b9-city-list button:focus-visible { background: rgba(255, 255, 255, 0.06); }
        .b9-city-list button.active { background: rgba(255, 45, 158, 0.16); }
        .b9-city-list .dep {
          font-size: 9.5px;
          font-weight: 800;
          letter-spacing: 0.1em;
          color: var(--pink, #ff2d9e);
        }
        .b9-city-list .city {
          font-family: var(--display);
          font-weight: 700;
          font-size: 13.5px;
          color: #fff;
        }

        @media (max-width: 760px) {
          .b9-map-shell { grid-template-columns: minmax(0, 1fr); }
          .b9-map { height: 320px; }
          .b9-city-list {
            height: auto;
            max-height: 180px;
            border-left: none;
            border-top: 1px solid rgba(255, 255, 255, 0.1);
          }
          .b9-city-list ul {
            display: flex;
            gap: 6px;
            overflow-x: auto;
            overflow-y: visible;
            padding: 10px;
          }
          .b9-city-list li { flex: none; }
          .b9-city-list button { white-space: nowrap; flex-direction: row; gap: 6px; align-items: baseline; }
        }
      `}</style>
    </div>
  )
}
