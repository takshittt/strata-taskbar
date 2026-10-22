import { useEffect, useState } from 'react'

export const REPO_URL = 'https://github.com/takshittt/strata-taskbar'
export const RELEASES_URL = `${REPO_URL}/releases/latest`
export const ISSUES_URL = `${REPO_URL}/issues`

const API_URL = 'https://api.github.com/repos/takshittt/strata-taskbar/releases/latest'
const CACHE_KEY = 'strata.latestRelease'
const ASSET_NAME = /^Strata-.+\.zip$/

export interface Release {
  version: string
  url: string
  sizeBytes: number
  publishedAt: string
}

interface GitHubRelease {
  tag_name: string
  published_at: string
  assets: { name: string; size: number; browser_download_url: string }[]
}

function readCache(): Release | null {
  try {
    const raw = sessionStorage.getItem(CACHE_KEY)
    return raw ? (JSON.parse(raw) as Release) : null
  } catch {
    return null
  }
}

function writeCache(release: Release) {
  try {
    sessionStorage.setItem(CACHE_KEY, JSON.stringify(release))
  } catch {
    // Storage blocked (private mode etc.): just refetch next time.
  }
}

export function parseRelease(data: GitHubRelease): Release | null {
  const asset = data.assets.find((a) => ASSET_NAME.test(a.name))
  if (!asset) return null
  return {
    version: data.tag_name.replace(/^v/, ''),
    url: asset.browser_download_url,
    sizeBytes: asset.size,
    publishedAt: data.published_at,
  }
}

/// The newest release's zip, or null while loading or if the lookup fails.
/// Callers fall back to RELEASES_URL, so a null here never breaks the download.
export function useLatestRelease(): Release | null {
  const [release, setRelease] = useState<Release | null>(readCache)

  useEffect(() => {
    if (release) return
    const controller = new AbortController()
    fetch(API_URL, { signal: controller.signal, headers: { Accept: 'application/vnd.github+json' } })
      .then((res) => (res.ok ? (res.json() as Promise<GitHubRelease>) : null))
      .then((data) => {
        const parsed = data && parseRelease(data)
        if (parsed) {
          writeCache(parsed)
          setRelease(parsed)
        }
      })
      .catch(() => {})
    return () => controller.abort()
  }, [release])

  return release
}

export function formatSize(bytes: number): string {
  return `${(bytes / 1_000_000).toFixed(1)} MB`
}
