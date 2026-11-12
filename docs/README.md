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

开发时用 `corepack pnpm dev`。两种方式都启动 Rust 管理服务 `target/debug/town-manager`（`crates/manager`，安装包里也是它），由它按需启动各小镇的世界进程：dev 另起 Vite 热更新页面，`/api/towns` 由 Vite 代理到管理服务（默认端口 8788）；preview 由管理服务直接发构建好的页面，会检查构建摘要，前端源码变更后需重新构建。改了 Rust 代码要重新 `cargo build` 再重启。`AI_TOWN_HOME` 指定数据目录，`TOWN_MANAGER_PORT` 换管理服务端口，`TOWN_HOST_BINARY` 换世界进程（跑长局用 release 版），`TOWN_MOCK_LLM=1` 让世界用固定回复模型。`/api/towns/health` 的 `source` 字段可确认实际运行的工作区。

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
