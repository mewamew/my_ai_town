// 建镇的诊断输出。在 Node 里跑生成器（测试、内置地图脚本）时设置环境变量 MAPGEN_DEBUG=<文件路径>，
// 各环节的失败原因逐行异步追加到这个文件；不设置时 debug 是 null，调用处写 debug?.(…)，诊断内容不会被计算。
// 建镇页在网页的工作线程里跑生成器，没有 process 和文件系统，这时 debug 一律是 null。
const file = globalThis.process?.env?.MAPGEN_DEBUG
/** 一行写完再写下一行，诊断按发生的先后排 */
let written = Promise.resolve()
/** 写文件的模块只在 Node 里、真的要写诊断时才加载；名字放在变量里，网页打包时不去解析它 */
const FS_MODULE = 'node:fs/promises'

export const debug = file
  ? (line) => {
      written = written
        .then(async () => {
          const { appendFile } = await import(/* @vite-ignore */ FS_MODULE)
          await appendFile(file, line + '\n')
        })
        .catch(() => {})
    }
  : null
