//! 测试公用夹具：最小道具库与规则、两处所拓扑、建世界与把动作跑完的辅助。
//! 除 soak.rs 外，内核测试都不读仓库里的真实内容数据，改游戏数据不会让这些测试失败。
use kernel::{props::Catalog, weather::WeatherRules, KernelError, Topology, World};
use protocol::{ActionGroup, ActionResult, GroupStatus, NeedRules};
use serde_json::{json, Value};

/// 测试用道具库（fixtures/props.json）：编号都在 test: 命名空间下。
pub fn catalog() -> Catalog {
    Catalog::from_json(include_str!("../fixtures/props.json")).unwrap()
}

/// 需求参数的合法范围（fixtures/needs_rules.json）。
pub fn need_rules() -> NeedRules {
    NeedRules::parse(include_str!("../fixtures/needs_rules.json")).unwrap()
}

/// 天气规则（fixtures/weather_rules.json）。
pub fn weather_rules() -> WeatherRules {
    serde_json::from_str(include_str!("../fixtures/weather_rules.json")).unwrap()
}

/// 两处所拓扑的 JSON：甲地 —2 分钟— 乙地。`edit` 可以换道具、改地点属性、加三餐或处所。
pub fn two_places_json(edit: impl FnOnce(&mut Value)) -> String {
    let mut data: Value =
        serde_json::from_str(include_str!("../fixtures/two_places.json")).unwrap();
    edit(&mut data);
    data.to_string()
}

/// 两处所拓扑，道具表换成给定内容。
pub fn two_places(props: Value) -> Topology {
    topology(&two_places_json(|data| data["props"] = props))
}

pub fn topology(json: &str) -> Topology {
    Topology::from_json(json, &catalog()).unwrap()
}

/// 两处所加一个孤岛（有落脚点、没有任何通道）；甲乙两地各有一张耗精力的工作台。
pub fn tiny_topology() -> Topology {
    topology(&two_places_json(|data| {
        data["locales"]
            .as_array_mut()
            .unwrap()
            .push(json!({"id": "loc_c", "name": "孤岛", "kind": "dwell"}));
        data["stations"].as_array_mut().unwrap().push(
            json!({"id": "st_c", "locale": "loc_c", "name": "孤岛·到达点", "kind": "arrival"}),
        );
        data["places"].as_array_mut().unwrap().push(json!(
            {"name": "孤岛", "locale": "loc_c", "arrival_station": "st_c", "type": "t", "summary": ""}
        ));
    }))
}

/// 建世界并安置启用 Agent 的村民：(编号, 名字, 处所)。
pub fn world_with(topo: Topology, start: f64, residents: &[(&str, &str, &str)]) -> World {
    let mut w = World::new(topo, start, need_rules());
    for (id, name, locale) in residents {
        w.spawn(id, name, locale).unwrap();
        w.enable_agent(id).unwrap();
    }
    w
}

/// 单条动作草案入队，用当前修订号。
pub fn run(w: &mut World, actor: &str, id: &str, draft: Value) -> Result<ActionGroup, KernelError> {
    let revision = w.actor(actor).unwrap().actions.revision;
    w.run_actions(
        actor,
        id,
        revision,
        &[serde_json::from_value(draft).unwrap()],
    )
}

/// 推进到动作组结束，返回第一条回执。
pub fn finish(w: &mut World, actor: &str, id: &str) -> ActionResult {
    for _ in 0..4000 {
        if w.action_group(actor, id).unwrap().status != GroupStatus::Running {
            return w.action_group(actor, id).unwrap().results[0].clone();
        }
        w.step(0.1);
    }
    panic!("动作未结束：{:?}", w.action_group(actor, id));
}

/// 存档再读进一个同样拓扑的新世界。和 host 存盘走同一条路：历史拆成流水，读回来再装上；
/// 装回去的快照得和完整快照一字不差。
pub fn restore(w: &World, mut fresh: World) -> World {
    let detached = w.detach(&Default::default()).unwrap();
    let save = serde_json::to_string(&detached.snapshot).unwrap();
    let mut snapshot: kernel::WorldSnapshot = serde_json::from_str(&save).unwrap();
    snapshot.attach(detached.records).unwrap();
    assert_eq!(json!(snapshot), json!(w.snapshot()));
    fresh.restore_snapshot(snapshot).unwrap();
    fresh
}
