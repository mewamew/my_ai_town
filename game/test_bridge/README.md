> 更新时间：2026-10-08 10:49 +08:00（Asia/Shanghai）

# Opt-in GameTestBridge and isolated regression tools

This contribution adds a loopback-only HTTP/WebSocket test bridge to the existing game. It is disabled by default and is independent of the cafe scheduling contribution in PR #166. It also adds an explicitly enrolled test cleanup-retention policy for isolated restore verification. No cafe scheduling, provider, prompt, game resource or historical-save fixture changes are included.

## Isolated cleanup retention and real restore verification

`AgentFileSystem.configure_test_retention()` is a one-way process-local opt-in, not an environment setting. A caller first creates a fresh `gametest-retention-*` sandbox with `owned/`, `retained/` and an empty `retention.jsonl`. Cleanup moves eligible descendants of `owned/` into unique numbered destinations; it inventories files and directories, journals the attempt and checks SHA-256 after moving. Existing destinations, traversal, foreign roots and symbolic links/junctions are rejected. Empty test parents remain. Native rename failures are returned, and incomplete post-move verification cannot silently become success on retry. The caller must own the isolated sandbox exclusively; this is not protection against a hostile concurrent filesystem writer.

The real Agent commit/cancel/close paths preserve their transaction/context on retention failure. TownSessionSaveStore retires owned leases by a single real move and releases ownership only after success. Its single-entry and candidate cleanup use the same policy. Resident and avatar memory cleanup are enrolled too, and their callers stop on retention failure. Default physical deletion remains the original behavior and is **not executed or claimed verified** by these tests.

`phase2_tests/test_evidence_import.py::test_real_cleanup_retention_and_restore` covers native Windows lock failures, path/junction rejection, destination collisions, real lease release/reacquisition, Agent preparation/cancellation, actual 15-resident paired restore, malformed/changed-hash World copies, future Agent format, and partial hydration/filesystem failure rollback. The restore uses real World, Agent, Store, coordinator and runtime gate. An offline scripted model supplies an unused provider contract; it does not fake store or restore outcomes. Fixture copies and private absolute-root bindings are explicit; official root-configuration validation, GUI/Bridge-host restore and original physical cleanup are separate requirements.

Each isolated child retains engine output, JSONL/SQLite, pre/post failure snapshots and the cleanup manifest. `retentionId` identifies a cleanup attempt; it is neither a test-evidence UUID nor a game event sequence. This transaction-level test has no HTTP request or Bridge event sequence and does not invent either. Original beta6 fixtures, foreign sentinels, initial copied files and enrolled source hashes are independently checked. Generated tests use fresh basetemp outside the evidence root; old reports remain.

Hydration obtains initialization from the real active World projection and calls the real Agent hydration API, allowing its saved-state equivalence checks to detect mismatches. The small test hydrator supplies this existing integration contract without running the production Gateway/UI. Child metadata records the outer case ID; JUnit properties link its run ID, JSONL, manifest and engine output. These links identify the transaction-level evidence even when no Bridge request/event exists.

The first full local retention run on 2026-10-07 passed all five stages: pytest 61/61 (CLI 323.66 seconds, JUnit 323.441), existing Godot Bridge 685 checks, Newman 14/14, Pylint 10/10, 411057.7662 ms for the five stages. Its 10 retention children passed 186 conditions, with JSONL/SQLite/source hashes and five equal before/after snapshots audited. These are separate counting units. Subsequent review strengthened the real World projection and explicit child/JUnit links; this final test source needs its own verification and hosted final-SHA CI. Development failures and earlier source-isolation rejection remain retained.

Final local source validation completed on 2026-10-07 and was audited on 2026-10-08: `retention-final-20261007-2208` passed five stages, pytest 61/61 (CLI 320.51 s; JUnit 320.256 s), Godot 685 checks, Newman 14/14 and Pylint 10/10; stage total 386802.5016 ms. Root `pytest-20261007T140927456286Z-f346f6a7` contains 576 JSONL/SQLite records and 9 source fingerprints. Ten retention children passed 186 conditions; their JSONL/SQLite, 10 enrolled source fingerprints each, outer case IDs and JUnit evidence links were audited. Five failed-restore snapshot pairs are byte-identical, and 714 retained-file hash entries were independently checked. The audit JSON and all original reports are isolated artifacts, not committed project files. Deliberately failing reporter children are separate expected-failure probes, not product defects.

These tests run serially with one isolated process per scenario. Background save/cleanup concurrency, production Gateway/UI/Bridge-host restore, official root configuration and the original physical deletion branch remain unverified. Local dirty-tree validation does not replace hosted final-commit CI; Phase 2 remains open.

Development failures are retained: the first driver left JSON integer fields as floats; a later driver loaded a prebuilt World JSON lacking the current authoritative build receipt. Both were corrected using existing `AgentJson.normalize_numbers` and `TownWorldDataBuilder`. Malformed JSON and valid JSON with changed content are separate fixtures with separate expected error codes. A concurrent source edit invalidated a development run's source-isolation check; final validation must run against frozen source. Complete Phase 2 acceptance and hosted final-SHA CI are still pending.

The existing speed mutation now increments the world revision, so optimistic concurrency and state-change events observe an actual speed change. A replay/no-op does not increment it.

## Running the bridge

Start the game with user arguments `--gametest-bridge` and optionally `--gametest-port=18765`. Without `--gametest-commands`, the bridge is read-only. Adding `--gametest-commands` explicitly enables speed, movement and save/load commands; do not use write commands against a personal save when exploring the protocol.

- `GET /health`, `GET /world/state`, `GET /residents/{id}` expose public, whitelisted state, not credentials or resident memory contents.
- `POST /commands/set-speed`, `move-player`, `save`, `load` require command and idempotency IDs, expected session/generation/version and a timeout. Movement uses the existing physical input path, not teleportation. Save/load delegate to the existing session lifecycle and are asynchronous.
- `GET /commands/{commandId}` returns a receipt; HTTP acceptance does not mean completion.
- `GET /events/cursor` returns current world metadata, a Bridge-instance `streamId` and `lastEmittedEventSequence`. This counts events generated/queued by the Bridge, not successful socket delivery or client receipt. World restart keeps the sequence within the same Bridge instance; a replacement instance has a new stream and resets it. An unready world returns 503.
- `/events` upgrades to a WebSocket semantic event stream. Queue overflow disconnects the client; there is no historical replay. Query state and receipts after reconnecting.

`protocol.schema.json` defines request/response/event contracts. The bridge bounds request size, connections, queued events and per-frame polling work. Loopback binding is not authentication: enable it only in a trusted local session.

## Deterministic regression

Use existing Python 3.11, Godot 4.7.2 and `requirements-phase2-core.txt`. Postman/Newman and Locust are optional independent interfaces; UI tests require a real Windows desktop and their separate UI dependencies. The GitHub Actions workflow runs core Bridge regressions and a separate Locust static job; it does not pretend a headless job validates the UI.

Run from the repository root (replace executable paths with your installed tools):

```powershell
# Use a NEW, nonexistent basetemp every time. pytest clears an existing basetemp.
python -B -m pytest -q -p no:cacheprovider -c game/test_bridge/pytest.ini game/test_bridge/phase2_tests --godot-bin D:/Godot/Godot_v4.7.2-stable_win64_console.exe --basetemp game/test_bridge/artifacts/unique-run-temp --junitxml game/test_bridge/artifacts/unique-run-junit.xml
godot --headless --path game --script res://tests/game_test_bridge_test.gd --log-file game/test_bridge/artifacts/unique-engine.log -- --gametest-isolated-test
```

The pytest fixture launches an isolated 15-resident World without booting normal UI/model services. Bridge save/load orchestration tests use a declared fake session host: they test receipts and lifecycle boundaries, **not real disk restoration**. The new read-only save test calls actual AgentSaveStore validation helpers using historical beta6 files and generated corrupt inputs, without invoking writes, restore transactions or recursive cleanup. It checks valid JSON/payload, truncated/non-object JSON, incorrect length/hash and unsupported version. This does **not** validate complete restoration, root configuration, rollback, world log/task/memory preservation or migration. Those remain separate validation work; do not run recursive-cleanup save suites under a no-deletion policy.

`run_phase2_ci.ps1` is a provider-neutral local/Actions entry point for preflight, core lint, pytest, Godot Bridge contracts and Newman report import. It uses a fresh per-run basetemp and retains failure artifacts. The upstream contribution deliberately excludes cafe-specific tests from this runner. Python dependencies are top-level pinned, not a full transitive lock.

## Failure evidence and ID boundaries

The same normalized record is appended to JSONL and SQLite. JUnit properties link a case to its requests, responses, transport failures, game events and failed assertions. A failed live assertion requests a bounded read-only public state snapshot; it is a **post-assertion read**, not an atomic failure-time snapshot.

| Identifier | Meaning |
|---|---|
| `testEvidenceId` / compatibility `eventId` | Generated evidence UUID, never a game event identifier |
| `sequence` | Evidence append order |
| `details.gameEventId`, `eventSequence` | Original game identity and sequence; absent values remain null |
| `details.receiveIndex`, `wirePayloadSha256` | Frame observation order and original payload hash |
| `requestId`, `commandId`, `worldGeneration`, `stateVersion` | Actual server metadata; client expected values remain in request details |

Events without command IDs only have a case observation-window association; temporal proximity is not a causal link. Duplicate frames are retained rather than deduplicated. Trace decode/disconnect/overflow errors and Schema violations fail the case. The collector handles the Bridge's current unmasked, unfragmented text frames, not every WebSocket extension/control format. Source hashes identify the exact dirty or clean code used by a run. Intentional failing child pytest cases verify reporter retention, not product defects.

## 事件窗口与异常边界补充（2026-10-05）

修改原因：仅靠命令回执无法判断没有 commandId 的首尾状态通知是否缺失；正常连接的回归也不能证明断线后的查询与显式重连仍然可用。

本次补充：

- 用实际 HTTP 前后水位检查同一流的 `(start,end]` 有界事件窗口；八组受控消费序列覆盖顺序、乱序、重复及首/中/尾/全部遗漏。回放引用实际采集事件的证据 ID，与 live 事件分开存储，不冒充真实网络丢包。
- 验证客户端主动断开、协议策略触发的服务端关闭，以及显式重新握手。断线窗口只提交一次命令，使用原 commandId 查询结果，不重发写请求；重连不提供历史事件补发。
- 通过真实 World stop/start 和 TCP/WebSocket 验证世代变化、旧世代命令拒绝且无副作用、新命令可用。额外检查同一 Bridge 重监听与新实例换流；不同流、序号倒退或窗口超过 4096 时完整性记为未知，不拼接成通过。
- 使用仓库已有 beta6 夹具的隔离副本调用实际 Store 只读入口，覆盖 17 个正常/异常场景及文件隔离检查。没有执行 hydration、恢复事务、回滚或递归清理，完整异常存档恢复仍未验收。
- 在创建证据库前拒绝已有 basetemp，以及证据目录位于 basetemp 内的配置，防止 pytest 清理证据。每次运行使用新路径，失败产物保留。

测试证据 UUID/追加顺序与游戏 eventId/eventSequence 始终分开；请求、事件、回放和水位响应通过显式来源字段关联。跨端 Access Log、实际引擎子进程资源计数及 Godot 驱动原始帧字节不可得的部分明确记为盲区，不宣称无泄漏或完整双端 tracing。生产 Planner/Recovery、正式存档恢复和性能容量不在这些结果范围内。

移植前工作树验证为 pytest 51/51、原 Godot 合同 685 checks、Pylint 10/10；定向三轮各 12/12。真实换代子实验的 18 个条件不是额外 18 个 pytest 用例。以上是本地旧工作树结果，不能替代本独立 PR 树或新提交的远端 CI；发布前需独立复验并保留原始报告。

### 原协议修复记录

独立 PR 树复验（2026-10-05）：`pr-cursor-20261005-2050` 的预检、静态检查、pytest、Godot 和 Newman 五阶段均通过。pytest `51 passed / 0 skipped`（CLI 144.41 秒；JUnit 144.247 秒），原 Godot `685 checks`，Newman `5 requests / 14 assertions / 0 failures`，Pylint `10/10`。根运行 `pytest-20261005T124935266968Z-240847ce` 的 566 条 JSONL/SQLite 记录及 9 份源码指纹逐项核对；真实换代子实验 18/18、38 条记录独立核对。系统证书读取错误及 Node 弃用警告原样保留，工具退出码均为 0。这是本地未提交文件树的结果，不是新 SHA 的远端通过证明；没有混入咖啡或游戏资源变更。

Two real-wire regressions are included: successful command events must include `failure: null`, and an idle connection must not resend its already-sent last frame. The sender resets both stored and local output when draining a frame. Event defaults preserve both required result/failure keys without weakening Schema assertions.

Development validation before this independent tree was assembled: genuine pre-fix failures were preserved; the repaired working tree passed 32 pytest cases and 685 existing Bridge checks. These numbers are not evidence for this separate tree or a future CI SHA. Independent validation results and outstanding work belong in the PR description. No claim of full save recovery, network disorder recovery, capacity/SLA performance, real-LLM evaluation or complete Phase 2 acceptance is made. Upstream review and merge remain the maintainer's decision.

Independent-tree validation on 2026-10-02: `pr-bridge-20261002-full3` completed all five core stages locally (preflight, static, pytest, Godot, Newman), 137.4 seconds excluding resource import. Pylint was 10/10, pytest was 33 passed with no skips, Godot was 685 checks and Newman was 5 requests / 14 assertions / 0 failures. JSONL, SQLite, JUnit, stage logs and summary were retained in the developer's isolated artifact directory; they are not committed or evidence of hosted CI. Source was based on upstream `43ef1d1` with the explicit uncommitted contribution; final-SHA CI still needs verification.

The first independent assembly omitted the existing speed-revision hook and failed two tests; the same assertions passed after including that required integration. Runner debugging also retained the initial PowerShell stderr/encoding and preflight failures. The runner now preserves native stderr as UTF-8 and checks the actual exit code, retains its 10 GiB free-space threshold using filesystem telemetry, writes Python syntax checks without bytecode files, and imports failure summaries instead of aborting before evidence collection. A real shell/child-process regression verifies stderr with exit 0 and failure with exit 3; these synthetic command probes validate the harness, not game behavior. Resource import exited 0 with sandbox certificate/editor-settings warnings, which are not suppressed.

## Upstream draft and first hosted result

[Draft PR #167](https://github.com/mewamew/my_ai_town/pull/167) contains this independently scoped Bridge contribution. The first hosted fork run [36965086430](https://github.com/haohao88888888/my_ai_town/actions/runs/36965086430), SHA `b212d751ab28cfa359a0e6c70cb0258c7196e37c`, **failed**: Locust static passed, core pytest had 32 passed / 1 failed. Godot and Newman stages were skipped after that failure, not passed. The real-event reporter test launched a nested pytest without forwarding the explicit Godot executable path; its two child cases failed during setup before the intended assertion. The local fallback path had hidden this harness defect. The test now resolves the existing executable fixture and explicitly forwards `--godot-bin` to the child; no game code, Schema or assertions were changed for this correction. New local and hosted validation must be checked separately, without inheriting prior-SHA results.

The failed artifact was preserved locally and its SHA-256 matched the Actions upload digest `f665d238a3299eb03c55a4e87fa269647a8764f366449cf8f12c9096d2298689`. Upstream workflows require maintainer approval (`action_required`); this is neither a test pass nor a test failure. The contributor will edit the PR description manually in Chinese. Complete restore/cleanup and disorder validation remain open regardless of PR status.

After forwarding the executable path, local run `pr-bridge-20261003-full1` again passed all five stages: Pylint 10/10, pytest 33 passed / 0 skipped (77.02 seconds), Godot 685 checks and Newman 5 requests / 14 assertions / 0 failures. Original assertions and the deliberately failing child case were retained. This local result is not hosted validation; the final updated commit still requires independent remote runs.
