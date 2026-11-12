玩家说明见根目录 `README.md`，启动和检查见 `docs/README.md`。以源码、测试和数据为准；除这两份说明、`AGENTS.md` 和必要的许可文件外，不新增说明文档。实现说明写在必要的源码注释里，验证结果写在提交信息或 PR 描述中。

测试只保留关键行为与数据安全的回归，优先走完整调用路径；同一规则不在多层重复覆盖，不保留细小实现、界面排列和批量参数变体测试。

## 项目边界

- `crates/` 是 Rust 世界内核、Agent、协议与服务；`frontend/` 是客户端；`scripts/` 是本机管理服务和 HD-2D 建镇生成器。
- 安卓版：`android/` 是应用壳，`crates/manager` 是手机上的管理服务（桌面仍用 `scripts/` 的 Node 版，两边的 `/api/towns` 接口保持一致；手机建镇由页面跑生成器，成品经 `/drafts` 交给管理服务校验），`scripts/android/build.mjs` 打包 APK。手机和电脑共用前端，手机差异只按 `data-layout` / `data-input` / `data-shell` 分支。
- mac 版：`macos/` 是 Swift 应用壳，同样启动 `crates/manager`，数据目录与电脑版共用；`scripts/macos/build.mjs` 打包签名的 DMG。
- Windows 版：`windows/` 是 Rust 应用壳（WebView2，单独的 Cargo 工作区，不进 CI），同样启动 `crates/manager`；`scripts/windows/build.mjs` 在 Mac 上用 mingw 交叉编译、打成 zip。
- 客户端只提供 HD-2D，立体渲染位于 `frontend/town-2d/src/map/hd2d/`，不恢复独立 3D 客户端和研究工具。
- 玩法（有自己的目标、时间表和输赢的一套规则，如大逃杀的潮水圈）不往本体里加开关：内核在 `crates/kernel/src/game_mode/` 实现 `Rules` 并登记，线上类型在 `crates/protocol/src/game_mode/`，画面在 `frontend/town-2d/src/map/hd2d/gameModes/`，音乐在 `frontend/town-shared/src/audio/gameModes/`。加一个玩法：在这四个目录各写它自己的文件，再补登记（内核的 `GameMode`、协议的三个枚举、服务打开玩法时的回执、前端 `protocol.ts` 的类型、`gameModeLooks` 和 `GAME_MODE_MUSIC`），漏了哪处编译器和协议样本测试会提示；接入点不够就改接入点，不在本体里为某个玩法写专门的判断。一个世界同时最多开一个玩法，没开时存档、协议和给模型的题面与没有玩法时一字不差。所有玩法都用得到的能力（天气、生理、陌生环境等）留在本体。选了就玩某个玩法的预制小镇登记在 `frontend/town-shared/src/prefabs/`。
- 存档：`towns/<小镇 ID>/world.json` 只放当前状态，也是提交点；只增不改的历史（事件、过完的日子、做完的动作组、结束了的互动、村民的记忆记录）追加在 `history/` 的流水里，村民的笔记和归档在 `residents/`。三处怎么读写只写在 `crates/host/src/persistence.rs` 和它的子模块；内核只管把历史从快照里拆出来、读档时装回去（`crates/kernel/src/history.rs`）。给人物或会话加会越攒越多的东西时，在那里和 `Session::without_files` 决定它进不进流水，别让 world.json 重新长大。改存档格式要升 `persistence/migration.rs` 的版本号并留原档备份；`crates/host/tests/fixtures/save-v5/` 是旧版本写的真存档，用来回归旧档迁移。
- 录像：世界进程把发给页面的广播录进 `towns/<小镇 ID>/recordings/`（`crates/host/src/recording.rs`，属于用户数据）；`scripts/replay/` 读录像，在 `game.html?replay`（`frontend/town-2d/src/replay/`）里重演画面拍素材，不开世界、不调模型。录像怎么读只写在 `scripts/replay/reel.mjs` 一处。
- `data/maps/2d-town/map.json` 是发布的默认地图（「我的小镇」），`data/maps/spring-valley/map.json`、`data/maps/broken-towers/map.json` 是另外两张随应用发的内置地图（冰雪的「温泉谷」、末日废土的「断楼城」）；内置小镇名单在 `scripts/towns/storage.mjs` 和 `crates/manager/src/storage.rs` 的 `BUILTIN_TOWNS`，两边一致。`data/mapgen/` 是公共生成模板；`data/props/` 是公共道具定义。玩家地图、道具、居民存档、记忆和日志属于用户目录 `towns/<小镇 ID>/`，不迁入仓库的数据目录。
- `config/` 是应用配置和村民库；密钥位于被忽略的 `config/credentials.json`。
- 不从废弃项目重新生成地图。内置地图由 `scripts/maps/` 下各自的设计脚本生成（`default-town.mjs`、`spring-valley.mjs`、`broken-towers.mjs`，重跑即重写地图并用 `scripts/mapgen/document.mjs` 的 `seal` 封摘要）；改了检查逻辑与坐标，再运行 `target/debug/town-map validate < <地图文件>`。
- `data/scene-assets/` 的清单用于 HD-2D 空间校验和旧地图指纹，历史模型名不代表发布 GLB。不要因清理名称改变清单；修改参数或版本前先解决已有地图与存档的兼容。
- 旧 3D 存档不自动转换或删除；删除用户数据须有明确指令。
