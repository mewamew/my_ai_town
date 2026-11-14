# 开发入口

后续开发统一在 [mewamew/my_ai_town](https://github.com/mewamew/my_ai_town) 的 `main` 进行。克隆后按下列步骤启动；玩家介绍和旧版说明见[项目首页](../README.md)。

## 安装与启动

Node.js 用 `.nvmrc` 的版本（最低 22.18），Rust 用 `rust-toolchain.toml` 固定的 1.88.0。

```sh
corepack pnpm install --frozen-lockfile
cargo +1.88.0 build --locked -p host -p manager --bins
corepack pnpm build
corepack pnpm preview   # http://127.0.0.1:5174
```

开发时用 `corepack pnpm dev`。两种方式都启动 Rust 管理服务 `target/debug/town-manager`（`crates/manager`，安装包里也是它），由它按需启动各小镇的世界进程：dev 另起 Vite 热更新页面，`/api/towns` 由 Vite 代理到管理服务（默认端口 8788）；preview 由管理服务直接发构建好的页面，会检查构建摘要，前端源码变更后需重新构建。改了 Rust 代码要重新 `cargo build` 再重启。`AI_TOWN_HOME` 指定数据目录，`TOWN_MANAGER_PORT` 换管理服务端口，`TOWN_HOST_BINARY` 换世界进程（跑长局用 release 版），`TOWN_MANAGER_BINARY` 换管理服务（在没编 Rust 的工作区里用别处编好的），`TOWN_MOCK_LLM=1` 让世界用固定回复模型。`/api/towns/health` 的 `source` 字段可确认实际运行的工作区。

建镇时生成器（`scripts/mapgen`）在页面的工作线程里运行，管理服务只理解描述、校验成品地图并保存；生成器因此不能依赖 Node 专有接口。

## 内置模型

用村民真实请求微调的小模型，玩家在请村民和「使用模型」里直接选「内置模型」，不填地址和密钥。它只给村民过日子用，一句话建镇和写人设仍走在线模型。模型训练在仓库外进行；这里只放接入代码：llama.cpp 的 `llama-server` 由世界进程按需启动，题面按训练时的模板逐字渲染（`crates/agent/src/builtin.rs`）。

推理程序随安装包带，模型文件不带：发布在魔搭（发布处见 `crates/host/src/application.rs` 的 `BUILTIN_SOURCE`），游戏第一次用时下载到用户数据目录的 `builtin-model/`，之后按 `manifest.json` 自动更新——下载、续传、核对和换上都在 `crates/host/src/builtin_store.rs`，管理服务直接调它。游戏只取格式号（`builtin.rs` 的 `FORMAT`）和自己一样的版本；题面模板、工具定义的写法或推理程序改得旧模型用不了时，把格式号加一。

```sh
node scripts/builtin-model/build.mjs [--llama <llama.cpp 源码目录>]            # 电脑：target/builtin-model/llama-server
node scripts/builtin-model/build.mjs [--llama <llama.cpp 源码目录>] --android  # 手机：target/builtin-model-android/llama-server
node scripts/builtin-model/build.mjs [--llama <llama.cpp 源码目录>] --windows  # Windows：target/builtin-model-windows/llama-server.exe
node scripts/builtin-model/build.mjs --gguf <模型.gguf>                        # 另外把没发布的模型装进本机，当作今天的测试版
```

`build.mjs` 把固定版本的 llama.cpp 编成单个 `llama-server`（电脑用 Metal，手机用 CPU，Windows 用 CPU 且要求 AVX2）。重启 `pnpm dev` 或 `preview` 后设定里就有「内置模型」；安卓、mac、Windows 打包时看到它就带上。新版本在训练环境里发布，这里不放发布工具。想换成自己的模型：照 `builtin_store.rs` 开头写的清单格式放一份 `manifest.json` 和模型文件，设 `AI_TOWN_MODEL_SOURCE=<它的地址>` 再启动管理服务。服务日志在各小镇的 `logs/builtin-model.log`。

## 安卓版

手机和电脑用同一套前端，手机布局按屏宽和触屏切换。应用壳（`android/`）在手机上启动 Rust 管理服务（`crates/manager`）和世界进程，再用 WebView 打开页面。需要 Android SDK 与 NDK、JDK 17（Android Studio 自带）和 `rustup +1.88.0 target add aarch64-linux-android`。

```sh
node scripts/android/build.mjs          # 发布包：target/android/ai-town-<版本>.apk
node scripts/android/build.mjs --debug  # 调试包；页面可在 chrome://inspect 里调试
```

第一次打包会生成发布签名 `android/release.jks` 与 `android/keystore.properties`（不入库）。签名换了，新包就不能覆盖安装旧包。

## mac 版

应用壳（`macos/`）和安卓一样启动 Rust 管理服务与世界进程，在窗口里打开同一套页面。数据目录与电脑版共用（`~/Library/Application Support/MyAiTown`，可用 `AI_TOWN_HOME` 改），两边不能同时打开；服务日志在 `~/Library/Logs/AI小镇/`。只支持 Apple 芯片，需要 Xcode 和钥匙串里的 Developer ID Application 证书。

```sh
node scripts/macos/build.mjs                             # 签名的 DMG：target/macos/ai-town-<版本>.dmg
AI_TOWN_APPLE_ID=<Apple ID> AI_TOWN_APPLE_PASSWORD=<App 专用密码> node scripts/macos/build.mjs   # 签名并公证
node scripts/macos/build.mjs --no-sign                   # 不签名，只在本机试
```

设了 `AI_TOWN_APPLE_ID` 与 `AI_TOWN_APPLE_PASSWORD` 时，脚本每次打包前先把凭据存进钥匙串档案 `ai-town-notary`（Team ID 取自签名证书），再提交公证；档案名可用 `--notary-profile` 或 `AI_TOWN_NOTARY_PROFILE` 改。App 专用密码在 appleid.apple.com 的「登录与安全」里生成。

## Windows 版

### Windows 本地启动器

已有源码运行环境时，可以在 Windows 上生成根目录的 `AI小镇启动.exe`：

```powershell
node scripts/windows/build-local-launcher.mjs
```

构建使用 Windows 自带 .NET Framework 的 C# 编译器；运行需要 Node.js 22.18+、`target/debug/host.exe`、`target/debug/town-manager.exe` 和已安装的前端依赖。双击后隐藏启动 Ollama 与 5174 端口的小镇服务，等待就绪后打开默认浏览器；前端构建过期时自动重新构建。端口被其他项目或不同存档的服务占用时会报错，不会强制终止进程。此入口使用浏览器，不依赖 WebView2。

本机设置位于被忽略的 `.local/windows-launcher.json`，字段为 `ollamaExe`、`modelDir`、`model`、`dataDir`，路径可相对项目根目录。默认从 `%LOCALAPPDATA%\Programs\Ollama` 或 `PATH` 查找已安装的 Ollama，沿用它的模型目录（包括 `OLLAMA_MODELS` 环境变量）；便携安装可用前两个字段指定路径。默认模型名 `qwen3.5:2b`，存档 `.local/run-data`；不会下载模型或修改居民的模型绑定。可用环境变量 `AI_TOWN_NODE` 指定 `node.exe`。

启动日志和状态位于 `.local/launcher/`。开发验收可运行 `AI小镇启动.exe --headless --no-browser`，检查退出码、`status.json` 和服务健康接口。启动器退出后后台服务继续运行；结束游玩时先返回「选择小镇」保存并关闭世界。EXE 是本机源码入口，不能脱离项目目录使用，源码更新后可用上面的命令重新生成。

### 完整 Windows 应用包

**Windows 尚未实机测试。以下是构建方式和设计目标，不代表已验证兼容性。启动、WebView2、内置模型、存档和中文路径都仍需 Windows 实机验证。**

可以在 Mac 上交叉编译。应用壳（`windows/`，Rust + WebView2）和 mac 版一样启动管理服务与世界进程，在窗口里打开同一套页面。产物是 zip，解压后双击「AI小镇.exe」，不用安装；目标平台是 64 位 Windows 10、11，画面靠系统的 WebView2 运行时（没有时提示去下载）。数据目录 `%LOCALAPPDATA%\MyAiTown`（可用 `AI_TOWN_HOME` 改），服务日志在它下面的 `logs\`。需要 `rustup target add x86_64-pc-windows-gnu --toolchain 1.88.0` 和 `brew install mingw-w64`。

```sh
node scripts/windows/build.mjs   # target/windows/ai-town-<版本>-windows-x64.zip
```

Windows 产物暂未签名，系统可能显示 SmartScreen 提示。发布前应在干净的 Windows 环境验证，并公布产物校验值。

## 录像与拍素材

「世界观」面板「规则」下面的录像开关（缺省开）开着时，世界进程把发给页面的名册和事件录进小镇目录的 `recordings/`，每打开一次世界一卷，什么也没发生的卷不留。重演时不开世界、不调模型，同一段拍几遍都一样：

```sh
node scripts/replay/script.mjs <小镇> --reels                   # 录下的几卷
node scripts/replay/script.mjs <小镇> --who 林晚 --grep 帮忙     # 读成剧本，找片段
node scripts/replay/shoot.mjs 镜头单.json --draft               # 小样：1280×720、30 帧
node scripts/replay/shoot.mjs 镜头单.json                       # 成片：缺省 3840×2160、60 帧
```

`shoot.mjs` 要一个正在跑的前端（缺省 5174，`--base` 换）、ffmpeg 和 Chrome（无头、走真 GPU）；镜头单怎么写见它的开头。每段出一个 mp4（时间码按录像时刻，几个机位在剪辑软件里按时间码对齐）、台词和心声两份 SRT、一张样片图。录像的行写法改了，`crates/host/src/recording.rs` 和 `scripts/replay/reel.mjs` 的格式号一起加一。

## 检查

按依赖顺序运行；CI 配置见 `.github/workflows/`。

```sh
cargo +1.88.0 fmt --all -- --check
cargo +1.88.0 clippy --locked --workspace --all-targets -- -D warnings
cargo +1.88.0 test --locked --workspace
cargo +1.88.0 build --locked -p host -p manager --bins
corepack pnpm build
corepack pnpm typecheck
corepack pnpm test
corepack pnpm format:check
```

## 数据与发布

- 玩家数据放在用户目录，`AI_TOWN_HOME` 可指定独立目录。测试和截图请使用独立目录，避免读写正式存档。API 密钥只存本机，不进入 Git；使用在线模型时，居民请求和相关世界上下文会发送给你配置的服务商。
- 新版不读取或迁移旧 Godot 存档；旧文件应自行保留。HD-2D 的历史地图兼容定义不能因名称清理而删除。
- `LICENSE` 与 `NOTICE` 说明本项目授权范围；`licenses/` 记录第三方软件、模型和素材。升级依赖后运行 `node scripts/third-party-notices.mjs` 更新依赖许可；替换 llama.cpp 时同步该版本及其内置依赖的许可。
- `stageAppBundle` 将许可文件一并放进安装包的 `app/licenses/`。签名、公证和真机运行需按发布平台分别完成，交叉编译成功不代表真机验证通过。
- CI 检查 Rust 内核和浏览器客户端；Windows 独立工作区不在 CI 中。现有 `protect-crates` 规则拒绝修改 `crates/` 的外部 PR，核心改动由维护者处理。

## 设计原则

- 模型提议，世界确认。Agent 输出只有经过内核校验并执行才成为世界事实。
- 村民动作来自模型；模型不可用时暂停村民决策，不用脚本代替。模型请求期间世界按正常速度推进，过时的回复退回；大家都在做一件还要好一阵的事、没人走动、交谈或等模型回复时世界自动快进，快到有人做完时慢回正常速度。正常速度按地图比例定，村民在画面上像散步。
- 协议传世界语义，渲染几何由前端处理；前端不推断内核规则。
- 人口属于存档状态。新世界是空村，居民从村民库经入口加入。村民库所有小镇共用：自定义模板存在用户目录的 `resident-library/`，旧版存在各小镇目录里的模板开镇时复制过来，原文件不删。
- 判断功能是否接通，要检查入口、调用、内核与协议路径及测试；需要时验证实际运行。

## 霜灯镇：五小时开发计划与验收

本计划于 2026-11-14 12:59（北京时间）建立，先写计划再实现。开发窗口截至 17:59。工作区为 `upstream-latest`，基线为原仓库 `main` 的 `b6e513d5`。本节按本次用户要求记录开发步骤、测试和失败处理；实现细节留在源码注释，运行证据留在忽略的 `.local/frostlight-check/`，验证结论进入提交信息。

### 目标与玩法

新增独立预制小镇「霜灯镇」，玩法编号 `frostlight`。参考 Frostpunk 的供热、生存资源、法令代价与社会情绪，将这些机制缩小到六位能行走、交谈、协商的居民。参考依据为 [11 bit studios 的 Frostpunk 介绍](https://11bitstudios.com/games/frostpunk/)与[官方玩法介绍](https://store.steampowered.com/news/posts/?appids=323190&enddate=1524044423&feed=steam_community_announcements)。采用原创名称、场景与界面，复用本项目已有美术和渲染能力。

完整一局围绕「为暴风雪备粮、维持热源、在黎明点亮霜灯」展开。居民有各自的愿望，模型决定是否劳动、如何分工、是否支持公共决策。玩家可查看所有资源的变化原因，作出供热和法令选择，也可以通过既有交流入口影响居民。胜负由世界规则结算。

首版必须包括：

1. 六名有差异的居民，一张独立的环形雪地小镇：中央热源，内圈住所/厨房，中圈工坊/诊所，外圈采集站；环路与放射状道路相连。参考 Frostpunk 的环形组织，单独设计地图，不改写现有小镇。热源、燃料点、厨房/食物点、避难点均有清晰且可达的劳动位置。
2. 准备、降温、暴风雪、黎明四个阶段；倒计时使用世界时间，暂停和存读档不跳过结算。
3. 有限燃料与食物、供热强度、热源压力/过载代价、希望与不满。所有数值有边界和可解释的变化原因。
4. 少量有明确收益与代价的法令（如加班、节粮、互助），有限的紧急救援选择；不给无限点按刷取资源的入口。
5. 居民真正行走到工作地点才可劳动，劳动占用时间，完成后结算产出或交付。位置不符、重复提交、物资不足、已经结局等情况明确拒绝，失败不扣物资。
6. 可达成的成功结局、资源枯竭/失去支持等失败结局，以及一份解释资源、政策和居民贡献的结局面板。
7. 地图上的暖光与寒冷变化、热源反馈、居民工作标记、资源和政策界面。维持现有 HD-2D 摄像机、右键旋转及边缘雾化。

将规模限制在一个可完整游玩的独立场景。独立地图由新的 `scripts/maps/frostlight.mjs` 生成到 `data/maps/frostlight/map.json`，执行 seal 和地图校验；布局以环形供热与短距离步行为中心。复杂科技树、大规模城市建造与新寻路系统属于后续扩展；美术先服务于热源、工作地点和行动可见性。

### 实现边界与接口

- 规则放在 `crates/kernel/src/game_mode/frostlight.rs` 并实现现有 `Rules`。时间、资源、政策、工作和结局状态由同一份规则持有，随世界快照保存。
- 协议放在 `crates/protocol/src/game_mode/frostlight.rs`，补齐 `GameModeChoice`、`GameModeView`、`GameModeContext`、公开导出与 TypeScript 对应类型。先固定协议，再并行实现，避免各端自行发明字段。
- 居民使用现有 `mode_action` 和移动工具。给模型的题面包含实际地点编号、合法动作、所需资源、当前工作和截止时间；小模型不需要猜测参数。居民响应失败或不可用时如实显示，不用脚本冒充模型决策。
- 玩家管理操作通过明确的世界命令接入并由内核校验；若现有接口不足，增加通用的玩法管理接入点，再由玩法决定权限与合法操作，不把霜灯镇判断散落在本体。
- 画面在 `frontend/town-2d/src/map/hd2d/gameModes/`，预制入口在 `frontend/town-shared/src/prefabs/`，音乐在 `frontend/town-shared/src/audio/gameModes/`。UI 只显示服务端状态，不自行发放资源或推断胜负。
- 新场景创建独立小镇。正式 `.local/run-data`、模型权重、密钥和旧定制版本保持原样；所有自动化、模型试跑和截图使用独立数据目录与端口。

### 阶段、交付与时间上限

| 时间（北京时间） | 工作 | 阶段完成标准 | 失败处理 |
| --- | --- | --- | --- |
| 12:59–13:25 | 文档、源码核对、协议设计、建立分支 | 计划已落盘；状态、动作、时间和结局约定明确 | 缺失接口先最小补齐；缩小功能数量，保留完整闭环 |
| 13:25–14:35 | 并行完成内核、居民/预制场景、界面/视觉 | 最小场景能开启；资源、工作、政策与阶段可联通 | 按文件归属整合，出现协议冲突先修契约，不各端绕过 |
| 14:35–15:25 | 整合与关键回归 | 从入口开局，走动、到点劳动、资源变化、阶段推进正常 | 固定种子复现，定位到首次状态偏离；修复后重跑对应完整路径 |
| 15:25–16:15 | 本地 Qwen 真实试跑与平衡 | 有模型调用、真实位移与工作产出的证据；成功路线与失败路线可解释 | 参数错误给合法选项；模型超时检查服务与预算；路点错误修地图/目标，不传送居民 |
| 16:15–17:00 | 视觉、交互、存读档与故障恢复验收 | 参考视角与俯视可读；重启保持进度；失败回执能理解 | 删减装饰和次要政策，优先解决数据一致性及阻断游玩的错误 |
| 17:00–17:59 | 最终构建、审查、证据与交付 | 构建通过、关键回归通过、旧存档哈希一致、启动入口可用 | 剩余缺陷明确报告；不把模拟验证写成真实模型验收，不宣称未完成项目已完成 |

主代理负责契约、整合、运行验证与数据安全；三个并行任务分别负责规则内核、居民/场景接入、前端视觉。阶段可以提前完成；发现风险时在五小时窗口内调整比例。账户余额无法从项目读取，不承诺固定 token 消耗量；额度用于实现、必要的审查和验证，不进行无意义生成或重复测试。

### 测试标准

遵循仓库「关键行为与数据安全」原则，同一规则只在最有代表性的完整路径中覆盖，不为界面排列或大量相近参数写重复测试。

| 关键路径 | 测试做法 | 通过标准 |
| --- | --- | --- |
| 开局与协议 | 预制选择→创建独立小镇→设置玩法→名册广播；协议样本交给前端类型检查 | 入口可见，开局可用，所有端解释同一状态 |
| 行走与劳动 | 模拟合法模型工具调用，申请带路径的工作，再真实移动到目标、定时劳动、返回交付 | 申请可排入真实动作组；抵达前不产出，不能隔空交付；完整动作组成功且位置正确才结算一次 |
| 资源、政策与胜负 | 固定种子跑通一条成功路线和一条放任失败路线；检查关键政策取舍 | 资源不为负、无无限奖励；截止/结局只触发一次；原因可见 |
| 错误与重复动作 | 非法目标、过期阶段、忙碌时重复提交、资源不足 | 明确错误，世界资源与已完成工作不被破坏，可重新提交合法动作 |
| 保存恢复 | 劳动中途和风暴阶段保存，重新加载继续至结束 | 工作、库存、期限与结局一致，无重复领物资，无时钟回退漏洞 |
| 旧版本兼容 | 运行已有关键存档回归；真实用户数据在前后分别计算文件名/长度/SHA-256 摘要 | 未开玩法时行为保持，正式存档逐文件摘要一致 |
| 本地模型 | 独立数据目录连接已有 `qwen3.5:2b`，记录请求、工具回执、坐标变化和资源变化 | 至少两名居民有可归因于模型调用的真实行动；如失败，保留诊断并准确报告 |
| 视觉与操作 | 浏览器检查开局、供热、法令、倒计时、结束面板；切换俯视并旋转 | 没有阻挡主要操作的面板，热源/工作位置清晰，无明显运行错误 |

基础检查采用本文件上方的 `cargo fmt`、`clippy`、Rust 测试、前端类型检查与构建命令。先执行受影响的关键回归，最终执行项目要求的完整检查；仅在代码再次变化、失败或仍有未解决风险时重复。Windows 用现有本地 Rust/LLVM 工具链；Corepack 不可用时可直接调用已安装的 TypeScript、Vite、Prettier 与 Node 测试入口，保留同等检查内容。

### 故障处理参考

1. **模型动作被拒绝**：保存脱敏后的动作与错误回执，核对模型实际拿到的合法动作/地点/资源；修正题面或边界校验；通过完整工具调用路径回归。不得把所有错误动作自动判成功。
2. **居民不移动**：依次检查模型是否响应、移动工具是否提交、目标是否可达、正在进行的动作是否阻塞、客户端是否收到坐标。每次只修有证据的一层；自动化回放与真实 Qwen 试跑分开标记。
3. **资源重复领取或存档不一致**：暂停该验收实例，保留原文件与日志；修复原子结算或已结算标记；用中途保存/重复提交回归，再继续试玩。
4. **场景/界面无法加载**：先跑类型检查与生产构建，查看首个运行异常；修复协议或初始化顺序；装饰效果可以降级，资源结算与可见移动必须保留。
5. **本地服务或端口冲突**：辨认进程来源，改用测试专用端口；只停止本次启动且可确认归属的进程。后台辅助程序隐藏启动，避免反复弹出 CMD 窗口。
6. **依赖或网络失败**：优先使用现有缓存；仅下载缺失的必要依赖。外部模型不可用时继续确定性规则测试，真实模型验收如实列为待完成，不伪造成功。
7. **时间不足**：优先级为数据安全→完整开局/行动/结局→本地模型→核心交互→视觉润色→额外事件。保留可运行版本和未完成清单，清楚区分已验证、仅构建通过和待验证。

交付包含本地源码、已更新的启动所需构建产物、玩家玩法说明以及简短的验证结论。测试数据留在明确的隔离目录，最终关闭无人使用的测试服务；用户正在试玩的实例保留，并说明端口与数据位置。正式存档不参与试玩。
