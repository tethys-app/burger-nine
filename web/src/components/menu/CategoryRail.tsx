import { useEffect, useRef } from 'react'
import type { Section } from '../../lib/types'

// Ported from the Neo app's category-rail.tsx, unchanged in structure.

/** Mobile-only horizontal pill strip. Desktop gets the vertical nav instead. */
export function CategoryRail({
  sections, active, onSelect,
}: {
  sections: Section[]; active: string; onSelect: (id: string) => void
}) {
  const pills = useRef(new Map<string, HTMLButtonElement>())

  useEffect(() => {
    pills.current.get(active)?.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' })
  }, [active])

  return (
    <div className="sticky top-[60px] z-30 border-b border-hairline bg-surface/85 backdrop-blur-xl lg:hidden">
      <div className="no-scrollbar flex gap-2 overflow-x-auto px-4 py-3">
        {sections.map((sec) => {
          const on = sec.id === active
          return (
            <button
              key={sec.id}
              ref={(el) => { if (el) pills.current.set(sec.id, el) }}
              onClick={() => onSelect(sec.id)}
              className={`menu-title shrink-0 whitespace-nowrap rounded-full px-4 py-2.5 text-[13px] font-semibold transition-all duration-200
                ${on
                  ? 'border-transparent bg-gradient-to-br from-pink-hot to-pink-deep text-white shadow-md'
                  : 'border border-hairline bg-surface-depth text-muted hover:text-ink'}`}
            >
              {sec.title}
            </button>
          )
        })}
      </div>
    </div>
  )
}

/** Desktop sticky left rail with a moving active indicator. */
export function CategoryNav({
  sections, active, onSelect,
}: {
  sections: Section[]; active: string; onSelect: (id: string) => void
}) {
  return (
    <nav className="sticky top-[52px] hidden h-[calc(100dvh-52px)] w-56 shrink-0 overflow-y-auto py-2 lg:block">
      <ul className="space-y-0.5 pr-2">
        {sections.map((sec) => {
          const on = sec.id === active
          return (
            <li key={sec.id}>
              <button
                onClick={() => onSelect(sec.id)}
                className={`group relative flex w-full items-center gap-2.5 rounded-xl px-3 py-2.5 text-left transition
                  ${on ? 'bg-elevated text-ink' : 'text-muted hover:bg-elevated/50 hover:text-ink'}`}
              >
                <span className={`h-5 w-1 shrink-0 rounded-full transition-all ${on ? 'bg-pink' : 'bg-transparent'}`} />
                <span className="menu-title min-w-0 flex-1 truncate text-sm font-black">{sec.title}</span>
              </button>
            </li>
          )
        })}
      </ul>
    </nav>
  )
}
