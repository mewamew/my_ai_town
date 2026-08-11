# My AI Town CI 排查手册

这份文档用于处理 GitHub Actions 的重复失败。目标不是反复点“重新运行”，而是在推送前发现提交不完整、脚本无法导入、检查配置遗漏等问题。

## 维护方式

- 每次 CI 失败先查本文档，不要先重复运行。
- 原因与已有案例相同时，按照现有处理顺序修复，不重复增加同类条目。
- 出现新的失败原因时，在“已发生案例”中追加表现、直接原因、修复方法和最终验证结果。
- 修复方式已经稳定后，再补充到“常见失败与处理方法”，让后续提交可以在推送前发现它。

## 先看结论

当前 CI 主要有两组检查：

1. 防复发检查：检查文件行数、动态调用、零引用候选和正式测试清单。
2. 正式测试：导入 Godot 项目，运行 Agent 离线测试、正式故事测试和独立正式入口测试，最后确认测试没有修改源码目录。

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

按顺序检查：

1. 文件是否真实存在。
2. `git status --short` 中是否显示为 `??`。
3. `git ls-files` 能否找到该文件。
4. 路径大小写是否与实际文件一致。macOS 常见文件系统可能忽略大小写，Linux CI 会严格区分。
5. 文件移动后是否仍有旧路径引用。

不要只修后续的类型推断错误。缺少预加载文件时，类型推断和依赖脚本编译错误通常都是连带结果，应先修第一条缺文件错误。

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

### 正式测试断言读取了错误的数据层

表现：测试中的行为已经正确，但断言从公开投影读取只存在于 World 内部的状态字段，或用显示名称查找按稳定 ID 建立的内部状态表，得到 `null` 并使正式测试退出失败。

处理方式：先确认失败字段是否属于生产入口的公开返回契约；如果只是测试用的内部状态，应从测试 World 的内部居民记录读取，并使用测试已有的稳定 ID 常量，不要用显示名称猜测字典键；另外保留公开投影的行为断言。不要为了让断言通过而把内部调试字段泄露到生产接口。

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

## 提交前简表

- [ ] `git status --short` 中没有被遗漏的 `??` 文件。
- [ ] 新增脚本所需的 `.gd.uid` 已确认。
- [ ] 新测试、预览和工具脚本已分类。
- [ ] 所有新增资源路径已经检查大小写，并确认文件被 Git 跟踪。
- [ ] `tools/guards/run_guards.sh` 通过。
- [ ] Godot 无头导入没有脚本或引擎错误。
- [ ] 相关测试通过；发行改动完成正式测试套件。
- [ ] 测试后 `git status --porcelain` 没有意外变化。
- [ ] 玩家可见改动已经写入根目录 `更新日志.md`，并已同步 README 的最新更新摘要。
- [ ] 提交后在干净临时工作区复查一次，再推送。
