// 声音开关记在本机：读不到或写不进本地存储时按开处理，当前页的设置照样生效。
export function readSwitch(key: string): boolean {
  try {
    return localStorage.getItem(key) !== 'false'
  } catch {
    return true
  }
}

export function saveSwitch(key: string, enabled: boolean) {
  try {
    localStorage.setItem(key, String(enabled))
  } catch {
    /* 当前页设置仍然生效 */
  }
}

export function readPreference(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

export function savePreference(key: string, value: string | null) {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {
    /* 当前页设置仍然生效 */
  }
}
