import type { ReactNode } from 'react'
import { ISSUES_URL, REPO_URL } from '../release'
import Section from './Section'

const link = 'font-medium text-lavender-700 underline-offset-2 hover:underline'

const items: { q: string; a: ReactNode }[] = [
  {
    q: 'Is Strata free?',
    a: (
      <>
        Yes, completely. It’s open source under the MIT license, and the code is on{' '}
        <a className={link} href={REPO_URL}>GitHub</a>.
      </>
    ),
  },
  {
    q: 'Why does my Mac warn me when I open it?',
    a: 'Apple charges developers every year to register their apps. Strata is free, so it isn’t registered, and macOS shows a warning the first time. Follow step 2 of the install guide above to open it anyway. You only need to do this once.',
  },
  {
    q: 'Why does it need Accessibility permission?',
    a: 'That’s how macOS lets an app see which windows are open, switch between them, and move or resize them. Strata doesn’t ask for Screen Recording and can’t see what’s inside your windows.',
  },
  {
    q: 'Which Macs does it work on?',
    a: 'Any Mac running macOS 14 (Sonoma) or newer, with Apple silicon or an Intel chip.',
  },
  {
    q: 'How do I change settings?',
    a: 'Right-click an empty spot on the bar and choose Settings. There you can change the icon size, turn on Launch at login, and more.',
  },
  {
    q: 'How do I update?',
    a: 'Download the new version and replace the old Strata in your Applications folder. Your settings and permission are kept.',
  },
  {
    q: 'How do I uninstall it?',
    a: 'Right-click the bar and choose Quit Strata. Then drag Strata from Applications to the Trash.',
  },
  {
    q: 'Buttons don’t show up, or windows won’t move.',
    a: 'Check that Strata is turned on in System Settings → Privacy & Security → Accessibility. If it is, turn it off and on again.',
  },
  {
    q: 'I found a bug.',
    a: (
      <>
        Please <a className={link} href={ISSUES_URL}>open an issue on GitHub</a> and describe what happened.
      </>
    ),
  },
]

export default function Faq() {
  return (
    <Section id="faq" eyebrow="FAQ" title="Questions and answers.">
      <div className="mx-auto max-w-3xl divide-y divide-zinc-200 border-y border-zinc-200">
        {items.map((item) => (
          <details key={item.q} className="group">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 py-5 text-lg font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lavender-600 [&::-webkit-details-marker]:hidden">
              {item.q}
              <svg viewBox="0 0 20 20" fill="currentColor" className="h-5 w-5 shrink-0 text-tomato transition-transform group-open:rotate-45" aria-hidden="true">
                <path d="M10 4a1 1 0 0 1 1 1v4h4a1 1 0 1 1 0 2h-4v4a1 1 0 1 1-2 0v-4H5a1 1 0 1 1 0-2h4V5a1 1 0 0 1 1-1z" />
              </svg>
            </summary>
            <p className="pb-5 text-zinc-600">{item.a}</p>
          </details>
        ))}
      </div>
    </Section>
  )
}
