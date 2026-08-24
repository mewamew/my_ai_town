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
3. 草稿发行：只允许从最新 `main` 手动运行；完整复用前两组检查后，正式导出 Windows、macOS 与 Android，验证下载包内容，最后建立尚未公开的 GitHub Draft Release。

最近一次失败并不是 GitHub 环境不稳定，而是同一批提交中同时存在两个问题：

- 代码引用了一个本地存在、但没有进入提交的新服务文件。
- 界面适配代码新增了一处可以直接调用、却使用了动态调用的写法。

第一个问题导致 Godot 导入失败，第二个问题导致防复发检查失败，所以 GitHub 上看起来像两个检查项同时出错。补交缺失文件并改成直接调用后，后续两次 CI 均通过。

测试套件中如果某个场景使用 `await process_frame` 或等待异步 UI 回调，调用方也必须使用 `await` 串行等待。否则后续场景会在前一个场景尚未释放页面和测试夹具时继续运行，表现为偶发空数组、越界和退出时资源泄漏；修复时先按场景边界补上 `await`，再把会直接索引数组的断言改为先检查长度，避免二次崩溃掩盖第一条真实失败。

活动气泡的想法页和行动页共用同一套控件时，切换页面必须同时清理上一页的文字、可见状态和分页游标；只隐藏旧标签会让审计快照、辅助功能读取或下一次布局继续看到残留内容。活动专项测试应覆盖“想法页显示文字”和“行动页文字为空”两个边界。

独立 `SceneTree` 专项在断言通过后也必须走项目级退出清理：先调用 `TownAudioController.prepare_shutdown()`，再把退出操作延迟至少两个 `process_frame`。直接 `quit()` 可能留下音乐流、播放对象或仍排队的音频回调，功能标记会通过，但 runner 会按 ObjectDB 泄漏判失败。

正式 Godot 测试默认使用 `AI_TOWN_PROVIDER_TEST_NO_NETWORK=1`，避免读取开发机上的个人 Provider 配置并在退出时留下未完成的健康检查请求。需要联网的专项验证必须显式设置为 `0`，不能让正式离线回归依赖本机配置或外部服务。

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
AI_TOWN_PROVIDER_TEST_NO_NETWORK=1 \
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
- Windows 与 Android 导出任务运行在 Linux 构建机，macOS 导出任务运行在 macOS 构建机；不要把需要 Apple 签名工具的 macOS 导出移到 Linux。
- 工作流完成后先下载 Windows、macOS 与 Android 包人工试玩，确认包内有游戏、`更新日志.md` 和 `build-info.json`，再把 Draft Release 对外发布。
- Android 连续发行前应在仓库 Actions secrets 配置持久签名密钥；未配置时工作流只会生成临时密钥，适合本次测试/内测安装，不适合覆盖安装后续版本。

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

### 活动气泡切换页面后仍读到上一页文字

表现：`town_activity_test.gd` 在“想法页显示普通气泡文字”或“动作页收起普通想法气泡文字”处失败；画面上旧文字可能暂时不可见，但审计快照仍能读到上一页内容。

直接原因：想法页和行动页复用同一个 Label，切到行动页时只设置了 `visible=false`，没有清空 `text`；同时快照缺少明确的想法页可见状态字段，导致视觉状态与检查结果不一致。

处理方法：在行动页渲染入口清空想法 Label 的文字并关闭可见状态；在审计快照中同时报告想法气泡是否实际可见。修改后运行 `town_activity_test.gd`，再运行完整正式故事检查。

### 2026-08-19：正式套件在依赖安装阶段被取消

表现：防复发守卫已经通过，`formal-suite` 没有进入 Godot 导入或正式测试；日志停在 `Install dependencies`，任务运行约两小时后出现 `The operation was canceled`。

直接原因：工作流无条件执行 `apt-get update`，Ubuntu runner 访问 `azure.archive.ubuntu.com` 时持续重试，导致安装步骤占满工作流的 120 分钟超时。这个失败不代表项目代码或测试本身失败。

处理方法：工作流先检查 `zsh`、`rg` 和 `unzip`，runner 已预装时跳过包管理器；确实缺少工具时才执行安装，并为 APT 请求、锁等待和整个更新/安装步骤设置有限重试与超时。不要只重复运行同一个卡住的工作流，也不要把依赖镜像问题误判成 Godot 回归。

最终验证：本地仍需运行 `tools/guards/run_guards.sh`、Godot 无头导入和正式测试；远端应确认依赖步骤能在有限时间内结束，然后才判断正式套件结果。

### 2026-08-20：Android 正式导出提示 `Could not find release keystore`

表现：Windows 与 macOS 构建成功，Android 构建在 `Signing release APK` 阶段输出 `Could not find release keystore, unable to export`，随后报告 `Project export for preset "Android" failed`。这不是脚本导入或 Android 架构配置错误，APK 已经完成资源组装，只是在签名步骤被 Godot 拒绝。

直接原因：Android 导出预设启用了 `package/signed=true`，但 GitHub runner 是一次性环境，默认没有开发机上的 release keystore；仅安装 Godot、导出模板和 Android SDK 不会自动提供项目的发布签名。

处理方法：发行工作流在 Android 构建任务中优先读取 `ANDROID_RELEASE_KEYSTORE_B64`、`ANDROID_RELEASE_KEYSTORE_PASSWORD` 和 `ANDROID_RELEASE_KEYSTORE_ALIAS` 三个 Actions secret，写入 runner 临时目录，并通过 `GODOT_ANDROID_KEYSTORE_RELEASE_*` 环境变量交给 Godot。测试/内测阶段如果尚未配置持久密钥，工作流会生成随机临时 RSA 密钥让 APK 可以安装，同时明确给出警告；配置持久密钥后，后续版本才能覆盖安装并保持 Android 更新链。无论使用哪种密钥，写入 `GITHUB_ENV` 前都必须调用 Actions 的 `add-mask` 保护密码，不能让步骤环境摘要泄露签名凭据。

最终验证：Android 导出日志应出现 `Signing release APK` 后正常完成，不能出现 `Could not find release keystore`；`release_tool.py verify` 还必须确认压缩包中存在 `.apk`、`更新日志.md` 和 `build-info.json`。发布前先检查 Actions secret 是否已经替换临时签名方案。

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

### 删除脚本后预加载检查读取不存在文件

表现：计划内删除了已跟踪的 `.gd`，尚未暂存时运行防复发检查，
`preload_resource_check.py` 在 `read_text()` 报 `FileNotFoundError`。

直接原因：`git ls-files` 在删除尚未写入索引时仍返回旧路径，检查脚本把 Git 清单误当成当前工作树
文件清单。

处理方法：预加载检查只扫描 Git 清单中当前仍真实存在的 GDScript；删除后的旧引用继续由 Godot
无头导入和文本搜索确认。不要为了让检查通过而提前暂存、恢复空文件或忽略真正缺失的预加载目标。

最终验证：保持删除未暂存，运行 `tools/guards/run_guards.sh`，预加载检查应正常完成；随后确认
`git diff --check`、Godot 无头导入和相关领域测试均通过。

### Windows 保存后无法继续，日志出现临时 `owner.json` 清理失败

表现：存档主体已经完成并且多次读取哈希一致，但保存退出或恢复存档后，程序仍报告事务未完成；Windows 日志中的失败路径通常以 `owner.json` 结尾，旧式路径可能超过 260 个字符，macOS 不一定复现。

直接原因：临时锁目录继续叠加在包含槽位、会话、修订和恢复次数的深层目录下。Windows 用户目录稍长时，临时所有者文件会越过传统路径边界；如果递归清理还持有目录遍历句柄，删除也会继续失败。

处理方法：恢复事务锁和槽位事务锁使用浅层固定长度目录，路径由业务身份的稳定摘要映射，`owner.json` 继续校验锁路径和进程身份；Agent 快照、会话照片和正式归档的写入中间文件统一放在各自存储根目录的浅层临时区；超长居民身份映射为固定长度运行时目录。递归清理统一从绝对路径进入，并在删除目录前释放遍历对象。不要通过删除玩家存档或要求玩家修改注册表来规避。

最终验证：`windows_directory_cleanup_test.gd` 必须分别构造旧式长度不少于 260 字符的恢复事务锁、槽位事务锁、Agent 快照、会话照片、正式归档和居民运行时记忆路径，完成实际事务建立、写入、重新读取和递归清理，同时确认新的临时路径保持在传统边界内。当前最低检查数为 56。Godot 项目与发行工作流继续固定使用 4.7 或更新版本，以获得引擎 Windows 文件层的原生长路径处理。

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

### 世界运行时架构检查失败

常见提示：`TownWorldRuntime 架构棘轮失败（指标只降不升）`。

含义：世界总控的行数、函数、顶层状态或长函数数量增加，或者 `world/runtime` 子模块新增了
对 `TownWorldRuntime` 私有成员的直接访问。总访问数没有增加，也不代表可以把访问转移到新的
私有成员；检查会同时限制总数、单个成员次数和新增成员。

处理方式：把状态和规则交给有明确职责的模块，并通过小型接口传入依赖。真实完成拆分且所有
验证通过后，才运行 `world_runtime_architecture_check.py --update` 收缩基线。脚本会拒绝提高任一
旧指标，不能手工调高 JSON 数字绕过检查。

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

### Agent 离线套件受本机 Provider 设置影响

表现：子测试已经输出各自的 `*_PASS`，但 macOS 本地运行时大量用例退出报告同一批模型资源仍在
使用；远端干净环境可能全部通过。本机 `user://` 中通常已经保存 Provider 和默认模型。

直接原因：项目自动加载的启动流程读取玩家本机设置后发起后台健康检查。测试逻辑本身没有请求
联网，但子进程继承了项目自动加载状态，尚未完成的请求在退出时被 runner 识别为资源占用。

处理方法：Agent 离线 runner 对每个非联网子测试设置
`AI_TOWN_PROVIDER_TEST_NO_NETWORK=1`，正式故事套件也在入口统一设置该环境变量；正式 CI 和本地完整命令
继续显式禁止非测试网络请求。联网 Provider 用例不使用这项开关。不要删除本机玩家配置，
也不要放宽 runner 对行首 `ERROR:` 的判断。

最终验证：在已经保存 Provider 配置的本机重新运行完整离线套件，必须得到
`AGENT_TEST_SUMMARY passed=48 failed=0 total=48`，并确认没有模型资源占用错误。

### 正式故事测试退出报告健康检查资源泄漏

表现：居民移动或界面断言已经打印通过标记，但 Godot 退出时报告多个模型 Provider 脚本仍在使用、请求资源未释放，正式测试运行器因此失败。

直接原因：测试启动页会读取本机保存的 Provider 配置并自动发起健康检查；短测试在请求完成前退出，外部请求和回调状态被一起带到进程结束。

处理方法：正式测试运行器默认导出 `AI_TOWN_PROVIDER_TEST_NO_NETWORK=1`，让启动页跳过个人配置的联网健康检查；需要验证真实 Provider 时，单独显式设为 `0`，并使用对应的联网测试入口。测试本身仍需按统一收尾等待自动加载节点初始化、释放音频和测试夹具。

最终验证：居民展示、居民速度稳定性和完整正式故事套件在无网络测试环境中通过，退出日志没有 `ObjectDB instances were leaked`、`resources still in use` 或行首 `ERROR:`。

### 发行工作流拒绝运行

常见提示包括“只能从 main 分支手动运行”“当前提交不是远端 main 的最新提交”或“标签已存在”。这些是防止从旧代码发行、覆盖已有版本的检查项，不应删除。

处理顺序：先确认工作流选择的是 `main`，再同步远端最新提交；如果版本标签已经存在，更新 `VERSION` 和本批更新日志后重新提交。不要删除标签或旧 Release 来复用同一个版本号。

### 导出成功，但玩家下载包校验失败

Windows 包必须同时包含 `.exe` 与 `.pck`，macOS 包必须包含 `.app/Contents/MacOS` 下的程序，Android 包必须包含 arm64 `.apk`；三个包的顶层目录都必须有 `更新日志.md` 和与 `VERSION` 一致的 `build-info.json`。

先从日志第一条 `RELEASE_ERROR` 检查导出路径、预设名称与构建信息，不要绕过 `release_tool.py verify` 直接上传。若调整包结构，必须同时补充发行工具测试，确保 macOS 程序权限等压缩包属性不会丢失。

### macOS 正式导出缺少 Xcode 命令行工具

表现：macOS 导入检查通过，但正式导出提示 `Code signing: Xcode command line tools are not installed`，随后出现 `Project export for preset "macOS" failed`。

直接原因：带临时签名的 macOS 导出任务运行在 Linux 构建机。Godot 可以在 Linux 上准备部分 macOS 资源，但无法调用 Apple 的签名工具完成当前预设。

处理方式：让 macOS 构建项使用 GitHub 的 macOS 构建机，并下载 Godot 的 macOS universal 编辑器；导出模板安装到 macOS 的 Godot 用户目录。Windows 构建项继续使用 Linux 构建机，不要关闭签名检查来绕过失败。

最终验证：远端工作流中 Windows、macOS 与 Android 构建项分别完成正式导出和包内容复查，随后才允许建立包含三个平台资源的 Draft Release。

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

### 2026-08-19：独立正式入口在无帧率限制的 headless 环境误报化身未落地

表现：独立正式入口测试偶发报告 `actual=avatar_descent expected=avatar_active`，同一次启动的 Agent Gateway 错误属于测试故意覆盖的失败分支；重新运行时可能通过。

直接原因：化身落地动画按毫秒推进，测试却只等待固定的 120 个 `process_frame`。无 vsync 的 headless runner 可以在动画达到 1.1 秒前跑完这些帧，导致把正常的时间动画误判为未完成。

处理方法：测试改为等待真实运行时进入 `avatar_active`，设置明确的毫秒超时；保留生产入口和动画实现不变，不用增加固定帧数来掩盖时序问题。

最终验证：独立正式入口连续运行两次均输出 `ISOLATED_FORMAL_ENTRY_STORY_PASS`，正式故事套件仍为 `FORMAL_RELEASE_STORY_SUITE_PASS checks=15 skipped=0`。

### 2026-08-17：活动想法页切换行动页残留文字

表现：完整发行故事检查在活动专项中失败，想法页显示断言和行动页清理断言不稳定；其余活动运行时检查正常。

直接原因：复用的想法文字控件在切换到正式行动页时只隐藏没有清空，测试审计因此读到旧文本；测试还缺少 `semanticThoughtBubbleVisible` 的明确快照字段。

处理方法：清空行动页的想法 Label，补充快照可见状态，并让活动套件等待异步场景完成后再进入下一项。

最终验证：活动专项 `TOWN_ACTIVITY_PASS checks=1660`，完整正式故事检查 `FORMAL_RELEASE_STORY_SUITE_PASS checks=15 skipped=0`。

### 2026-08-17：独立画面专项退出时音频对象泄漏

表现：居民化身脚点遮挡、室内墙体遮挡和凭据隔离专项的功能通过标记已经输出，但 runner 仍报告 `ObjectDB instances were leaked at exit`；详细日志显示 `AudioStreamWAV` 和 `AudioStreamPlaybackWAV`。

直接原因：这些专项直接构造 `TownBase` 或读取全局音频控制器，测试收尾时立即 `quit()`，没有停止全局音乐播放和等待节点、解码器释放。

处理方法：专项收尾先调用全局 `TownAudioController.prepare_shutdown()`；涉及场景树的测试再通过 deferred 退出等待两个 `process_frame`。凭据隔离专项必须传入非 `ai-town` 的 `AI_TOWN_QA_PROJECT_NAME`，保持用户目录隔离合同。

最终验证：三个专项均输出通过标记，runner 不再报告资源泄漏；完整发行验证和隔离入口继续通过。

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

### 2026-08-24：正式入口第二次保存因入镇过渡动作未登记而失败

表现：Agent 离线套件、正式故事检查和防复发守卫均通过；独立正式入口故事在首次启动失败后重试成功，但第二次手动保存返回 `SESSION_SAVE_WORLD_PREPARE_FAILED`，底层错误为“居民当前动作未登记在 `usedActionIds`”。

直接原因：居民在第一天从南入口进入小镇时，`TownResidentArrivalRuntime` 会直接写入一条过渡动作，却没有同步写入该居民的已使用动作集合。保存快照带着当前动作进入恢复校验时，恢复层会按合同拒绝这份不完整状态。这个路径受无头 runner 的时间推进影响，macOS 本地不一定稳定复现。

修复：创建入镇过渡动作时立即登记对应的 `action_id`；在错过首次保存窗口的回归场景中增加“当前动作必须已登记”的断言。不要放宽恢复校验，也不要删除玩家存档来绕过。

最终验证：先运行入镇与存档相关测试，再运行 Agent 离线套件、15 项正式故事、独立正式入口和测试后源码清洁检查；独立正式入口必须完成首次失败补偿、重试进入小镇和第二次保存。

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
- [ ] 世界核心改动没有增加总控规模或 `world._xxx` 私有访问；真实拆分后已收缩架构基线。
- [ ] `tools/guards/run_guards.sh` 通过。
- [ ] Godot 无头导入没有脚本或引擎错误。
- [ ] 相关测试通过；发行改动完成正式测试套件。
- [ ] provider 测试退出时没有资源泄漏；同步 transport 已确认不会残留请求状态或 watchdog。
- [ ] 正式 Godot 回归默认使用 `AI_TOWN_PROVIDER_TEST_NO_NETWORK=1`；联网 Provider 验证单独运行并显式授权。
- [ ] CI 工作流依赖步骤先检查 `zsh`、`rg` 和 `unzip`，只有缺少工具时才执行带超时的 APT 安装。
- [ ] 发行工作流改动确认 Windows 与 Android 使用 Linux 构建机、macOS 使用 macOS 构建机。
- [ ] 测试后 `git status --porcelain` 没有意外变化。
- [ ] 玩家可见改动已经写入根目录 `更新日志.md`，并已同步 README 的最新更新摘要。
- [ ] 提交后在干净临时工作区复查一次，再推送。
