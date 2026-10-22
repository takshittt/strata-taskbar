import { REPO_URL, type Release } from '../release'
import DownloadButton from './DownloadButton'

const links = [
  { href: '#features', label: 'Features' },
  { href: '#install', label: 'Install' },
  { href: '#shortcuts', label: 'Shortcuts' },
  { href: '#faq', label: 'FAQ' },
]

export default function Header({ release }: { release: Release | null }) {
  return (
    <header className="sticky top-0 z-20 border-b border-zinc-200/70 bg-white/80 backdrop-blur-md">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-4 sm:px-6">
        <a href="#top" className="flex items-center gap-2 font-semibold tracking-tight">
          <img src="icon.png" alt="" className="h-7 w-7" />
          Strata
        </a>
        <nav aria-label="Main" className="flex items-center gap-1 sm:gap-6">
          <ul className="hidden items-center gap-6 text-sm text-zinc-600 md:flex">
            {links.map((l) => (
              <li key={l.href}>
                <a href={l.href} className="transition-colors hover:text-zinc-900">
                  {l.label}
                </a>
              </li>
            ))}
            <li>
              <a href={REPO_URL} className="transition-colors hover:text-zinc-900">
                GitHub
              </a>
            </li>
          </ul>
          <DownloadButton release={release} size="small" />
        </nav>
      </div>
    </header>
  )
}
