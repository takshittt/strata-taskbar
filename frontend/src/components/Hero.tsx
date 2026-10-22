import type { Release } from '../release'
import DownloadButton from './DownloadButton'
import MockTaskbar from './MockTaskbar'

export default function Hero({ release }: { release: Release | null }) {
  return (
    <section id="top" className="bg-gradient-to-b from-lavender-50 via-white to-white px-4 pt-16 pb-20 sm:px-6 sm:pt-24">
      <div className="mx-auto max-w-3xl text-center">
        <img src="icon.png" alt="" className="mx-auto mb-6 h-20 w-20 sm:h-24 sm:w-24" />
        <h1 className="relative isolate text-4xl font-bold tracking-tight text-balance sm:text-6xl">
          A Windows-style{' '}
          <span className="relative whitespace-nowrap">
            <span aria-hidden="true" className="absolute inset-x-0 bottom-1 -z-10 h-3 -rotate-1 rounded-sm bg-chartreuse sm:bottom-2 sm:h-5" />
            taskbar
          </span>{' '}
          for your Mac.
        </h1>
        <p className="mx-auto mt-5 max-w-xl text-lg text-pretty text-zinc-600 sm:text-xl">
          The Dock shows one icon per app. Strata shows <strong className="font-semibold text-zinc-900">every open window</strong> as its own button, so you can switch with one click.
        </p>
        <div className="mt-9">
          <DownloadButton release={release} />
        </div>
      </div>
      <div className="mt-16">
        <MockTaskbar />
      </div>
    </section>
  )
}
