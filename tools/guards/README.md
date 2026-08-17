# 防复发守卫（屎山消灭计划 批次 A）

机制与口径的权威定义在 `docs/屎山消灭计划.md`（批次 A、铁律第 2 条）。本目录是可执行实现。

一键运行（CI 与本地验收共用）：

```sh
tools/guards/run_guards.sh
```

## 十项固定检查

| 脚本 | 判定 | 基线/清单 |
|---|---|---|
| `line_ratchet.py` | 受控文件行数只降不升 | `line_ratchet.json` |
| `world_runtime_architecture_check.py` | 世界总控规模与子模块私有访问只降不升 | `world_runtime_architecture_baseline.json` |
| `dynamic_call_scan.py` | 白名单外新增动态调用即失败 | `dynamic_call_baseline.json` + `dynamic_call_whitelist.json` |
| `zero_reference_scan.py` | 白名单/基线外新零引用候选即失败 | `zero_reference_baseline.json` + `zero_reference_whitelist.json` |
| `required_tests_check.py` | 必须存在的测试缺失、重复注册、checks=N 未钉住即失败 | `required_tests.json` |
| `preload_resource_check.py` | GDScript 中字面量或编译期字符串拼接的 `res://` 预加载文件缺失即失败 | 已跟踪的 `game/**/*.gd` |
| `cross_platform_text_check.py` | 文本统一以 LF 检出，字节摘要约束不受 Windows 换行转换影响 | `.gitattributes` + 白模冻结清单 |
| `foreground_shader_check.py` | 前景局部遮挡保留裁切，并禁止重复乘算地图纹理造成画面变暗 | `MapRuntimeOcclusionLayer.gd` |
| `sync_readme_updates.py --check` | 仓库首页的最近更新摘要与玩家更新日志一致 | `更新日志.md` |
| `release/test_release_tool.py` + `release_tool.py source-check` | 版本号格式、双平台打包结构、构建信息和校验和符合发行约定 | `VERSION` + `更新日志.md` |

状态字段迁入专用状态对象、私有成员名因此改变时，使用
`world_runtime_architecture_check.py --update --rename-private-access _旧成员=_新成员`。
只有旧访问已经清零、且新访问次数不高于旧基线时才允许迁移；普通拆分仍直接使用 `--update`
收缩基线。

## 动态调用清单制要点

- 条目标识 = 文件路径 + 所在函数名 + 归一化调用内容（无行号，多重集计数）。
- 扫描范围 = `game/` 生产 `.gd`，递归排除 `**/tests/**`、`**/preflight/**`、
  `**/validation/**`、`game/addons/`，叠加 `test_classification.json` 已分类脚本。
- 覆盖形式：`.call("…")`（含换行参数）、`.call(&"…")`、`callv`、
  `Callable(obj, "名字")`、变量方法名。
- **variable 类条目的说明**：`cb.call(x)` 形式静态上无法区分"Callable 实例的合法
  调用"与"obj.call(变量方法名) 动态派发"。两者都进清单；新增时由评审判断，
  确认是 Callable 实例调用的加白名单，理由写"Callable 实例调用，非字符串派发"。
- **纯搬运迁移通道**：文件移动/重命名、函数重命名用
  `dynamic_call_scan.py --rebaseline-moves`——只有调用内容多重集完全不变才允许
  改写基线；内容有增删走常规通道。
- 清理后收缩基线：`--write-baseline`（有新增条目时拒绝写入，防"顺手加回"）。

## 零引用候选的语义说明

- `tscn:` 候选 = 场景文件的 res:// 路径与文件名在仓库其他文本零出现（同名歧义：
  不同目录同名场景会互相"抵消"引用，漏报可能、误报不会）。
- `class:` 候选 = `class_name X` 标识符在定义文件外零出现。**这说明 class_name
  声明未被使用，不等于文件是死代码**（文件可能仍被 preload 路径引用）；
  处置通常是删多余的 class_name 声明或删除确认后的死文件，二者都会让候选消失。

## 测试脚本八类分类（`test_classification.json`）

每个门禁/测试脚本归入八类之一：**自动测试 / 联网测试 / 预检查 / 手工预览 /
截图采集 / 资产工具 / 夹具 / 辅助**。保留为联网、手工或工具脚本都是合法归宿。
分类是贯穿批次 B-H 的工作流；全部分类完成后再单独切换 runner 自动发现
（切换前 `run_formal_release_story_suite.sh` 的手写清单照常工作）。

## 套件防缩水（铁律第 2 条）

- `required_tests.json` 是必须存在的测试 ID 清单，清单项缺失即红。
- 测试合并或删除：在 PR 里证明覆盖未减少，同步更新清单基线。
- 已输出 `checks=N` 的测试在 runner 通过标记里钉住计数（`pinned_checks`），
  其余测试补上计数后逐个纳入；不设全套件断言总数指标。
