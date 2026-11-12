// 建镇：生成器在网页的工作线程里跑，不卡住页面（见 localCreation.ts）。
// 收到 { spec }，生成过程中发 { stage }，最后发 { result } 或 { error }。
import { generate } from '../../../../scripts/mapgen/generate.mjs'
import library from '../../../../data/mapgen/templates.json'
import contours from '../../../../data/mapgen/contours.json'
import definitions from '../../../../data/props/core/definitions.json'

self.onmessage = (event: MessageEvent<{ spec: unknown }>) => {
  try {
    const result = generate(event.data.spec, library, contours, definitions, {
      onStage: (stage: unknown) => self.postMessage({ stage }),
    })
    self.postMessage({ result })
  } catch (error) {
    const e = error as { message?: string; code?: string; details?: Record<string, unknown> }
    self.postMessage({
      error: {
        message: e.message ?? String(error),
        code: e.code ?? 'GENERATION_FAILED',
        details: e.details ?? {},
      },
    })
  }
}
