import Section from './Section'

// Each key: what's printed on the keycap, and what a screen reader says.
type Key = [cap: string, name: string]

const rows: { keys: Key[]; result: string }[] = [
  { keys: [['←', 'Left arrow'], ['→', 'Right arrow'], ['↑', 'Up arrow'], ['↓', 'Down arrow']], result: 'Left, right, top or bottom half' },
  { keys: [['U', 'U'], ['I', 'I'], ['J', 'J'], ['K', 'K']], result: 'Top-left, top-right, bottom-left, bottom-right corner' },
  { keys: [['D', 'D'], ['F', 'F'], ['G', 'G']], result: 'Left, middle or right third' },
  { keys: [['E', 'E'], ['T', 'T']], result: 'Left or right two-thirds' },
  { keys: [['Return', 'Return']], result: 'Fill the screen' },
  { keys: [['C', 'C']], result: 'Centre' },
  { keys: [['Delete', 'Delete']], result: 'Back to its old size' },
  { keys: [['1–9', '1 to 9']], result: 'Open your 1st–9th pinned app' },
]

function Kbd({ cap, name }: { cap: string; name: string }) {
  return (
    <kbd aria-label={name} className="inline-flex h-8 min-w-8 items-center justify-center rounded-md border border-zinc-300 border-b-2 bg-white px-2 font-sans text-sm font-medium text-zinc-800">
      {cap}
    </kbd>
  )
}

export default function Shortcuts() {
  return (
    <Section
      id="shortcuts"
      eyebrow="Shortcuts"
      title="Snap windows from the keyboard."
      intro={
        <>
          Hold <Kbd cap="⌃" name="Control" /> <Kbd cap="⌥" name="Option" /> and press a key. You can turn the shortcuts off in Settings.
        </>
      }
      tinted
    >
      <div className="mx-auto max-w-3xl overflow-hidden rounded-2xl border border-zinc-200 bg-white">
        <table className="w-full text-left">
          <thead className="border-b border-zinc-200 bg-lavender-50 text-sm text-zinc-500">
            <tr>
              <th scope="col" className="px-4 py-3 font-medium sm:px-6">⌃⌥ +</th>
              <th scope="col" className="px-4 py-3 font-medium sm:px-6">Window goes to</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-100">
            {rows.map((r) => (
              <tr key={r.result}>
                <td className="px-4 py-3 sm:px-6">
                  <div className="flex flex-wrap gap-1.5">
                    {r.keys.map(([cap, name]) => (
                      <Kbd key={cap} cap={cap} name={name} />
                    ))}
                  </div>
                </td>
                <td className="px-4 py-3 text-zinc-700 sm:px-6">{r.result}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-6 text-center text-zinc-600">
        Add <Kbd cap="⌘" name="Command" /> (⌃⌥⌘ + ← / →) to move a window to the other monitor.
      </p>
    </Section>
  )
}
