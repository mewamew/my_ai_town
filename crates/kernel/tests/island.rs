//! 荒岛玩法用到的道具规则：物品前提与产出、原地搭建、布置检查、每日补回、概率收获（带工具更容易）、
//! 定时来船与离开，以及天气影响身体和遮蔽处。都走 run_actions 与 step 的完整路径。
use crate::common;
use kernel::{weather::WeatherRequest, World};
use protocol::{BodyConditionKind, Exposure, GroupStatus, WeatherKind, WeatherMode};
use serde_json::{json, Value};

const WOOD: &str =
    r#"{"id":"test:wood","version":1,"name":"木头","portable":true,"stack_limit":5,"actions":[]}"#;

fn world() -> World {
    let mut w = common::world_with(
        common::two_places(json!([])),
        420.0,
        &[("r", "漂流者", "loc_a")],
    );
    w.tune_needs(
        "r",
        protocol::NeedsTuning {
            fullness_decay: 0.0,
            energy_decay: 0.0,
            ..kernel::default_tuning()
        },
    )
    .unwrap();
    w
}

fn put(w: &mut World, id: &str, definition: Value) {
    let def: kernel::props::Definition = serde_json::from_value(definition).unwrap();
    w.place_prop(
        serde_json::from_value(json!({
            "instance":{"id":id,"definition":def.reference(),"locale":"loc_a"},
            "definition":def
        }))
        .unwrap(),
    )
    .unwrap();
}

/// 跑一个道具动作到结束；返回 (是否成功, 回执变化或失败原因)。
fn act(w: &mut World, key: &str, prop: &str, verb: &str) -> (bool, String) {
    match common::run(w, "r", key, json!({"prop_id":prop,"intent":{"verb":verb}})) {
        Err(e) => (false, e.to_string()),
        Ok(_) => {
            let r = common::finish(w, "r", key);
            let ok = w.action_group("r", key).unwrap().status == GroupStatus::Succeeded;
            let text = if ok {
                r.changes.join("；")
            } else {
                r.reason.unwrap_or_default()
            };
            (ok, text)
        }
    }
}

fn carried(w: &World, name: &str) -> usize {
    w.topo
        .props()
        .iter()
        .filter(|p| !p.withdrawn && p.name == name && w.inventory().carried_by(&p.id, "r"))
        .count()
}

fn on_map(w: &World, name: &str) -> Option<String> {
    w.topo
        .props()
        .iter()
        .find(|p| !p.withdrawn && p.name == name && w.inventory().on_map(w.props(), &p.id))
        .map(|p| p.id.clone())
}

/// 营地：搭棚子要两根木头，完成时用掉、在原地建起棚子。
fn camp() -> Value {
    json!({"id":"test:camp","version":1,"name":"营地","actions":[{
        "id":"build","label":"搭棚子","duration_minutes":30,"completion":"activity",
        "requires":[{"item":"test:wood","name":"木头","count":2,"consume":true}],
        "on_complete":[{"kind":"place_prop","prop":{"id":"test:shelter","version":1,"name":"棚子",
            "shelter":true,"actions":[{"id":"rest","label":"避雨","duration_minutes":30,"completion":"activity","rest":true}]}}]
    }]})
}

#[test]
fn gathering_and_building_consume_requirements_restock_at_dawn_and_survive_reload() {
    let mut w = world();
    let wood: Value = serde_json::from_str(WOOD).unwrap();
    put(
        &mut w,
        "drift",
        json!({"id":"test:drift","version":1,"name":"漂流木堆","actions":[{
            "id":"gather","label":"捡木头","duration_minutes":10,"completion":"activity",
            "supply":{"initial":2,"cost":1,"restock":{"amount":1,"max":2}},
            "on_complete":[{"kind":"give_item","item":wood,"count":1}]
        }]}),
    );
    put(&mut w, "camp", camp());
    // 布置检查：有漂流木堆，营地要的木头就有来处；只放营地的图上就弄不到。
    assert!(w.missing_materials().is_empty());
    let mut lonely = world();
    put(&mut lonely, "camp", camp());
    let gaps: Vec<_> = lonely.missing_materials().into_iter().collect();
    assert_eq!(gaps.len(), 1);
    assert_eq!(
        (
            gaps[0].prop.as_str(),
            gaps[0].action.as_str(),
            gaps[0].item.as_str()
        ),
        ("营地", "搭棚子", "木头")
    );
    let (ok, why) = act(&mut w, "b0", "camp", "搭棚子");
    assert!(!ok && why.contains("需要随身带着木头×2"), "{why}");
    assert!(act(&mut w, "g1", "drift", "捡木头").0);
    let (ok, text) = act(&mut w, "g2", "drift", "捡木头");
    assert!(
        ok && text.contains("得到木头×1") && text.contains("剩余 0 份"),
        "{text}"
    );
    let (ok, why) = act(&mut w, "g3", "drift", "捡木头");
    assert!(!ok && why.contains("补给已耗尽"), "{why}");
    assert_eq!(carried(&w, "木头"), 2);

    let (ok, text) = act(&mut w, "b1", "camp", "搭棚子");
    assert!(
        ok && text.contains("建成「棚子」") && text.contains("用掉木头×2"),
        "{text}"
    );
    assert_eq!(carried(&w, "木头"), 0);
    let shelter = on_map(&w, "棚子").expect("棚子建在原地");

    // 天亮补回一份，补到上限为止；搭好的棚子和补给余量都随存档保存。
    let drift = |w: &World| {
        let p = w.topo.prop("drift").unwrap();
        w.props()
            .supply_remaining("drift", p.verbs[0].action.as_ref().unwrap())
            .unwrap()
    };
    let to_dawn = 1440.0 + 360.0 - w.minutes() + 1.0;
    w.step(to_dawn);
    assert_eq!(drift(&w), 1);
    let fresh = common::world_with(common::two_places(json!([])), 420.0, &[]);
    let mut back = common::restore(&w, fresh);
    assert_eq!(drift(&back), 1);
    assert!(back.topo.prop(&shelter).is_some_and(|p| p.shelter));
    back.step(1440.0);
    back.step(1440.0);
    assert_eq!(drift(&back), 2);
}

#[test]
fn chance_is_replayable_and_signal_brings_a_boat_that_leaves_or_takes_the_resident() {
    let mut w = world();
    put(
        &mut w,
        "pool",
        json!({"id":"test:pool","version":1,"name":"潮池","actions":[{
            "id":"fish","label":"摸鱼","duration_minutes":10,"completion":"activity",
            "on_complete":[{"kind":"chance","percent":50,
                "effects":[{"kind":"restore","need":"fullness","amount":1.0}],"miss":"什么也没摸到"}]
        }]}),
    );
    let boat = json!({"id":"test:boat","version":1,"name":"小船","actions":[{
        "id":"board","label":"登船","duration_minutes":5,"completion":"activity",
        "on_complete":[{"kind":"depart","text":"登上小船离开了"}]
    }]});
    put(
        &mut w,
        "pyre",
        json!({"id":"test:pyre","version":1,"name":"篝火","actions":[{
            "id":"light","label":"点火","duration_minutes":5,"completion":"activity",
            "on_complete":[{"kind":"schedule","key":"boat","after_minutes":60.0,"text":"海上来了一艘小船",
                "place":{"prop":boat,"lasts_minutes":30.0,"leave_text":"小船开走了"}}]
        }]}),
    );
    // 同一存档往后掷出的结果一样；十次里有中有不中。
    let mut twin = common::restore(&w, {
        let mut t = world();
        t.step(0.0);
        t
    });
    let rolls = |w: &mut World| -> Vec<bool> {
        (0..10)
            .map(|i| {
                act(w, &format!("f{i}"), "pool", "摸鱼")
                    .1
                    .contains("饱腹恢复")
            })
            .collect()
    };
    let a = rolls(&mut w);
    assert_eq!(a, rolls(&mut twin));
    assert!(a.contains(&true) && a.contains(&false), "{a:?}");

    // 带着工具时按更高的概率掷：没有木矛几乎叉不到，带上木矛几乎都能叉到；说明里写着这一条。
    let spear = json!({"id":"test:spear","version":1,"name":"木矛","portable":true,"actions":[]});
    put(
        &mut w,
        "rack",
        json!({"id":"test:rack","version":1,"name":"木料","actions":[{
            "id":"carve","label":"削木矛","duration_minutes":5,"completion":"activity",
            "on_complete":[{"kind":"give_item","item":spear,"count":1}]
        }]}),
    );
    put(
        &mut w,
        "deep",
        json!({"id":"test:deep","version":1,"name":"深潭","actions":[{
            "id":"fish","label":"叉鱼","duration_minutes":10,"completion":"activity",
            "on_complete":[{"kind":"chance","percent":1,
                "boost":{"item":"test:spear","name":"木矛","percent":99},
                "effects":[{"kind":"restore","need":"fullness","amount":1.0}],"miss":"什么也没叉到"}]
        }]}),
    );
    let caught = |w: &mut World, tag: &str| {
        (0..5)
            .filter(|i| {
                act(w, &format!("{tag}{i}"), "deep", "叉鱼")
                    .1
                    .contains("饱腹恢复")
            })
            .count()
    };
    assert_eq!(caught(&mut w, "bare"), 0);
    assert!(act(&mut w, "carve", "rack", "削木矛").0);
    assert_eq!(caught(&mut w, "spear"), 5);
    let deep = w.topo.prop("deep").unwrap().verbs[0]
        .action
        .clone()
        .unwrap();
    let view = kernel::props::action_description_for(&deep, w.physiology());
    assert!(
        view.effects
            .iter()
            .any(|e| e.contains("随身带着木矛时 99%")),
        "{:?}",
        view.effects
    );

    // 点火后过一阵来船；没人上船就按时开走。
    let (ok, text) = act(&mut w, "l1", "pyre", "点火");
    assert!(ok && text.contains("之后会有动静"), "{text}");
    let (_, again) = act(&mut w, "l2", "pyre", "点火");
    assert!(again.contains("已经在等着发生"), "{again}");
    w.step(60.0);
    assert!(on_map(&w, "小船").is_some());
    w.step(31.0);
    assert!(on_map(&w, "小船").is_none());

    // 再点一次火，这回上船：人离开世界，不再在地图上。
    assert!(act(&mut w, "l3", "pyre", "点火").0);
    w.step(61.0);
    let boat_id = on_map(&w, "小船").expect("第二艘船到了");
    let (ok, text) = act(&mut w, "go", &boat_id, "登船");
    assert!(ok && text.contains("登上小船离开了"), "{text}");
    w.step(1.0);
    assert!(!w.actor("r").unwrap().present());
}

#[test]
fn rain_wears_down_the_exposed_until_ill_and_a_shelter_keeps_them_dry() {
    let mut w = common::world_with(common::tiny_topology(), 420.0, &[("r", "漂流者", "loc_a")]);
    use kernel::avatar::{Area, Spot, Surface, WalkMap};
    w.walk_map = Some(std::sync::Arc::new(WalkMap {
        version: 1,
        svg_units_per_metre: 10.,
        metres_per_minute: 12.,
        outdoor_space: "town_outdoor".into(),
        surfaces: vec![Surface {
            locale: "loc_a".into(),
            space: "town_outdoor".into(),
            area: Area::Rect {
                min: [0., 0.],
                max: [30., 30.],
            },
        }],
        stations: std::collections::BTreeMap::from([(
            "st_a".into(),
            Spot {
                locale: "loc_a".into(),
                space: "town_outdoor".into(),
                position: [2., 2.],
            },
        )]),
        ..Default::default()
    }));
    w.enable_weather(common::weather_rules(), 7, "island".into())
        .unwrap();
    w.set_weather(WeatherRequest {
        request_id: "rain".into(),
        expected_revision: w.weather().unwrap().view.revision,
        mode: WeatherMode::Fixed,
        kind: Some(WeatherKind::HeavyRain),
    })
    .unwrap();
    assert_eq!(w.exposure_at("r"), Exposure::Outdoor);
    let energy = |w: &World| w.actor("r").unwrap().needs.energy.value;

    // 开关关着时下雨不伤身。
    let before = energy(&w);
    w.step(30.0);
    let plain = before - energy(&w);
    assert_eq!(w.actor("r").unwrap().needs.body.wet, 0.0);

    let mut switches = w.physiology();
    switches.weather = true;
    w.set_physiology(switches);
    let before = energy(&w);
    w.step(30.0);
    assert!(before - energy(&w) > plain + 1.0);
    assert!(w
        .body_view("r")
        .unwrap()
        .causes
        .iter()
        .any(|c| c.contains("露天淋大雨")));
    w.step(61.0);
    let n = &w.actor("r").unwrap().needs;
    assert!(n
        .body
        .conditions
        .iter()
        .any(|c| c.kind == BodyConditionKind::Illness && c.source == "淋雨受凉"));
    // 湿透那一刻清零，之后又淋了一分钟。
    assert!(n.body.wet <= 1.0 + 1e-6);

    // 在遮蔽处避雨按室内算：不再淋湿，之前的湿气慢慢变干。
    w.step(20.0);
    let wet = w.actor("r").unwrap().needs.body.wet;
    assert!(wet > 10.0);
    put(
        &mut w,
        "hut",
        json!({"id":"test:hut","version":1,"name":"棚子","shelter":true,"actions":[{
            "id":"rest","label":"避雨","duration_minutes":30,"completion":"activity","rest":true
        }]}),
    );
    common::run(
        &mut w,
        "r",
        "hide",
        json!({"prop_id":"hut","intent":{"verb":"避雨"}}),
    )
    .unwrap();
    w.step(1.0);
    assert_eq!(w.exposure_at("r"), Exposure::Indoor);
    w.step(10.0);
    assert!(w.actor("r").unwrap().needs.body.wet < wet - 5.0);

    // 热带的雨淋湿得慢一半：避完雨出来，大雨里淋一小时只湿到 30（温带 60），三小时才着凉。
    w.set_climate(protocol::Climate::Tropical).unwrap();
    w.step(20.0);
    assert_eq!(w.exposure_at("r"), Exposure::Outdoor);
    let start = w.actor("r").unwrap().needs.body.wet;
    w.step(60.0);
    let gained = w.actor("r").unwrap().needs.body.wet - start;
    assert!((gained - 30.0).abs() < 1e-6, "{gained}");
}
