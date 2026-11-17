import type { WorldSettingsController } from '../worldSettings'

/** 开局入口与世界设定共用一处生命周期，普通向导和预制设置都从这里打开。 */
export function installFirstRun(worldSettings: WorldSettingsController, open: () => void) {
  let openedWorld = ''
  worldSettings.setFirstRun(() => {
    const world = worldSettings.state()?.world_id
    if (!world) return false
    if (openedWorld !== world) {
      openedWorld = world
      open()
    }
    return true
  })
}
