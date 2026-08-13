# My AI Town CI 排查手册

这份文档用于处理 GitHub Actions 的重复失败。目标不是反复点“重新运行”，而是在推送前发现提交不完整、脚本无法导入、检查配置遗漏等问题。

## 维护方式

- 每次 CI 失败先查本文档，不要先重复运行。
- 原因与已有案例相同时，按照现有处理顺序修复，不重复增加同类条目。
- 出现新的失败原因时，在“已发生案例”中追加表现、直接原因、修复方法和最终验证结果。
- 修复方式已经稳定后，再补充到“常见失败与处理方法”，让后续提交可以在推送前发现它。

## 先看结论

当前 CI 主要有两组日常检查，另有一条手动发行流程：

1. 防复发检查：检查文件行数、动态调用、零引用候选和正式测试清单。
2. 正式测试：导入 Godot 项目，运行 Agent 离线测试、正式故事测试和独立正式入口测试，最后确认测试没有修改源码目录。
3. 草稿发行：只允许从最新 `main` 手动运行；完整复用前两组检查后，正式导出 Windows 与 macOS，验证下载包内容，最后建立尚未公开的 GitHub Draft Release。

最近一次失败并不是 GitHub 环境不稳定，而是同一批提交中同时存在两个问题：

- 代码引用了一个本地存在、但没有进入提交的新服务文件。
- 界面适配代码新增了一处可以直接调用、却使用了动态调用的写法。

第一个问题导致 Godot 导入失败，第二个问题导致防复发检查失败，所以 GitHub 上看起来像两个检查项同时出错。补交缺失文件并改成直接调用后，后续两次 CI 均通过。

## 推送前固定检查

### 1. 确认提交里到底有什么

CI 只能看到 Git 提交，无法看到本机未跟踪文件。

```sh
git status --short
git diff --cached --name-status
git diff --cached --check
```

重点检查：

- `??` 开头的文件尚未进入提交。
- 新增 `.gd` 文件时，确认对应的 `.gd.uid` 是否也需要提交。
- 新增测试、预览或工具脚本时，确认已经更新 `tools/guards/test_classification.json`。
- 删除或移动文件后，搜索是否还有旧路径引用。
- 根目录 `更新日志.md` 是否已经同步本批玩家可见改动。

如果代码中新增了 `preload()` 或 `load()` 路径，使用下面的命令确认目标文件已经被 Git 跟踪：

```sh
git ls-files --error-unmatch path/to/file.gd
```

命令失败就表示该文件不会出现在 CI 中。

### 2. 先运行防复发检查

```sh
tools/guards/run_guards.sh
```

必须看到：

```text
GUARDS_PASS
```

如果失败，不要直接更新基线或白名单，先判断代码能否使用更明确的写法。

### 3. 检查 Godot 项目能否完整导入

设置本机 Godot 路径后运行：

```sh
"$GODOT_BIN" --headless --path game --import 2>&1 | tee /tmp/my-ai-town-import.log
rg -n '^ERROR:|SCRIPT ERROR:|Parse Error:|Failed to load script' /tmp/my-ai-town-import.log
```

第二条命令没有输出才算通过。只看到导入进度完成，不代表脚本没有报错。

### 4. 运行与 CI 相同的正式测试

```sh
"$GODOT_BIN" --headless --path game --script res://tests/agent/run_agent_tests.gd
zsh game/tests/run_formal_release_story_suite.sh
zsh game/tests/run_isolated_formal_entry_story.sh
```

发行前还可以运行：

```sh
zsh game/tests/run_complete_formal_release_validation.sh
```

### 5. 确认测试没有生成遗漏文件

```sh
git status --porcelain
```

测试后如果出现新的 `.gd.uid`、报告文件或其他源码目录改动，CI 最后一步会失败。应确认这些文件应该提交、忽略还是改到临时目录，不能直接带着未处理状态推送。

### 6. 发行前确认版本与玩家文件

手动运行 `build-draft-release` 前逐项确认：

- 工作流从远端最新 `main` 发起，不从功能分支直接发行。
- 根目录 `VERSION` 是本次要使用的新版本，格式为 `x.y.z`，或 `x.y.z-alpha.N`、`x.y.z-beta.N`、`x.y.z-rc.N`。
- 对应的 `v<版本号>` 标签和 GitHub Release 尚不存在，避免覆盖旧版本。
- `更新日志.md` 已涵盖这批玩家可见变化，README 的最近更新摘要已经同步。
- `python3 -m unittest discover -s tools/release -p 'test_*.py'` 与 `tools/guards/run_guards.sh` 均通过。
- Windows 导出任务运行在 Linux 构建机，macOS 导出任务运行在 macOS 构建机；不要把需要 Apple 签名工具的 macOS 导出移到 Linux。
- 工作流完成后先下载 Windows 与 macOS 包人工试玩，确认包内有游戏、`更新日志.md` 和 `build-info.json`，再把 Draft Release 对外发布。

发行工作流只在一次性构建副本中写入 Godot 与系统文件版本，不把发行版本写回开发源码。不要手动修改 `game/project.godot` 的版本字段来替代 `VERSION`。

## 最可靠的复查方式：只检查提交内容

本地工作目录可能存在未提交文件，Godot 可以读取它们，因此本地检查可能出现“错误通过”。提交完成、推送之前，建议从当前提交建立一个临时工作区再检查：

```sh
check_root="$(mktemp -d /tmp/my-ai-town-ci-check.XXXXXX)"
git worktree add --detach "$check_root/worktree" HEAD
cd "$check_root/worktree"

tools/guards/run_guards.sh
"$GODOT_BIN" --headless --path game --import

cd -
git worktree remove "$check_root/worktree"
rmdir "$check_root"
```

这样看到的文件与 CI 更接近。如果这里报缺文件，通常就是文件没有提交或路径大小写不一致。

## 常见失败与处理方法

### Godot 导入：`Preload file ... does not exist`

含义：脚本引用的资源不在 CI 取得的提交中，或者路径不完全一致。

防复发检查会解析单个字符串、带尾逗号以及由多个字符串字面量拼接成的
`preload()` 路径；使用变量或运行时计算路径的加载不属于这项静态检查，仍需依靠
Godot 无头导入确认。

按顺序检查：

1. 文件是否真实存在。
2. `git status --short` 中是否显示为 `??`。
3. `git ls-files` 能否找到该文件。
4. 路径大小写是否与实际文件一致。macOS 常见文件系统可能忽略大小写，Linux CI 会严格区分。
5. 文件移动后是否仍有旧路径引用。

不要只修后续的类型推断错误。缺少预加载文件时，类型推断和依赖脚本编译错误通常都是连带结果，应先修第一条缺文件错误。

### Windows 保存后无法继续，日志出现临时 `owner.json` 清理失败

表现：存档主体已经完成并且多次读取哈希一致，但保存退出或恢复存档后，程序仍报告事务未完成；Windows 日志中的失败路径通常以 `owner.json` 结尾，旧式路径可能超过 260 个字符，macOS 不一定复现。

直接原因：临时锁目录继续叠加在包含槽位、会话、修订和恢复次数的深层目录下。Windows 用户目录稍长时，临时所有者文件会越过传统路径边界；如果递归清理还持有目录遍历句柄，删除也会继续失败。

处理方法：恢复事务锁和槽位事务锁使用浅层固定长度目录，路径由业务身份的稳定摘要映射，`owner.json` 继续校验锁路径和进程身份；Agent 快照、会话照片和正式归档的写入中间文件统一放在各自存储根目录的浅层临时区；超长居民身份映射为固定长度运行时目录。递归清理统一从绝对路径进入，并在删除目录前释放遍历对象。不要通过删除玩家存档或要求玩家修改注册表来规避。

最终验证：`windows_directory_cleanup_test.gd` 必须分别构造旧式长度不少于 260 字符的恢复事务锁、槽位事务锁、Agent 快照、会话照片、正式归档和居民运行时记忆路径，完成实际事务建立、写入、重新读取和递归清理，同时确认新的临时路径保持在传统边界内。当前最低检查数为 56。Godot 项目与发行工作流继续固定使用 4.7 或更新版本，以获得引擎 Windows 文件层的原生长路径处理。

### Windows 检查脚本输出中文时出现 `UnicodeEncodeError`

表现：同一组防复发检查在 macOS 和 Linux 通过，在 `windows-latest` 上却从第一条中文成功提示开始连续报 `UnicodeEncodeError: 'charmap' codec can't encode characters`，最终得到 `GUARDS_FAILED`，后续 Godot 测试全部跳过。

直接原因：Windows GitHub 执行器中的 Python 标准输出仍使用 `cp1252`，仓库检查脚本会打印中文结果；检查逻辑本身已经完成，但输出成功提示时编码失败，进程因此返回非零状态。

处理方法：在需要直接运行仓库 Python 检查脚本的 Windows 工作流中设置 `PYTHONUTF8=1` 和 `PYTHONIOENCODING=utf-8`。不要删除或改写中文提示，也不要把 `GUARDS_FAILED` 当作游戏代码失败继续排查。

最终验证：重新运行 Windows 防复发检查，确认所有中文提示正常输出并出现 `GUARDS_PASS`，随后继续执行同一任务中的 Godot 无窗口导入、Windows 路径回归和正式入口测试；不能只看到编码错误消失就结束验证。

### Windows 正式入口已通过，却把允许的错误行判成失败

表现：正式入口测试已经输出 `GAME_FLOW_HOST_FORMAL_ENTRY_PASS`，测试进程也是成功退出；验收脚本仍报告那条预期的 Agent Gateway 初始化错误属于“额外引擎错误”。同一允许规则在 macOS 的 zsh 脚本中可以通过。

直接原因：Windows 日志使用 CRLF 行尾。PowerShell 只按换行符拆分后，每行末尾仍保留回车，带行尾锚点的精确允许规则因此无法匹配。另一个同时暴露的问题是进程结束后读取 `PeakWorkingSet64` 会得到空值，不能作为性能结果。

处理方法：PowerShell 日志检查使用能够同时识别 CRLF 和 LF 的 `\r?\n` 拆分，再执行精确的整行允许匹配；性能采样在 Godot 进程运行期间定时刷新 `WorkingSet64` 并累计峰值，不能等进程退出后再读取。

最终验证：远端 Windows 正式入口既要输出通过标记、没有额外引擎错误，也要记录非空且大于零的耗时和峰值内存；只有通过标记而性能值为空，仍不算完成 Windows 无窗口性能验收。

### 动态调用检查失败

常见提示：

```text
动态调用守卫失败：以下条目不在基线/白名单内
```

处理顺序：

1. 已知对象类型和方法名时，优先从 `service.call("method")` 改成 `service.method()`。
2. 只有确实需要根据字符串派发方法时，才加入 `dynamic_call_whitelist.json`，并写清原因。
3. 只是移动文件或重命名函数、调用内容没有改变时，才使用 `--rebaseline-moves`。
4. 清理了旧动态调用时，可以用 `--write-baseline` 收缩基线；不能用它掩盖新增调用。

### 行数检查失败

含义：受控文件继续变大，超过现有行数基线。

处理方式：优先拆分职责、提取独立模块或减少重复代码。不要只为了通过 CI 调高基线。

### 零引用检查失败

含义：新增场景或 `class_name` 在其他文件中没有可识别引用。

处理方式：

- 确认是否漏接场景、漏写预加载或漏注册。
- 如果文件由路径动态加载，按实际情况补充白名单和原因。
- 如果确实不再使用，删除文件或多余的 `class_name`。

### 正式测试清单失败

常见原因：

- 新正式测试没有加入 `required_tests.json`。
- 删除或改名测试后，旧测试仍在必须清单里。
- 测试在运行脚本中重复注册。
- 测试输出的 `checks=N` 少于已经固定的最低数量。

测试合并或删除时，要确认覆盖范围没有减少，再同步调整清单。

### 测试通过，但源码目录不干净

CI 最后会检查 `git status --porcelain`。常见来源：

- Godot 自动生成了未提交的 `.gd.uid`。
- 测试把报告写进了 `res://`。
- 测试修改了配置、夹具或缓存文件。

测试产物应写进 `user://` 或系统临时目录。确实属于源码的 UID 应随对应脚本一起提交。

### 通过标记缺失或断言数量减少

测试进程退出并不等于测试成功。正式测试还会检查：

- 是否出现约定的通过标记。
- 是否存在脚本错误、引擎错误或资源泄漏。
- 已固定的测试断言数量是否减少。

应修复测试或功能本身，不要删除通过标记检查。

### provider 测试通过但退出报告资源泄漏

表现：provider 测试输出了约定的 `*_PASS` 标记，功能断言也通过，但退出时出现 `ERROR: N resources still in use at exit`；Agent runner 因此把子测试记为失败。

直接原因：请求完成回调通过闭包捕获请求状态，而请求状态又保存失败回调，形成引用循环；同步注入 transport 最容易触发，因为请求在创建超时看门狗之前就已经完成。

处理方法：在成功、失败、超时和取消的共同结算路径中清空请求状态保存的回调；transport 返回后如果请求已经同步完成，不再创建 watchdog。watchdog 的 `timeout` 信号回调中只能使用 `queue_free()`，不能直接 `free()` 被 Godot 锁定的计时器。不要放宽 runner 对行首 `ERROR:` 或资源泄漏的检查。

最终验证：provider robustness 测试必须覆盖有效宿主节点下的同步 transport，确认请求只结算一次、没有残留在途取消状态，并重新运行 Agent 离线套件和完整正式入口套件。不要把 watchdog 的具体实现（例如宿主子节点数量）写成测试契约，应断言超时、完成和取消的行为。

### 发行工作流拒绝运行

常见提示包括“只能从 main 分支手动运行”“当前提交不是远端 main 的最新提交”或“标签已存在”。这些是防止从旧代码发行、覆盖已有版本的检查项，不应删除。

处理顺序：先确认工作流选择的是 `main`，再同步远端最新提交；如果版本标签已经存在，更新 `VERSION` 和本批更新日志后重新提交。不要删除标签或旧 Release 来复用同一个版本号。

### 导出成功，但玩家下载包校验失败

Windows 包必须同时包含 `.exe` 与 `.pck`，macOS 包必须包含 `.app/Contents/MacOS` 下的程序；两个包的顶层目录都必须有 `更新日志.md` 和与 `VERSION` 一致的 `build-info.json`。

先从日志第一条 `RELEASE_ERROR` 检查导出路径、预设名称与构建信息，不要绕过 `release_tool.py verify` 直接上传。若调整包结构，必须同时补充发行工具测试，确保 macOS 程序权限等压缩包属性不会丢失。

### macOS 正式导出缺少 Xcode 命令行工具

表现：macOS 导入检查通过，但正式导出提示 `Code signing: Xcode command line tools are not installed`，随后出现 `Project export for preset "macOS" failed`。

直接原因：带临时签名的 macOS 导出任务运行在 Linux 构建机。Godot 可以在 Linux 上准备部分 macOS 资源，但无法调用 Apple 的签名工具完成当前预设。

处理方式：让 macOS 构建项使用 GitHub 的 macOS 构建机，并下载 Godot 的 macOS universal 编辑器；导出模板安装到 macOS 的 Godot 用户目录。Windows 构建项继续使用 Linux 构建机，不要关闭签名检查来绕过失败。

最终验证：远端工作流中 Windows 与 macOS 构建项分别完成正式导出和包内容复查，随后才允许建立包含两个平台资源的 Draft Release。

### 正式测试断言读取了错误的数据层

表现：测试中的行为已经正确，但断言从公开投影读取只存在于 World 内部的状态字段，或用显示名称查找按稳定 ID 建立的内部状态表，得到 `null` 并使正式测试退出失败。

处理方式：先确认失败字段是否属于生产入口的公开返回契约；如果只是测试用的内部状态，应从测试 World 的内部居民记录读取，并使用测试已有的稳定 ID 常量，不要用显示名称猜测字典键；另外保留公开投影的行为断言。不要为了让断言通过而把内部调试字段泄露到生产接口。

### 修改活动源数据后，World 启动报告活动收据指纹不匹配

表现：Godot 无头导入和活动专项测试可以通过，但 Agent 离线套件中的正式 Bootstrap 返回 `WORLD_DATA_INVALID`；错误包含“Activity Integration 收据与 exact source fingerprint 不匹配”或“未绑定 exact 七份源文档”。

直接原因：修改了 `world/data/town/source/activity_definitions.json` 等活动源文档，并手动同步了 `town_world.json` 中的业务字段，却没有通过正式构建入口重算 `activityIntegrationReceipt.sourceFingerprint` 和对应文档指纹。只改生成文件里的活动值不能完成来源校验。

处理方法：修改活动源文档后运行：

```sh
"$GODOT_BIN" --headless --path game \
  --script res://world/data/town/TownWorldDataBuild.gd
```

确认输出 `TOWN_WORLD_DATA_BUILD_PASS`，检查生成差异只包含预期业务字段和活动收据，再运行正式 Bootstrap 或 Agent 离线套件。不要手工计算或复制指纹。

## 查看 GitHub CI 日志

先查看 PR 的检查项：

```sh
gh pr checks <PR编号>
```

再查看失败运行：

```sh
gh run view <运行编号> --log-failed
```

日志很多时，只筛选关键错误：

```sh
gh run view <运行编号> --log-failed \
  | rg -n 'GUARDS_FAILED|SCRIPT ERROR:|Parse Error:|^ERROR:|Failed to load script|Process completed'
```

排查时从第一条真实错误开始，不要从最后一条“进程退出”倒推。后面的编译失败、类型推断失败和测试跳过，往往只是第一条错误造成的连锁结果。

## 可以忽略的常见噪声

以下信息单独出现时通常不是本项目 CI 失败原因：

- `cannot connect to daemon at tcp:5037`：CI 没有 Android 调试服务；如果后面没有对应检查失败，可以忽略。
- Node.js 版本弃用提醒：这是 GitHub Action 依赖提醒，不等同于项目测试失败。
- 缓存未命中：只会让运行变慢，不代表功能失败。
- Godot 大量素材导入进度：应继续看到日志末尾的脚本错误检查结果。

## 已发生案例

### 2026-08-14：Windows 无窗口验收被 Python 控制台编码阻断

表现：Windows 测试机完成检出后，防复发检查的行数、动态调用、零引用和正式测试清单脚本都在打印中文成功提示时抛出 `UnicodeEncodeError`；素材、跨平台文本、前景着色器、README 同步和发行工具测试仍能通过，但汇总结果为 `GUARDS_FAILED`，Godot 步骤没有开始。

直接原因：Windows 执行器中的 Python 3.12 标准输出使用 `cp1252`，工作流没有像项目文本契约那样显式固定 UTF-8。

修复：为 Windows 无窗口验收工作流统一设置 `PYTHONUTF8=1` 和 `PYTHONIOENCODING=utf-8`，保留原检查脚本及中文输出不变。

最终验证：修复后的同一提交必须在真正的 `windows-latest` 上先得到 `GUARDS_PASS`，再完成 Godot 无窗口导入、启动页性能记录、传统 260 字符路径回归和正式生产入口主链路。

补充表现：编码修复后的第二次运行中，Godot 正式入口在 43.3 秒后输出通过标记并以 0 退出，但 PowerShell 允许规则受 CRLF 行尾影响仍把唯一的预期错误判为失败；同时进程退出后的 `PeakWorkingSet64` 为空。

补充修复：日志按 `\r?\n` 拆分后再做整行匹配，并在 Godot 运行期间每 100 毫秒采样一次工作集峰值。最终验证必须同时确认主链路通过和性能字段非空。

### 2026-08-12：备餐时长调整后遗漏活动收据重建

表现：食堂活动回归和防复发守卫均通过，远端 Agent 离线套件为 `47/48`；唯一失败的 `agent_debug_lab_test.gd` 在正式 Bootstrap 启动时得到 `WORLD_DATA_INVALID`，后续居民数、存档和恢复断言都是连带失败。

直接原因：统一备餐时长从 60 分钟调整为 30 分钟后，只同步了活动源文档和 `town_world.json` 中的活动定义，没有运行 `TownWorldDataBuild.gd`，导致生成数据仍携带修改前的活动来源指纹。

修复：使用正式世界数据构建入口重新生成 `town_world.json`，同步新的 `activity_definitions.json` 文档指纹和组合来源指纹；随后先单独复查 `agent_debug_lab_test.gd`，再运行完整远端正式套件。

最终验证：修复 head 的 Agent 离线套件、15 项正式故事、独立正式入口和测试后源码清洁检查全部通过；远端正式套件用时 14 分 39 秒，防复发守卫同时通过。

### 2026-08-12：模型请求生命周期修复引入 provider 资源泄漏

表现：快速重开对话修复的 guards 通过，但正式验证中 Agent 离线套件为 `passed=39 failed=9`；9 个 provider 用例都打印了通过标记，随后因 Godot 退出资源泄漏被 runner 判定失败。

直接原因：新请求状态保存了捕获自身的失败结算闭包，provider 测试中的同步 transport 使循环引用一直存活；同步完成后还会继续创建 watchdog。

修复：结算时断开请求状态与闭包的引用，并在 transport 已同步完成时跳过 watchdog；补充同步 transport 的资源释放回归测试。首次回归测试误把 watchdog 假定为宿主子节点，远端使用 `SceneTreeTimer` 时产生了错误断言，随后改为检查请求行为和在途状态。

后续验证：将 watchdog 改为 `SceneTreeTimer` 后，资源释放虽然交给场景树，但有效宿主下的在途请求不再有可检查的计时器节点，导致 watchdog 生命周期断言失败；最终改为宿主下的一次性 `Timer`，结算时同步停止并释放，保留同步完成跳过 watchdog 的处理。

补充表现：在 timeout 信号回调中直接调用 `free()` 会出现 `Object is locked and can't be freed`，即使测试通过标记仍会被 runner 判为失败；应改用 `queue_free()`，并保留同步 transport 不创建 watchdog 的路径。

最终验证：基准提交同一套正式验证为 `48/48`；修复后必须重新确认 Agent 离线套件 `48/48`，并继续完成正式故事和源码目录清洁检查。

### 2026-08-08：发行修复 PR 首次运行失败

表现：

- 防复发检查失败。
- Godot 项目导入失败，后续正式测试全部跳过。

直接原因：

- 居民编辑服务脚本及 UID 在本地存在，但没有进入第一次提交。
- 界面适配层使用了不必要的字符串动态调用。

修复：

- 补交居民编辑服务脚本及 UID。
- 将动态调用改为直接方法调用。

结果：后续代码修复提交和开发日志提交触发的两次 CI 均全部通过。

本案例对应的失败运行：[GitHub Actions 记录](https://github.com/mewamew/my_ai_town/actions/runs/31257786389)。

### 2026-08-11：公告优先级回归测试读取了公开投影中的内部字段

表现：Agent 离线用例和前两项正式故事检查通过；对话正式测试在“玩家公告不打断居民对话”断言处失败，实际值为 `<null>`。

直接原因：测试先通过 `get_resident_state` 的公开投影读取 `decisionPending`，后改读 World 内部居民记录时又用显示名称“林岚”查表；该表按稳定居民 ID 建立，因此两次都得到 `null`。

修复：保留生产接口边界不变，将测试断言改为读取测试 World 内部按 `POSTAL_ID` 索引的居民状态；同步补充对话优先级回归覆盖。

最终验证：修复后重新推送，等待同一远端 head 的正式测试和防复发守卫重新完成。

### 2026-08-11：macOS 发行包在 Linux 构建机导出失败

表现：完整正式验证和 Windows 下载包均通过；macOS 在“正式导出”步骤提示缺少 Xcode 命令行工具，因此没有建立不完整的 Draft Release。

直接原因：Windows 与 macOS 共用了 `ubuntu-latest` 构建机，而 macOS 预设需要 Apple 的签名工具完成临时签名。

修复：为构建矩阵分别指定运行环境；Windows 保持 Linux，macOS 改用 macOS，并按运行环境安装对应的 Godot 编辑器和导出模板。

最终验证：修复提交必须先通过本地发行工具测试、守卫、Godot 无头导入和正式测试；合并后从最新 `main` 重新运行草稿发行，确认两个平台都通过并建立 Draft Release。

本案例对应的失败运行：[GitHub Actions 记录](https://github.com/mewamew/my_ai_town/actions/runs/31484804450)。

## 提交前简表

- [ ] `git status --short` 中没有被遗漏的 `??` 文件。
- [ ] 新增脚本所需的 `.gd.uid` 已确认。
- [ ] 新测试、预览和工具脚本已分类。
- [ ] 所有新增资源路径已经检查大小写，并确认文件被 Git 跟踪。
- [ ] 修改活动源文档后已运行 `TownWorldDataBuild.gd`，并确认活动收据和来源指纹同步更新。
- [ ] 涉及存档目录、事务或临时文件时，Windows 超长路径恢复与清理测试已经通过。
- [ ] 新增 Windows Python 检查任务时已固定 UTF-8 输出，并确认中文检查结果可以正常打印。
- [ ] Windows 日志精确允许规则兼容 CRLF，性能记录在进程运行期间采样且结果非空。
- [ ] `tools/guards/run_guards.sh` 通过。
- [ ] Godot 无头导入没有脚本或引擎错误。
- [ ] 相关测试通过；发行改动完成正式测试套件。
- [ ] provider 测试退出时没有资源泄漏；同步 transport 已确认不会残留请求状态或 watchdog。
- [ ] 发行工作流改动确认 Windows 使用 Linux 构建机、macOS 使用 macOS 构建机。
- [ ] 测试后 `git status --porcelain` 没有意外变化。
- [ ] 玩家可见改动已经写入根目录 `更新日志.md`，并已同步 README 的最新更新摘要。
- [ ] 提交后在干净临时工作区复查一次，再推送。
