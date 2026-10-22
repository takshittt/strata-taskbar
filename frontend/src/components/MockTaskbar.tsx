import { AppleLogo } from './DownloadButton'

// A drawing of the bar in HTML, standing in for a screenshot (spec §4.1).

interface Item {
  label: string
  colors: string
  focused?: boolean
}

const windows: Item[] = [
  { label: 'Apple – Start Page', colors: 'from-lavender-400 to-lavender-600', focused: true },
  { label: 'Budget.xlsx', colors: 'from-emerald-400 to-green-600' },
  { label: 'Inbox — Mail', colors: 'from-tomato to-tomato-ink' },
  { label: 'Documents', colors: 'from-chartreuse to-lime-500' },
  { label: '~ — zsh', colors: 'from-zinc-600 to-zinc-800' },
]

function StartIcon() {
  return (
    <div className="grid h-5 w-5 grid-cols-2 gap-0.5">
      {['bg-lavender-600', 'bg-chartreuse', 'bg-tomato', 'bg-lavender-300'].map((c) => (
        <span key={c} className={`rounded-[2px] ${c}`} />
      ))}
    </div>
  )
}

export default function MockTaskbar() {
  return (
    <div aria-hidden="true" className="relative mx-auto w-full max-w-5xl select-none">
      <div className="relative aspect-[16/9] overflow-hidden rounded-2xl border border-lavender-200 bg-gradient-to-br from-lavender-200 via-lavender-100 to-tomato-soft shadow-2xl shadow-lavender-300/50 sm:aspect-[16/8]">
        {/* Menu bar */}
        <div className="flex h-6 items-center gap-4 bg-white/50 px-4 text-[11px] font-medium text-zinc-700 backdrop-blur">
          <AppleLogo className="h-3 w-3 text-zinc-800" />
          <span className="font-semibold">Safari</span>
          <span className="hidden sm:inline">File</span>
          <span className="hidden sm:inline">Edit</span>
          <span className="hidden sm:inline">View</span>
        </div>

        {/* Two windows, snapped to the left and right halves */}
        <div className="absolute inset-x-3 top-9 bottom-14 flex gap-3 sm:inset-x-4 sm:bottom-16">
          <FakeWindow title="Apple – Start Page" active />
          <FakeWindow title="Budget.xlsx" />
        </div>

        {/* The bar */}
        <div className="absolute inset-x-0 bottom-0 flex h-11 items-center gap-1 border-t border-white/60 bg-white/70 px-2 backdrop-blur-xl sm:h-12 sm:gap-1.5">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md hover:bg-zinc-900/5">
            <StartIcon />
          </div>
          {windows.map((w, i) => (
            <div
              key={w.label}
              className={`relative flex h-9 min-w-0 items-center gap-2 rounded-md px-2 text-xs text-zinc-800 ${
                w.focused ? 'bg-white shadow-sm ring-1 ring-zinc-900/5' : ''
              } ${i > 2 ? 'hidden sm:flex' : 'flex'}`}
            >
              <span className={`h-5 w-5 shrink-0 rounded-[5px] bg-gradient-to-br ${w.colors}`} />
              <span className="hidden truncate md:inline md:max-w-28 lg:max-w-36">{w.label}</span>
              {w.focused && <span className="absolute inset-x-3 bottom-0.5 h-0.5 rounded-full bg-lavender-600" />}
            </div>
          ))}
          <div className="ml-auto pr-2 text-[11px] text-zinc-600">9:41</div>
        </div>
      </div>
    </div>
  )
}

function FakeWindow({ title, active = false }: { title: string; active?: boolean }) {
  return (
    <div className={`flex flex-1 flex-col overflow-hidden rounded-lg bg-white ${active ? 'shadow-xl' : 'shadow-md opacity-95'}`}>
      <div className="flex h-6 items-center gap-1.5 border-b border-zinc-100 px-2.5 sm:h-7">
        <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
        <span className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
        <span className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
        <span className="ml-2 truncate text-[10px] text-zinc-500">{title}</span>
      </div>
      <div className="flex-1 space-y-2 p-3">
        <div className="h-2 w-2/3 rounded bg-zinc-100" />
        <div className="h-2 w-1/2 rounded bg-zinc-100" />
        <div className="h-2 w-3/4 rounded bg-zinc-100" />
      </div>
    </div>
  )
}
