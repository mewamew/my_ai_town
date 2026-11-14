import type { GameModeMusic } from '.'

export const frostlightMusic: GameModeMusic<'frostlight'> = {
  order: ['story/finale', 'story/critical', 'tide/final'],
  quietDeaths: false,
  cell(view) {
    if (view.ending) return 'story/finale'
    if (view.phase === 'storm' || view.stress >= 80) return 'story/critical'
    if (view.phase === 'cold') return 'tide/final'
    return null
  },
  sting(view, before) {
    if (view.ending && !before.ending)
      return ['warm_dawn', 'survived'].includes(view.ending.kind) ? 'tide-rise' : 'death'
    if (view.phase === 'storm' && before.phase !== 'storm') return 'tide-announce'
    return null
  },
}
