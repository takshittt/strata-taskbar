import { ISSUES_URL, REPO_URL, type Release } from '../release'
import DownloadButton from './DownloadButton'

export default function Footer({ release }: { release: Release | null }) {
  return (
    <>
      <section aria-labelledby="cta-title" className="bg-gradient-to-b from-lavender-50 to-lavender-100 px-4 py-20 text-center sm:px-6 sm:py-28">
        <img src="icon.png" alt="" className="mx-auto mb-6 h-16 w-16" />
        <h2 id="cta-title" className="text-3xl font-bold tracking-tight text-balance sm:text-4xl">
          Give your Mac a taskbar.
        </h2>
        <div className="mt-8">
          <DownloadButton release={release} />
        </div>
      </section>
      <footer className="border-t border-zinc-200 px-4 py-8 sm:px-6">
        <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 text-sm text-zinc-500 sm:flex-row">
          <p>Strata is free and open source under the MIT license.</p>
          <ul className="flex gap-6">
            <li>
              <a href={REPO_URL} className="hover:text-zinc-900">GitHub</a>
            </li>
            <li>
              <a href={`${REPO_URL}/releases`} className="hover:text-zinc-900">All releases</a>
            </li>
            <li>
              <a href={ISSUES_URL} className="hover:text-zinc-900">Report a bug</a>
            </li>
          </ul>
        </div>
      </footer>
    </>
  )
}
