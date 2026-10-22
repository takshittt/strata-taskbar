import type { ReactNode } from 'react'
import Section from './Section'

const Path = ({ children }: { children: ReactNode }) => <strong className="font-semibold text-zinc-900">{children}</strong>

const steps: { title: string; body: ReactNode }[] = [
  {
    title: 'Move it to Applications',
    body: (
      <p>
        Double-click the zip file to unzip it. Then drag <Path>Strata</Path> into your <Path>Applications</Path> folder.
      </p>
    ),
  },
  {
    title: 'Open it the first time',
    body: (
      <>
        <p>Strata is free, so it isn’t registered with Apple (that costs money every year). Your Mac will block it the first time. You only need to do this once:</p>
        <ol className="mt-3 list-decimal space-y-1.5 pl-5 marker:text-lavender-500">
          <li>
            Open <Path>Strata</Path> from Applications. You’ll see a warning. Click <Path>Done</Path> or <Path>OK</Path>.
          </li>
          <li>
            Open <Path>System Settings → Privacy &amp; Security</Path>.
          </li>
          <li>
            Scroll down. Next to the message about Strata, click <Path>Open Anyway</Path>.
          </li>
          <li>
            Enter your password if asked, then click <Path>Open Anyway</Path> again.
          </li>
        </ol>
      </>
    ),
  },
  {
    title: 'Give it permission',
    body: (
      <>
        <p>
          Strata needs <Path>Accessibility</Path> permission to see and move your windows. Until you allow it, the bar says <em>“Strata needs Accessibility access — click to grant”</em>.
        </p>
        <ol className="mt-3 list-decimal space-y-1.5 pl-5 marker:text-lavender-500">
          <li>
            Click that message. It opens <Path>System Settings → Privacy &amp; Security → Accessibility</Path>.
          </li>
          <li>
            Turn on the switch next to <Path>Strata</Path>.
          </li>
        </ol>
        <p className="mt-3">That’s it. The bar appears at the bottom of your screen.</p>
      </>
    ),
  },
]

export default function Install() {
  return (
    <Section id="install" eyebrow="Install" title="Up and running in three steps." intro="Takes about a minute. You only do this once.">
      <ol className="mx-auto grid max-w-5xl gap-5 lg:grid-cols-3">
        {steps.map((s, i) => (
          <li key={s.title} className="rounded-2xl border border-zinc-200 p-6 text-zinc-600">
            <div className="mb-4 flex h-9 w-9 items-center justify-center rounded-full bg-lavender-600 font-semibold text-white">{i + 1}</div>
            <h3 className="mb-2 text-lg font-semibold text-zinc-900">{s.title}</h3>
            {s.body}
          </li>
        ))}
      </ol>
    </Section>
  )
}
