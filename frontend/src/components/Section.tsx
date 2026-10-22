import type { ReactNode } from 'react'

interface Props {
  id: string
  eyebrow: string
  title: string
  intro?: ReactNode
  tinted?: boolean
  children: ReactNode
}

export default function Section({ id, eyebrow, title, intro, tinted = false, children }: Props) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className={`px-4 py-20 sm:px-6 sm:py-28 ${tinted ? 'bg-lavender-50' : ''}`}>
      <div className="mx-auto max-w-6xl">
        <div className="mx-auto mb-12 max-w-2xl text-center sm:mb-16">
          <p className="inline-block rounded-full bg-chartreuse px-3 py-1 text-xs font-semibold tracking-wide text-zinc-900 uppercase">{eyebrow}</p>
          <h2 id={`${id}-title`} className="mt-4 text-3xl font-bold tracking-tight text-balance sm:text-4xl">
            {title}
          </h2>
          {intro && <p className="mt-4 text-lg text-pretty text-zinc-600">{intro}</p>}
        </div>
        {children}
      </div>
    </section>
  )
}
