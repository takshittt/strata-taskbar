import type { ReactNode } from 'react'
import Section from './Section'

const icon = (path: ReactNode) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" className="h-6 w-6" aria-hidden="true">
    {path}
  </svg>
)

const features = [
  {
    title: 'One button per window',
    body: 'Every open window gets its own button. Click to switch to it, click again to minimise it. Drag buttons to reorder them.',
    icon: icon(<><rect x="3" y="15" width="18" height="6" rx="1.5" /><path d="M6 18h3M11 18h3M16 18h2" /></>),
  },
  {
    title: 'Start button',
    body: 'Opens a list of all your apps, or Spotlight or Raycast if you prefer.',
    icon: icon(<><rect x="4" y="4" width="7" height="7" rx="1" /><rect x="13" y="4" width="7" height="7" rx="1" /><rect x="4" y="13" width="7" height="7" rx="1" /><rect x="13" y="13" width="7" height="7" rx="1" /></>),
  },
  {
    title: 'Pinned apps',
    body: 'Keep your favourite apps on the bar, even when they’re closed. When one is open, its icon turns into its window buttons.',
    icon: icon(<><path d="M12 17v5" /><path d="M9 3h6l-1 6 3 3v2H7v-2l3-3-1-6z" /></>),
  },
  {
    title: 'Snap windows',
    body: 'Put a window on the left half, right half, a corner, a third and more, with a keyboard shortcut or a right-click.',
    icon: icon(<><rect x="3" y="4" width="18" height="16" rx="2" /><path d="M12 4v16" /><path d="M6 12h3M7.5 10.5 9 12l-1.5 1.5" /></>),
  },
  {
    title: 'Custom zones',
    body: 'Draw your own screen layout. Hold Shift while dragging a window to drop it into a zone.',
    icon: icon(<><rect x="3" y="4" width="18" height="16" rx="2" /><path d="M14 4v16M14 12h7" /></>),
  },
  {
    title: 'Multiple monitors',
    body: 'Each screen gets its own bar showing only the windows on that screen.',
    icon: icon(<><rect x="2" y="5" width="12" height="9" rx="1.5" /><rect x="15" y="7" width="7" height="7" rx="1.5" /><path d="M6 18h4M8 14v4M18.5 14v3" /></>),
  },
]

// Icon tiles cycle through the palette: lavender first, chartreuse and tomato as accents.
const tiles = ['bg-lavender-100 text-lavender-700', 'bg-chartreuse-soft text-zinc-800', 'bg-tomato-soft text-tomato-ink']

export default function Features() {
  return (
    <Section id="features" eyebrow="Features" title="Everything you missed from Windows." tinted>
      <ul className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {features.map((f, i) => (
          <li key={f.title} className="rounded-2xl border border-lavender-100 bg-white p-6">
            <div className={`mb-4 inline-flex h-11 w-11 items-center justify-center rounded-xl ${tiles[i % tiles.length]}`}>{f.icon}</div>
            <h3 className="text-lg font-semibold">{f.title}</h3>
            <p className="mt-2 text-zinc-600">{f.body}</p>
          </li>
        ))}
      </ul>
    </Section>
  )
}
