//! 多村民 V1：没有默认村民，运行中从村民库加入、空村、旧档迁移、重置清空、住宅决定上限而不是人数。
use crate::support::*;
use serde_json::{json, Value};
use std::fs;

#[test]
fn joining_while_running_keeps_the_first_resident_and_survives_restart() {
    let mut town = Town::new();
    let mut ws = town.start();
    let first = until(&mut ws, |m| m["type"] == "roster");
    assert!(members(&first).is_empty(), "没有默认村民");
    let first = join(&mut ws, "tpl_a", None);
    assert_eq!(first["ok"], true, "{first}");
    assert_eq!(first["home"], "home_1");
    let first_id = first["resident_id"].as_str().unwrap().to_string();
    let population =
        reply(&mut ws, json!({"type":"get_population"}), "population")["population"].clone();
    assert_eq!(population["residents"].as_array().unwrap().len(), 1);
    assert_eq!(population["residents"][0]["template_id"], "tpl_a");
    assert_eq!(population["entry_name"], "门口");
    let library = reply(
        &mut ws,
        json!({"type":"get_resident_library","filter":{}}),
        "resident_library",
    );
    let cards = library["templates"].as_array().unwrap();
    assert_eq!(cards.len(), 3);
    let status =
        |id: &str| cards.iter().find(|c| c["template_id"] == id).unwrap()["status"].clone();
    assert_eq!(status("tpl_a"), "joined");
    assert_eq!(status("tpl_b"), "available");

    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":20}),
    );
    until(&mut ws, |m| {
        m["type"] == "roster" && m["sim_minutes"].as_f64().unwrap() > 425.0
    });
    let calls_before = usage_of(&mut ws, &first_id)["daily_calls"]
        .as_u64()
        .unwrap();
    let outcome = join(&mut ws, "tpl_b", None);
    assert_eq!(outcome["ok"], true, "{outcome}");
    assert_eq!(outcome["name"], "阿乙");
    assert_eq!(outcome["home"], "home_2", "按住宅配置顺序分配下一处空房");
    let joined_at = outcome["joined_at"].as_f64().unwrap();
    assert!(joined_at > 425.0, "世界时间不回退");
    let id = outcome["resident_id"].as_str().unwrap().to_string();
    let roster = until(&mut ws, |m| m["type"] == "roster" && members(m).len() == 2);
    let people = members(&roster);
    let second = people.iter().find(|m| m["id"] == id).unwrap();
    assert_eq!(second["locale"], "gate", "出现在入口");
    assert!(
        second["plan"]["upcoming"].as_array().unwrap().is_empty(),
        "没有入村脚本"
    );
    assert!(
        usage_of(&mut ws, &first_id)["daily_calls"]
            .as_u64()
            .unwrap()
            >= calls_before,
        "第一人的用量没有被初始化"
    );
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":0}),
    );
    until(&mut ws, |m| m["type"] == "roster" && m["speed"] == 0.0);

    // 同名加入、同模板再加入都被拒绝，且没有世界副作用；同号同内容返回原结果。
    let clash = join(&mut ws, "tpl_c", Some("阿乙"));
    assert_eq!(clash["ok"], false);
    assert!(
        clash["message"].as_str().unwrap().contains("叫「阿乙」"),
        "{clash}"
    );
    assert_eq!(members(&until(&mut ws, |m| m["type"] == "roster")).len(), 2);
    let population =
        reply(&mut ws, json!({"type":"get_population"}), "population")["population"].clone();
    let world_id = population["world_id"].as_str().unwrap().to_string();
    let op = json!({"type":"join_resident","op_id":"dup-1","world_id":world_id,"template_id":"tpl_c","template_version":1,"name":"阿丙","home":"home_3"});
    send(&mut ws, op.clone());
    let once = until(&mut ws, |m| {
        m["type"] == "resident_joined" && m["outcome"]["op_id"] == "dup-1"
    })["outcome"]
        .clone();
    send(&mut ws, op);
    let again = until(&mut ws, |m| {
        m["type"] == "join_result" && m["op_id"] == "dup-1"
    })["outcome"]
        .clone();
    assert_eq!(once["resident_id"], again["resident_id"]);
    assert_eq!(members(&until(&mut ws, |m| m["type"] == "roster")).len(), 3);
    let repeat = join(&mut ws, "tpl_b", None);
    assert_eq!(repeat["ok"], false);
    assert!(
        repeat["message"].as_str().unwrap().contains("已在村中"),
        "{repeat}"
    );
    assert_eq!(members(&until(&mut ws, |m| m["type"] == "roster")).len(), 3);

    // 模板归档不影响已入村的人；个人设定接口按新 id 可用。
    let archived = reply(
        &mut ws,
        json!({"type":"archive_resident_template","request_id":"test-archive-resident-template","template_id":"tpl_b","expected_version":1,"archived":true}),
        "template_saved",
    );
    assert_eq!(archived["ok"], true);
    let config = reply(
        &mut ws,
        json!({"type":"get_agent_config","resident":id}),
        "agent_config",
    );
    assert_eq!(config["resident"], "阿乙");
    assert!(config["persona"]
        .as_str()
        .unwrap()
        .contains("来到小镇的第一天"));
    let saved = reply(
        &mut ws,
        json!({"type":"set_persona","request_id":"test-set-persona","resident":id,"text":"# 阿乙\n更新后的人设"}),
        "agent_saved",
    );
    assert_eq!(saved["ok"], true);
    assert_eq!(join_receipts(&mut ws, &id), 1, "入村记录只写一次");

    // 重启：同一批人、同一住宅、同一入村时间；入村事件不重复。
    town.kill();
    drop(ws);
    let mut ws = town.start();
    let restored = until(&mut ws, |m| m["type"] == "roster");
    assert_eq!(members(&restored).len(), 3);
    let population =
        reply(&mut ws, json!({"type":"get_population"}), "population")["population"].clone();
    let second = population["residents"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["id"] == id)
        .unwrap();
    assert_eq!(second["home"], "home_2");
    assert_eq!(second["joined_at"].as_f64().unwrap(), joined_at);
    let config = reply(
        &mut ws,
        json!({"type":"get_agent_config","resident":id}),
        "agent_config",
    );
    assert_eq!(
        config["persona"], "# 阿乙\n更新后的人设",
        "人设快照随存档保存"
    );
    assert_eq!(join_receipts(&mut ws, &id), 1, "入村记录只写一次");
    let disk: Value = serde_json::from_slice(&fs::read(town.save()).unwrap()).unwrap();
    assert_eq!(disk["schema_version"], 6);
    assert_eq!(
        disk["population"]["residents"].as_object().unwrap().len(),
        3
    );
}

/// 村民库所有小镇共用：A 镇存进村民库的人，B 镇打开就看得到、请得来。旧版存在各小镇自己目录里的
/// 模板和隐藏记录收进共用库，原文件不删。
#[test]
fn every_town_shares_one_villager_library() {
    let mut a = Town::new();
    let shared = a.dir.join("shared-library");
    a.share_library(&shared);
    let mut ws = a.start();
    let saved = reply(
        &mut ws,
        json!({"type":"save_resident_template","request_id":"shared-template","fields":{"name":"小满",
            "intro":"","tags":[],"appearance":{"marker":"dot","color":"#000"}}}),
        "template_saved",
    );
    assert_eq!(saved["ok"], true, "{saved}");
    let made = saved["template"]["template_id"]
        .as_str()
        .unwrap()
        .to_owned();
    a.kill();
    drop(ws);

    let mut b = Town::new();
    b.share_library(&shared);
    let mut old = read_json(&fixture("library/tpl_a.json"));
    old["template_id"] = json!("custom_old");
    old["builtin"] = json!(false);
    old["fields"]["name"] = json!("老街坊");
    b.write("old-town/resident-library/templates/custom_old.json", old);
    b.write(
        "old-town/resident-library/state.json",
        json!({"archived_builtin":["tpl_c"]}),
    );
    let mut ws = b.start();
    let library = reply(
        &mut ws,
        json!({"type":"get_resident_library","filter":{}}),
        "resident_library",
    );
    let listed = |id: &str| {
        library["templates"]
            .as_array()
            .unwrap()
            .iter()
            .any(|c| c["template_id"] == id)
    };
    assert!(listed(&made), "A 镇存的人 B 镇看得到：{library}");
    assert!(listed("custom_old"), "旧版小镇里的模板收进来了：{library}");
    assert!(!listed("tpl_c"), "旧版隐藏的内置模板仍然隐藏");
    join_id(&mut ws, &made);
    assert!(b
        .dir
        .join("old-town/resident-library/templates/custom_old.json")
        .exists());
    assert!(shared.join("templates/custom_old.json").exists());
}

/// 捏人：模板带的长相随加入抄进登记；单独改一位居民只改这一位，别的页面收到新名单，重启后还在。
/// 长相不合格或名单版本过期时退回，模板和登记都不变。
#[test]
fn a_residents_look_follows_the_template_and_survives_restart() {
    let mut town = Town::new();
    let mut ws = town.start();
    let look = json!({"hair":"twintail","outfit":"dress","hair_color":"#d8a040","eye_color":"#4c77da",
        "skin":"#f6ece0","top":"#c88a8e","bottom":"#3a3a44","accent":"#e44a4e","headband":"#e44a4e",
        "pattern":{"on":"top","color":"#f4f6f4","rows":["#.#.",".#.#","#.#.",".#.#"]}});
    let template = |name: &str, look: &Value| {
        json!({"type":"save_resident_template","request_id":"look-template","fields":{"name":name,
            "intro":"","tags":[],"appearance":{"marker":"dot","color":"#b4691e","look":look}}})
    };
    let mut broken = look.clone();
    broken["hair_color"] = json!("red");
    let refused = reply(&mut ws, template("小草", &broken), "template_saved");
    assert_eq!(refused["ok"], false);
    assert!(
        refused["message"].as_str().unwrap().contains("发色"),
        "{refused}"
    );
    let saved = reply(&mut ws, template("小花", &look), "template_saved");
    assert_eq!(saved["ok"], true, "{saved}");
    assert_eq!(saved["template"]["fields"]["appearance"]["look"], look);
    let id = join_id(&mut ws, saved["template"]["template_id"].as_str().unwrap());
    let population = |ws: &mut tungstenite::WebSocket<std::net::TcpStream>| {
        reply(ws, json!({"type":"get_population"}), "population")["population"].clone()
    };
    let before = population(&mut ws);
    let registration = |p: &Value| {
        p["residents"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["id"] == id)
            .unwrap()
            .clone()
    };
    assert_eq!(
        registration(&before)["appearance"]["look"],
        look,
        "加入时照模板长"
    );

    let change = |revision: &Value, look: &Value| {
        json!({"type":"set_resident_appearance","request_id":"look-1","world_id":before["world_id"],
            "expected_revision":revision,"resident_id":id,
            "appearance":{"marker":"x","color":"#000000","look":look}})
    };
    let mut crooked = look.clone();
    crooked["pattern"]["rows"] = json!(["#.#", ".#.#", "#.#.", ".#.#"]);
    for (bad, why) in [
        (change(&before["revision"], &crooked), "花纹"),
        (change(&json!(0), &look), "名单"),
    ] {
        let answer = reply(&mut ws, bad, "resident_appearance_saved");
        assert_eq!(answer["ok"], false, "{answer}");
        assert!(
            answer["message"].as_str().unwrap().contains(why),
            "{answer}"
        );
    }
    assert_eq!(population(&mut ws), before, "退回的修改不碰登记");

    let mut other = connect_again(&ws);
    let mut changed = look.clone();
    changed["hair"] = json!("crop");
    changed["beard"] = json!(true);
    changed.as_object_mut().unwrap().remove("pattern");
    let answer = reply(
        &mut ws,
        change(&before["revision"], &changed),
        "resident_appearance_saved",
    );
    assert_eq!(answer["ok"], true, "{answer}");
    let seen = until(&mut other, |m| m["type"] == "population");
    let appearance = registration(&seen["population"])["appearance"].clone();
    assert_eq!(appearance["look"], changed, "别的页面也换上");
    assert_eq!(
        (appearance["marker"].clone(), appearance["color"].clone()),
        (json!("dot"), json!("#b4691e")),
        "只换长相，地图标记和颜色沿用登记里的"
    );
    let library = reply(
        &mut ws,
        json!({"type":"get_resident_template","template_id":saved["template"]["template_id"]}),
        "resident_template",
    );
    assert_eq!(
        library["template"]["fields"]["appearance"]["look"], look,
        "不回写模板"
    );

    // 名单回读一次，确认上一条命令已存盘，再重启
    population(&mut ws);
    town.kill();
    drop((ws, other));
    let mut ws = town.start();
    assert_eq!(
        registration(&population(&mut ws))["appearance"]["look"],
        changed
    );
}

/// 加入事务在存盘一步失败：回执明确失败，世界与登记表都回到加入前；障碍消除后同一人能再加入，编号不跳号。
#[test]
fn join_rolls_back_when_saving_fails_and_keeps_world_and_registry_consistent() {
    let mut town = Town::new();
    let mut ws = town.start();
    let first = join_id(&mut ws, "tpl_a");
    assert_eq!(first, "resident_001");
    let blocker = town.save().with_file_name("world.json.tmp");
    fs::create_dir(&blocker).unwrap();
    let failed = join(&mut ws, "tpl_b", None);
    assert_eq!(failed["ok"], false, "{failed}");
    assert!(failed["message"].as_str().is_some_and(|m| !m.is_empty()));
    assert!(failed["resident_id"].is_null());
    let population =
        reply(&mut ws, json!({"type":"get_population"}), "population")["population"].clone();
    assert_eq!(population["residents"].as_array().unwrap().len(), 1);
    let roster = until(&mut ws, |m| m["type"] == "roster");
    assert_eq!(members(&roster).len(), 1);
    assert!(
        population["homes"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|h| !h["occupant"].is_null())
            .count()
            == 1
    );
    fs::remove_dir(&blocker).unwrap();
    let second = join(&mut ws, "tpl_b", None);
    assert_eq!(second["ok"], true, "{second}");
    assert_eq!(second["resident_id"], "resident_002");
    assert_eq!(members(&until(&mut ws, |m| m["type"] == "roster")).len(), 2);
    let disk: Value = serde_json::from_slice(&fs::read(town.save()).unwrap()).unwrap();
    assert_eq!(
        disk["population"]["residents"].as_object().unwrap().len(),
        2
    );
}

/// 今天日志里「来到小镇」的执行记录条数。
fn join_receipts(ws: &mut tungstenite::WebSocket<std::net::TcpStream>, id: &str) -> usize {
    let diary = reply(ws, json!({"type":"get_diary","resident":id}), "diary");
    let today = diary["days"].as_array().unwrap().last().unwrap();
    today["receipts"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|r| r["text"].as_str().unwrap().contains("来到小镇"))
        .count()
}
