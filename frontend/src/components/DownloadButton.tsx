import { RELEASES_URL, formatSize, type Release } from '../release'

interface Props {
  release: Release | null
  size?: 'large' | 'small'
  showMeta?: boolean
}

export function AppleLogo({ className }: { className: string }) {
  return (
    <svg className={className} viewBox="0 0 384 512" fill="currentColor" aria-hidden="true">
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
    </svg>
  )
}

export default function DownloadButton({ release, size = 'large', showMeta = true }: Props) {
  const large = size === 'large'
  return (
    <div className={large ? 'flex flex-col items-center gap-3' : 'contents'}>
      <a
        href={release?.url ?? RELEASES_URL}
        className={`inline-flex items-center gap-2 rounded-full bg-lavender-600 font-medium text-white shadow-sm shadow-lavender-600/30 transition-colors hover:bg-lavender-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lavender-600 ${
          large ? 'px-7 py-3.5 text-lg' : 'px-4 py-1.5 text-sm'
        }`}
      >
        <AppleLogo className={large ? 'h-5 w-5 -mt-0.5' : 'h-3.5 w-3.5 -mt-0.5'} />
        {large ? 'Download for Mac' : 'Download'}
      </a>
      {large && showMeta && (
        <p className="text-sm text-zinc-500">
          {release && (
            <>
              Version {release.version} · {formatSize(release.sizeBytes)}
              <span className="mx-2 text-zinc-300">|</span>
            </>
          )}
          macOS 14 or newer · Apple silicon &amp; Intel · Free
        </p>
      )}
    </div>
  )
}
