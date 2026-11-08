//! 题面体检：发给模型的内容只写给模型看的东西。两个村民按剧本采叶子、编篮子、聊天、送叶子、写信读信、
//! 往柜子里放东西，扫一遍发给模型的每个请求：不许出现 64 位哈希这类长十六进制编号、模型服务商的
//! 调用编号、四位以上的小数和空字段。以后加了字段、漏了清理，这里会报出是哪一次请求、哪一段。
use crate::support::*;
use agent::{
    budget::Limits,
    conversation::Role,
    runtime::{AgentRequest, ResidentRuntime},
};
use kernel::World;
use protocol::{GroupStatus, RequestKind};
use serde_json::{json, Value};

fn put(w: &mut World, id: &str, definition: Value) {
    let definition: kernel::props::Definition = serde_json::from_value(definition).unwrap();
    w.place_prop(
        serde_json::from_value(json!({
            "instance":{"id":id,"definition":definition.reference(),"locale":"loc_a"},
            "definition":definition
        }))
        .unwrap(),
    )
    .unwrap();
}

/// 一个采集处：做一次得到 count 件 item。
fn source(id: &str, label: &str, item: Value, count: u32) -> Value {
    json!({"id":format!("test:{id}"),"version":1,"name":format!("{label}处"),"actions":[{
        "id":"gather","label":label,"duration_minutes":5,"completion":"activity",
        "on_complete":[{"kind":"give_item","item":item,"count":count}]
    }]})
}

fn leaf() -> Value {
    json!({"id":"test:leaf","version":1,"name":"棕榈叶","portable":true,"stack_limit":5,"actions":[]})
}

/// 本人身上某样东西的编号，按编号排。
fn carried(w: &World, actor: &str, name: &str) -> Vec<String> {
    let mut ids: Vec<_> = w
        .topo
        .props()
        .iter()
        .filter(|p| !p.withdrawn && p.name == name && w.inventory().carried_by(&p.id, actor))
        .map(|p| p.id.clone())
        .collect();
    ids.sort();
    ids
}

/// 一次请求里给程序看的东西：长十六进制、服务商的调用编号、四位以上的小数、空字段。
/// 返回是哪一种和从哪里起的一段原文。
fn noise(text: &str) -> Option<(&'static str, String)> {
    let chars: Vec<char> = text.chars().collect();
    let around = |at: usize| chars[at.saturating_sub(40)..].iter().take(160).collect();
    let (mut run, mut letters) = (0, false);
    for (i, c) in chars.iter().enumerate() {
        if c.is_ascii_digit() || ('a'..='f').contains(c) {
            run += 1;
            letters |= c.is_ascii_alphabetic();
            if run >= 16 && letters {
                return Some(("长十六进制编号", around(i + 1 - run)));
            }
        } else {
            (run, letters) = (0, false);
        }
    }
    let found = |needle: &str| {
        text.find(needle)
            .map(|at| around(text[..at].chars().count()))
    };
    if let Some(at) = found("call_") {
        return Some(("服务商的调用编号", at));
    }
    let decimals = chars.windows(6).position(|w| {
        w[0].is_ascii_digit() && w[1] == '.' && w[2..].iter().all(char::is_ascii_digit)
    });
    if let Some(at) = decimals {
        return Some(("四位以上的小数", around(at)));
    }
    // 截断预览里的 JSON 是一段文字，空字段写作 \":null
    found("\":null").map(|at| ("空字段", at))
}

/// 照 DeepSeek 的样子编的调用编号：漏进题面一眼认得出。
fn call_id(n: usize) -> String {
    format!("call_{:02}_Zq9XkPf3LmW8RtY2vB5n{n:04}", n % 4)
}

/// 剧本：世界、运行器和发出过的全部请求。
struct Scene {
    w: World,
    r: ResidentRuntime,
    sent: Vec<AgentRequest>,
    calls: usize,
}

impl Scene {
    fn new() -> Self {
        let mut w = world();
        w.spawn("r2", "何青", "loc_a").unwrap();
        // 不让饿、渴、累的通知打断剧本；精力开着，躺椅的说明里有一长串小数
        w.set_physiology(protocol::PhysiologySwitches {
            fullness: false,
            water: false,
            energy: true,
            health: true,
            weather: false,
        });
        for id in ["r1", "r2"] {
            w.tune_needs(
                id,
                protocol::NeedsTuning {
                    energy_decay: 0.0,
                    ..kernel::default_tuning()
                },
            )
            .unwrap();
        }
        put(&mut w, "palm", source("palm", "采叶子", leaf(), 5));
        put(
            &mut w,
            "loom",
            json!({"id":"test:loom","version":1,"name":"编织台","actions":[{
                "id":"weave","label":"编篮子","duration_minutes":10,"completion":"activity",
                "requires":[{"item":"test:leaf","name":"棕榈叶","count":2,"consume":true}],
                "on_complete":[{"kind":"give_item","item":{"id":"test:basket","version":1,"name":"叶编篮","portable":true,"actions":[]},"count":1}]
            }]}),
        );
        put(
            &mut w,
            "cabinet",
            json!({"id":"test:cabinet","version":1,"name":"柜子","storage_slots":4,"actions":[]}),
        );
        put(
            &mut w,
            "desk",
            json!({"id":"test:desk","version":1,"name":"书桌","actions":[{
                "id":"write","label":"写信","duration_minutes":120,"completion":"write_book"
            }]}),
        );
        put(
            &mut w,
            "chair",
            json!({"id":"test:chair","version":1,"name":"躺椅","actions":[{
                "id":"rest","label":"歇一会","duration_minutes":30,"completion":"activity",
                "during":[{"kind":"restore_need","need":"energy","per_minute":0.8333333333333334,"pause_decay":true}]
            }]}),
        );
        // 窗口开得小，几轮就要折叠，累积摘要也在体检之列
        let limits = Limits {
            compact_at_tokens: 14_000,
            ..Limits::default()
        };
        let mut r = runtime(&mut w, limits);
        r.register(&mut w, "r2", "何青，喜欢手工，和阿树是邻居。")
            .unwrap();
        Self {
            w,
            r,
            sent: vec![],
            calls: 0,
        }
    }

    /// 一直走到 `actor` 发出 `kind` 轮次的请求、并且 `ready`；途中别的请求按默认的样子回。
    fn turn_when(
        &mut self,
        actor: &str,
        kind: RequestKind,
        ready: impl Fn(&World) -> bool,
    ) -> AgentRequest {
        for _ in 0..3000 {
            let mut mine = None;
            for q in self.r.poll(&mut self.w, true) {
                self.sent.push(q.clone());
                let wanted = q.actor_id == actor && q.stamp.kind == kind && ready(&self.w);
                if mine.is_none() && wanted {
                    mine = Some(q);
                } else {
                    self.idle(&q);
                }
            }
            if let Some(q) = mine {
                return q;
            }
            self.w.step(1.0);
        }
        panic!("等不到 {actor} 的 {kind:?} 请求");
    }

    fn turn(&mut self, actor: &str, kind: RequestKind) -> AgentRequest {
        self.turn_when(actor, kind, |_| true)
    }

    fn answer(&mut self, q: &AgentRequest, calls: Vec<(&str, Value)>) {
        let calls = calls
            .into_iter()
            .map(|(name, args)| {
                self.calls += 1;
                tool_call(&call_id(self.calls), name, args)
            })
            .collect();
        assert!(reply_with(&mut self.r, &mut self.w, q, "按计划来。", calls));
    }

    /// 不在剧本里的请求：整理交一份空整理，交谈轮到了就倾听，生活决策就等人来找。
    fn idle(&mut self, q: &AgentRequest) {
        let call = match q.stamp.kind {
            RequestKind::Reflection => {
                let through = q
                    .messages
                    .iter()
                    .find_map(|m| {
                        serde_json::from_str::<Value>(&m.content)
                            .ok()?
                            .pointer("/reflection_task/through")?
                            .as_u64()
                    })
                    .unwrap();
                (
                    "reflect",
                    json!({"through_event":through,"summary":"整理完毕。","notes":[]}),
                )
            }
            RequestKind::Chat => ("interact", json!({"operation":"listen"})),
            RequestKind::Life => (
                "wait_for",
                json!({"event":"interaction","reason":"等人来找"}),
            ),
        };
        self.answer(q, vec![call]);
    }
}

#[test]
fn prompts_carry_no_ids_hashes_long_decimals_or_empty_fields() {
    let mut s = Scene::new();
    let life = RequestKind::Life;
    let q = s.turn("r1", life);
    s.answer(
        &q,
        vec![(
            "run_actions",
            json!({"actions":[{"intent":{"verb":"采叶子"},"prop_id":"palm"}]}),
        )],
    );
    let q = s.turn("r1", life);
    s.answer(
        &q,
        vec![(
            "run_actions",
            json!({"actions":[{"intent":{"verb":"编篮子"},"prop_id":"loom"}]}),
        )],
    );
    let q = s.turn("r1", life);
    s.answer(
        &q,
        vec![(
            "offer_invitation",
            json!({"partner_id":"r2","interaction":{"kind":"talk"},"message":"何青，聊两句？"}),
        )],
    );
    let q = s.turn("r2", life);
    let talk = s.w.interactions().for_actor("r2")[0].id.clone();
    s.answer(
        &q,
        vec![(
            "reply_invitation",
            json!({"interaction_id":talk,"accept":true,"message":"好啊"}),
        )],
    );
    let q = s.turn("r1", RequestKind::Chat);
    s.answer(
        &q,
        vec![(
            "interact",
            json!({"operation":"say","message":"叶子采好了，还编了个篮子。"}),
        )],
    );
    let q = s.turn("r2", RequestKind::Chat);
    s.answer(
        &q,
        vec![(
            "interact",
            json!({"operation":"say","message":"真好看，能分我几片叶子吗？"}),
        )],
    );
    let q = s.turn("r1", RequestKind::Chat);
    s.answer(
        &q,
        vec![(
            "interact",
            json!({"operation":"leave","message":"这就给你，我先去写封信。"}),
        )],
    );
    // 背包里三片叶子只列一个编号：送两片就把它写两遍，由系统从这一堆里挑
    let q = s.turn("r1", life);
    let leaves = carried(&s.w, "r1", "棕榈叶");
    assert_eq!(leaves.len(), 3);
    s.answer(
        &q,
        vec![(
            "offer_invitation",
            json!({"partner_id":"r2","interaction":{"kind":"give","items":[leaves[0],leaves[0]]},"message":"给你两片"}),
        )],
    );
    let q = s.turn_when("r2", life, |w| {
        w.interactions()
            .for_actor("r2")
            .iter()
            .any(|i| i.status == protocol::InteractionStatus::Offered)
    });
    let gift =
        s.w.interactions()
            .for_actor("r2")
            .iter()
            .find(|i| i.status == protocol::InteractionStatus::Offered)
            .unwrap()
            .id
            .clone();
    s.answer(
        &q,
        vec![(
            "reply_invitation",
            json!({"interaction_id":gift,"accept":true,"message":"谢谢"}),
        )],
    );
    let q = s.turn_when("r1", life, |w| carried(w, "r2", "棕榈叶").len() == 2);
    s.answer(
        &q,
        vec![(
            "run_actions",
            json!({"actions":[{"intent":{"verb":"写信"},"prop_id":"desk",
                "writing":{"title":"给何青的信","text":"篮子放进柜子了，想用就去拿。"}}]}),
        )],
    );
    let letter = |w: &World| {
        w.topo
            .props()
            .iter()
            .find(|p| p.id.starts_with("written:"))
            .map(|p| p.id.clone())
    };
    let q = s.turn_when("r2", life, |w| letter(w).is_some());
    let letter = letter(&s.w).unwrap();
    s.answer(
        &q,
        vec![(
            "run_actions",
            json!({"actions":[{"intent":{"verb":"阅读"},"prop_id":letter}]}),
        )],
    );
    let read = |w: &World| {
        w.contents()
            .readings
            .get("r2")
            .and_then(|r| r.keys().next_back().copied())
    };
    let q = s.turn_when("r2", life, |w| read(w).is_some());
    let event_id = read(&s.w).unwrap();
    s.answer(&q, vec![("read_content", json!({"event_id":event_id}))]);
    let q = s.turn("r1", life);
    let basket = carried(&s.w, "r1", "叶编篮");
    let leaf = carried(&s.w, "r1", "棕榈叶");
    s.answer(
        &q,
        vec![(
            "run_actions",
            json!({"actions":[{"intent":{"verb":"存放"},
                "inventory":{"operation":"store","items":[basket[0],leaf[0]],"container":"cabinet"}}]}),
        )],
    );
    let q = s.turn_when("r1", life, |w| carried(w, "r1", "叶编篮").is_empty());
    s.answer(
        &q,
        vec![("inspect", json!({"id":"cabinet"})), ("observe", json!({}))],
    );
    s.turn("r1", life);

    // 剧本真的走完了：两片叶子到了何青手里，信读了，柜子里放着篮子和一片叶子
    assert_eq!(carried(&s.w, "r2", "棕榈叶").len(), 2);
    let all: Vec<&str> = s
        .sent
        .iter()
        .flat_map(|q| &q.messages)
        .map(|m| m.content.as_str())
        .collect();
    for (what, needle) in [
        ("背包一堆一条", "\"quantity\":3"),
        ("身边人带着的东西", "\"carrying\""),
        ("别人递过来的东西", "\"offered_items\""),
        ("柜子里存的", "\"stored_items\""),
        ("读到的信", "给何青的信"),
        ("累积摘要", "此前会话的累积摘要"),
        ("摘要里写成人话的动作", "动作：采叶子，完成"),
    ] {
        assert!(all.iter().any(|c| c.contains(needle)), "题面里没见到{what}");
    }

    for (n, q) in s.sent.iter().enumerate() {
        for m in q.messages.iter().filter(|m| m.role != Role::Assistant) {
            if let Some((what, at)) = noise(&m.content) {
                panic!(
                    "第 {n} 次请求（{}，{:?}）的 {:?} 消息里有{what}：{at}",
                    q.actor_id, q.stamp.kind, m.role
                );
            }
        }
    }
}

/// 大逃杀第三局：背包只分到观察的八分之一，八格塞满时被截成开头一段，排在后面的急救包、竹筒水
/// 在题面里看不见，白鸦拿到急救包后七十多次请求都不知道自己有。
#[test]
fn a_bag_full_of_odds_and_ends_still_shows_the_first_aid_kit_and_water() {
    let mut w = world();
    let mut gather = Vec::new();
    for (n, name) in ["石块", "棕榈叶", "树枝", "贝壳", "椰子壳", "破布"]
        .into_iter()
        .enumerate()
    {
        let item = json!({"id":format!("core:island-junk-{n}"),"version":1,"name":name,"portable":true,"stack_limit":5,
            "actions":[{"id":"throw","label":format!("扔{name}"),"duration_minutes":1,"completion":"activity"}]});
        put(
            &mut w,
            &format!("junk{n}"),
            source(&format!("junk{n}"), &format!("捡{name}"), item, 5),
        );
        gather.push((format!("junk{n}"), format!("捡{name}")));
    }
    let water = json!({"id":"core:island-water-tube","version":1,"name":"竹筒水","portable":true,"actions":[{
        "id":"drink","label":"喝竹筒水","duration_minutes":2,"completion":"activity","consumes_item":true,
        "on_complete":[{"kind":"restore","need":"water","amount":30}]}]});
    let aid = json!({"id":"tide:first-aid","version":1,"name":"急救包","portable":true,"actions":[
        {"id":"illness","label":"用急救包治病","duration_minutes":5,"completion":"activity","consumes_item":true,"recipient":true,
         "on_complete":[{"kind":"cure_condition","condition":"illness"}]},
        {"id":"injury","label":"用急救包包扎","duration_minutes":5,"completion":"activity","consumes_item":true,"recipient":true,
         "on_complete":[{"kind":"cure_condition","condition":"injury"},{"kind":"restore","need":"health","amount":20.0}]}]});
    put(&mut w, "spring", source("spring", "灌竹筒水", water, 1));
    put(&mut w, "crate", source("crate", "开木箱", aid, 1));
    gather.push(("spring".into(), "灌竹筒水".into()));
    gather.push(("crate".into(), "开木箱".into()));
    w.enable_agent("r1").unwrap();
    for (n, (prop, verb)) in gather.iter().enumerate() {
        let key = format!("g{n}");
        let revision = w.actor("r1").unwrap().actions.revision;
        let draft = json!({"prop_id":prop,"intent":{"verb":verb}});
        w.run_actions(
            "r1",
            &key,
            revision,
            &[serde_json::from_value(draft).unwrap()],
        )
        .unwrap();
        while w.action_group("r1", &key).unwrap().status == GroupStatus::Running {
            w.step(0.5);
        }
    }
    assert_eq!(w.inventory_view("r1").used, 8, "八格塞满");

    let mut r = runtime(&mut w, Limits::default());
    let q = request(&mut r, &mut w);
    let observation = q
        .messages
        .iter()
        .rev()
        .find_map(|m| {
            serde_json::from_str::<Value>(&m.content)
                .ok()?
                .get("observation")
                .cloned()
        })
        .unwrap();
    assert!(
        observation.get("inventory_source").is_none(),
        "背包没被截断"
    );
    let bag = &observation["inventory"]["slots"];
    let names: Vec<_> = bag
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["name"].as_str().unwrap())
        .collect();
    assert!(
        names.contains(&"急救包") && names.contains(&"竹筒水"),
        "{names:?}"
    );
    // 一堆五件只列一个编号，能拿它做的事只列名字
    let stone = bag
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["name"] == "石块")
        .unwrap();
    assert_eq!(stone["quantity"], 5);
    assert!(stone["id"].as_str().unwrap().len() < 20, "{stone}");
    let aid = bag
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["name"] == "急救包")
        .unwrap();
    assert_eq!(aid["actions"], json!(["用急救包治病", "用急救包包扎"]));
}
