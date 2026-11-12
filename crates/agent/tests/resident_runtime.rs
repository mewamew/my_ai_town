use crate::support::*;
use agent::{
    budget::Limits,
    context,
    runtime::ResidentRuntime,
    session::{GoalStatus, PauseKind},
};
use serde_json::json;

#[test]
fn outdated_replies_are_counted_and_two_revision_conflicts_in_a_row_stop_only_this_resident() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    let counts = |r: &ResidentRuntime| {
        let s = r.session("r1").unwrap();
        (
            s.tally.replies,
            s.tally.stale_replies,
            s.streaks.stale_streak,
        )
    };
    let first = request(&mut r, &mut w);
    // 请求期间外部改了安排：整条回复作废。
    w.interrupt_actions("r1", "安排被打断");
    assert!(!reply_with(&mut r, &mut w, &first, "先看看。", vec![]));
    assert_eq!(counts(&r), (1, 1, 1));
    assert!(r.session("r1").unwrap().pause_reason().is_none());
    // 请求期间收到重要通知：改变世界的动作被退回，但这和速度无关，不计连续次数。
    let second = request(&mut r, &mut w);
    w.set_need_values("r1", Some(30.0), None).unwrap();
    reply(
        &mut r,
        &mut w,
        &second,
        "run_actions",
        json!({"actions":[{"intent":{"verb":"阅读公告"},"prop_id":"board"}]}),
    );
    assert_eq!(counts(&r), (2, 2, 1));
    assert!(r.session("r1").unwrap().pause_reason().is_none());
    // 又一次请求期间世界状态被改掉：连续两次，停本人。
    let third = request(&mut r, &mut w);
    w.interrupt_actions("r1", "安排又被打断");
    assert!(!reply_with(&mut r, &mut w, &third, "再看看。", vec![]));
    assert_eq!(counts(&r), (3, 3, 2));
    let s = r.session("r1").unwrap();
    assert_eq!(s.pause_kind(), PauseKind::Stale);
    assert!(s.pause_reason().is_some());
    // 停下的人不再做决定，世界照走会把他饿死渴死：全镇一起停
    assert_eq!(r.town_holds(&w).len(), 1, "过时也让全镇暂停");
    w.step(30.0);
    assert!(r.poll(&mut w, true).is_empty());
    assert_eq!(r.resume(&w), 1);
    let fourth = request(&mut r, &mut w);
    reply(&mut r, &mut w, &fourth, "observe", json!({}));
    assert_eq!(counts(&r), (4, 3, 0));
    // 消耗页的按人一行照这两个数显示
    let usage = r.session("r1").unwrap().usage(&w);
    assert_eq!((usage.replies, usage.stale_replies), (4, 3));
}

#[test]
fn repeated_model_failures_pause_the_town_after_bounded_retries() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    // 重试按现实时间隔开（poll_at 给定现实时刻），和世界走了几分钟无关。
    let mut now = 1_000;
    for attempt in 1..=3 {
        let mut requests = r.poll_at(&mut w, true, now);
        assert_eq!(requests.len(), 1, "到了重试时刻就再发");
        let q = requests.remove(0);
        assert!(r.on_reply(
            &mut w,
            "r1",
            q.stamp.id,
            q.stamp.epoch,
            Err(agent::completion::ModelError::Http {
                status: 504,
                detail: "网关超时".into()
            }),
            90_000
        ));
        let s = r.session("r1").unwrap();
        assert_eq!(s.streaks.model_failures, attempt);
        if attempt < 3 {
            assert!(s.pause_reason().is_none(), "前两次隔一阵重试");
            assert!(s.sleep().is_none(), "不按模拟时间搁置");
            let wait = 20 * u64::from(attempt);
            w.step(60.0);
            assert!(r.poll_at(&mut w, true, now + wait - 1).is_empty());
            now += wait;
        }
    }
    let s = r.session("r1").unwrap();
    assert_eq!(s.pause_kind(), PauseKind::Fault);
    assert!(s.pause_reason().unwrap().contains("连续 3 次"));
    let holds = r.town_holds(&w);
    assert_eq!(holds.len(), 1);
    // 提示卡按原因类别给修复按钮：服务端出错是「拒收」，不是密钥或网络
    assert_eq!(holds[0].cause, protocol::HoldCause::Rejected);
    w.step(31.0);
    assert!(r.poll(&mut w, true).is_empty());
    assert_eq!(r.resume(&w), 1);
    assert_eq!(r.session("r1").unwrap().streaks.model_failures, 0);
    assert_eq!(r.poll(&mut w, true).len(), 1);
}

#[test]
fn pending_action_and_goal_survive_compaction_and_process_recovery() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    let goal = request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &goal,
        "set_goal",
        json!({"id":"read","title":"看公告","condition":{"kind":"action","verb":"阅读公告","locale":"loc_a"},"status":"active","commitment":"读完再决定要不要接活"}),
    );
    let mut session = r.session("r1").unwrap().clone();
    assert!(context::compact(&mut session, 0).unwrap());
    assert_eq!(session.goals["read"].commitment, "读完再决定要不要接活");
    let q = request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "run_actions",
        json!({"actions":[{"intent":{"verb":"阅读公告"},"prop_id":"board"}]}),
    );
    w.step(0.3);
    let mut pending = r.session("r1").unwrap().clone();
    let before = pending.messages.clone();
    assert!(context::compact(&mut pending, 0).is_err());
    assert_eq!(pending.messages, before);
    let saved_world = serde_json::to_value(w.snapshot()).unwrap();
    let saved_runtime = serde_json::to_value(r.state()).unwrap();
    let mut recovered = world();
    recovered
        .restore_snapshot(serde_json::from_value(saved_world).unwrap())
        .unwrap();
    let mut restored =
        ResidentRuntime::restore(serde_json::from_value(saved_runtime).unwrap(), &recovered)
            .unwrap();
    recovered.step(0.8);
    let q = request(&mut restored, &mut recovered);
    reply(
        &mut restored,
        &mut recovered,
        &q,
        "set_goal",
        json!({"id":"read","title":"看公告","condition":{"kind":"action","verb":"阅读公告","locale":"loc_a"},"status":"completed","commitment":"读完再决定要不要接活"}),
    );
    assert_eq!(
        restored.session("r1").unwrap().goals["read"].status,
        GoalStatus::Completed
    );
    assert_eq!(recovered.actor("r1").unwrap().actions.groups.len(), 1);
}

#[test]
fn bounded_concurrency_dispatches_other_residents_fairly() {
    let mut w = world();
    w.spawn("r2", "阿禾", "loc_a").unwrap();
    w.spawn("r3", "阿林", "loc_a").unwrap();
    let mut r = runtime(
        &mut w,
        Limits {
            max_concurrent: 2,
            ..Limits::default()
        },
    );
    r.register(&mut w, "r2", "喜欢看书").unwrap();
    r.register(&mut w, "r3", "喜欢手工").unwrap();
    let initial = r.poll(&mut w, true);
    assert_eq!(initial.len(), 2);
    assert!(r.poll(&mut w, true).is_empty());
    reply(&mut r, &mut w, &initial[0], "observe", json!({}));
    let next = r.poll(&mut w, true);
    assert_eq!(next.len(), 1);
    assert_eq!(next[0].actor_id, "r3");
    assert!(r.poll(&mut w, false).is_empty());
}

#[test]
fn local_model_action_shapes_still_move_and_complete_the_requested_work() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    let q = request(&mut r, &mut w);
    // 实际本地模型回复：漏掉 actions，intent 又编码成字符串。
    reply(
        &mut r,
        &mut w,
        &q,
        "run_actions",
        json!({"intent": r#"{"verb":"前往","locale":"loc_b","target":null}"#}),
    );
    assert_eq!(r.session("r1").unwrap().pending.len(), 1);
    w.step(3.0);
    assert_eq!(w.actor("r1").unwrap().locus.locale, "loc_b");

    let q = request(&mut r, &mut w);
    // 完整的 JSON 字符串可以解码；错放在 intent 外的字段只移动层级，不改值。
    reply(
        &mut r,
        &mut w,
        &q,
        "run_actions",
        json!({"actions": json!([
            {"intent":{"locale":"loc_a"},"verb":"前往"},
            {"intent":r#"{"verb":"阅读公告"}"#,"prop_id":"board"}
        ]).to_string()}),
    );
    w.step(5.0);
    let actor = w.actor("r1").unwrap();
    assert_eq!(actor.locus.locale, "loc_a");
    let group = actor
        .actions
        .groups
        .values()
        .find(|g| g.actions.len() == 2)
        .unwrap();
    assert_eq!(group.status, protocol::GroupStatus::Succeeded);
    assert_eq!(group.results.len(), 2);
    assert_eq!(group.results[1].verb, "阅读公告");
    assert_eq!(group.results[1].status, protocol::ActionStatus::Succeeded);
}

#[test]
fn action_compatibility_rejects_ambiguous_or_invalid_commands_without_world_changes() {
    use agent::tools::ToolErrorKind::{InvalidArguments, World};
    let mut w = world();
    let r = runtime(&mut w, Limits::default());
    let mut s = r.session("r1").unwrap().clone();
    let before = serde_json::to_value(w.snapshot()).unwrap();
    // 只覆盖兼容入口的安全边界：重复、未知字段、破损 JSON，以及内核语义校验。
    for (arguments, expected) in [
        (
            json!({"intent":{"verb":"前往","locale":"loc_b"},"verb":"停留"}),
            InvalidArguments,
        ),
        (
            json!({"intent":r#"{"verb":"前往","locale":"loc_b","x":5}"#}),
            InvalidArguments,
        ),
        (
            json!({"actions":r#"[{"intent":{"verb":"前往","locale":"loc_b"}}"#}),
            InvalidArguments,
        ),
        (
            json!({"intent":r#"{"verb":"前往","locale":"loc_b","locale":"loc_a"}"#}),
            InvalidArguments,
        ),
        (
            json!({"intent":r#"{"verb":"前往","locale":"invented_locale"}"#}),
            World,
        ),
        (
            json!({"intent":r#"{"verb":"编造能力","locale":"loc_b"}"#}),
            World,
        ),
    ] {
        let error = call(&mut w, &mut s, "run_actions", arguments).unwrap_err();
        assert_eq!(error.kind, expected);
        if expected == InvalidArguments {
            assert!(error.message.contains(r#"{"actions":[{"intent":{"verb""#));
        }
        assert_eq!(before, serde_json::to_value(w.snapshot()).unwrap());
    }
}

#[test]
fn structured_local_turns_move_use_props_and_reject_partial_or_ambiguous_replies() {
    use agent::completion::{local_tool_request_body, parse_local_tool_reply};
    let decision = |body: &serde_json::Value| {
        let last = body["messages"].as_array().unwrap().last().unwrap();
        serde_json::from_str::<serde_json::Value>(last["content"].as_str().unwrap()).unwrap()
            ["decision_state"]
            .clone()
    };
    let response = |content: String, finish: &str| {
        json!({"choices":[{"finish_reason":finish,"message":{"role":"assistant","content":content}}],
            "usage":{"prompt_tokens":100,"completion_tokens":25}})
    };
    let move_call = json!({"name":"move_to","arguments":{"locale":"loc_b"}});
    // 整条回复先校验再提交：未知调用、多余参数、截断与多次调用都不能漏执行身体动作。
    for (envelope, finish) in [
        (json!({"thought":"我这就出发。","calls":[]}), "stop"),
        (
            json!({"thought":"","calls":[{"name":"unknown_tool","arguments":{}}]}),
            "stop",
        ),
        (
            json!({"thought":"","calls":[{"name":"move_to","arguments":{"locale":"loc_b","target":"none"}}]}),
            "stop",
        ),
        (json!({"thought":"","calls":[move_call.clone()]}), "length"),
        (
            json!({"thought":"","calls":[move_call.clone(),{"name":"observe","arguments":{}}]}),
            "stop",
        ),
    ] {
        let mut w = world();
        let mut r = runtime(&mut w, Limits::default());
        let q = request(&mut r, &mut w);
        let before = serde_json::to_value(w.snapshot()).unwrap();
        let rejected = parse_local_tool_reply(&response(envelope.to_string(), finish), &q);
        assert!(rejected.is_err());
        assert!(r.on_reply(&mut w, &q.actor_id, q.stamp.id, q.stamp.epoch, rejected, 1));
        assert_eq!(serde_json::to_value(w.snapshot()).unwrap(), before);
    }

    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    let q = request(&mut r, &mut w);
    let original = serde_json::to_value(&q).unwrap();
    let body = local_tool_request_body(&q, "qwen3.5:2b");
    assert_eq!(serde_json::to_value(&q).unwrap(), original);
    assert!(body.get("tools").is_none());
    assert_eq!(body["response_format"]["type"], "json_schema");
    assert_eq!(
        body["response_format"]["json_schema"]["schema"]["properties"]["calls"]["maxItems"],
        1
    );
    assert_eq!(
        body["response_format"]["json_schema"]["schema"]["properties"]["calls"]["minItems"],
        1
    );
    let branches = body["response_format"]["json_schema"]["schema"]["properties"]["calls"]["items"]
        ["anyOf"]
        .as_array()
        .unwrap();
    let names: Vec<_> = branches
        .iter()
        .map(|branch| branch["properties"]["name"]["const"].as_str().unwrap())
        .collect();
    assert!(names.contains(&"move_to") && names.contains(&"use_prop"));
    assert!(!names.contains(&"run_actions"));
    let destinations = &branches
        .iter()
        .find(|branch| branch["properties"]["name"]["const"] == "move_to")
        .unwrap()["properties"]["arguments"]["properties"]["locale"]["enum"];
    assert_eq!(destinations, &json!(["loc_a", "loc_b"]));
    for tool in &q.tools {
        let name = tool["function"]["name"].as_str().unwrap();
        let local_name = if name == "run_actions" {
            "advanced_actions"
        } else {
            name
        };
        let branch = branches
            .iter()
            .find(|branch| branch["properties"]["name"]["const"] == local_name)
            .unwrap();
        if name == "interact" {
            let mut operations: Vec<_> = branch["properties"]["arguments"]["anyOf"]
                .as_array()
                .unwrap()
                .iter()
                .map(|operation| {
                    operation["properties"]["operation"]["const"]
                        .as_str()
                        .unwrap()
                })
                .collect();
            let mut original_operations: Vec<_> = tool["function"]["parameters"]["properties"]
                ["operation"]["enum"]
                .as_array()
                .unwrap()
                .iter()
                .map(|operation| operation.as_str().unwrap())
                .collect();
            operations.sort_unstable();
            original_operations.sort_unstable();
            assert_eq!(operations, original_operations);
        } else {
            assert_eq!(
                branch["properties"]["arguments"],
                tool["function"]["parameters"]
            );
        }
    }
    // 记目标只登记意图，下一次请求仍须看到真实地点和条件，再由模型选择移动。
    let planned = parse_local_tool_reply(
        &response(json!({"thought":"去工作台做点东西。","calls":[{"name":"set_goal","arguments":{
            "id":"work","title":"制作器物","condition":{"kind":"action","verb":"制作器物","locale":"loc_b"},"status":"active"
        }}]}).to_string(), "stop"), &q,
    ).unwrap();
    assert!(r.on_reply(
        &mut w,
        &q.actor_id,
        q.stamp.id,
        q.stamp.epoch,
        Ok(planned),
        1
    ));
    let q = request(&mut r, &mut w);
    let planned_state = decision(&local_tool_request_body(&q, "qwen3.5:2b"));
    assert_eq!(planned_state["locale"], "loc_a");
    assert_eq!(planned_state["goals"][0]["condition"]["locale"], "loc_b");
    assert_eq!(planned_state["goals"][0]["status"], "active");
    // 世界已拒绝的“完成目标”只能作为失败资料，不能继续作为助手的可照抄范例。
    let premature = parse_local_tool_reply(
        &response(
            json!({"thought":"我已经做好了。","calls":[{"name":"set_goal","arguments":{
                "id":"work","title":"制作器物","status":"completed"
            }}]})
            .to_string(),
            "stop",
        ),
        &q,
    )
    .unwrap();
    let premature_call = premature.calls[0].clone();
    assert!(r.on_reply(
        &mut w,
        &q.actor_id,
        q.stamp.id,
        q.stamp.epoch,
        Ok(premature),
        1
    ));
    let q = request(&mut r, &mut w);
    let original = serde_json::to_value(&q).unwrap();
    let corrected_context = local_tool_request_body(&q, "qwen3.5:2b");
    assert_eq!(serde_json::to_value(&q).unwrap(), original);
    let historical: Vec<_> = corrected_context["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|message| {
            (
                message["role"].as_str().unwrap(),
                serde_json::from_str::<serde_json::Value>(message["content"].as_str().unwrap())
                    .unwrap_or_default(),
            )
        })
        .collect();
    assert!(historical.iter().any(|(role, content)| *role == "user"
        && content["historical_failed_attempt"] == json!(premature_call)));
    assert!(historical.iter().any(|(role, content)| *role == "user"
        && content["tool_result"]["call_id"] == premature_call.id
        && content["tool_result"]["result"]["ok"] == false));
    assert!(
        !historical.iter().any(|(role, content)| *role == "assistant"
            && content["calls"]
                .as_array()
                .is_some_and(|calls| calls.iter().any(|call| call["id"] == premature_call.id)))
    );
    assert_eq!(decision(&corrected_context)["goals"][0]["status"], "active");
    let moved = parse_local_tool_reply(
        &response(
            json!({"thought":"这就去工作台。","calls":[move_call]}).to_string(),
            "stop",
        ),
        &q,
    )
    .unwrap();
    let move_id = moved.calls[0].id.clone();
    assert_eq!(moved.calls[0].name, "run_actions");
    assert_eq!(moved.usage.unwrap().total(), 125);
    assert!(r.on_reply(&mut w, &q.actor_id, q.stamp.id, q.stamp.epoch, Ok(moved), 1));
    w.step(3.0);
    assert_eq!(w.actor("r1").unwrap().locus.locale, "loc_b");

    let q = request(&mut r, &mut w);
    let original = serde_json::to_value(&q).unwrap();
    let follow_up = local_tool_request_body(&q, "qwen3.5:2b");
    assert_eq!(serde_json::to_value(&q).unwrap(), original);
    let current = decision(&follow_up);
    assert_eq!(current["locale"], "loc_b");
    assert_eq!(current["visible_props"][0]["id"], "bench");
    assert!(current["known_map"]["known_places"]
        .as_array()
        .unwrap()
        .iter()
        .any(|place| place["id"] == "loc_b"));
    // 成功动作回执比最后观察新时，不能把出发前位置再标成当前；真实回执必须保留。
    let mut before_observation = q.clone();
    assert_eq!(
        before_observation.messages.pop().unwrap().role,
        agent::conversation::Role::User
    );
    let before_observation = decision(&local_tool_request_body(&before_observation, "qwen3.5:2b"));
    assert!(before_observation.get("locale").is_none());
    assert_eq!(
        before_observation["latest_tool_result"]["name"],
        "run_actions"
    );
    assert!(
        follow_up["response_format"]["json_schema"]["schema"]["properties"]["calls"]["items"]
            ["anyOf"]
            .as_array()
            .unwrap()
            .iter()
            .any(|branch| branch["properties"]["name"]["const"] == "use_prop"
                && branch["properties"]["arguments"]["anyOf"].is_array())
    );
    // observe 之后的完整新观察会省略未变的道具，旧查询不能让此后每轮失去道具枚举。
    let observed = parse_local_tool_reply(
        &response(
            json!({"thought":"","calls":[{"name":"observe","arguments":{}}]}).to_string(),
            "stop",
        ),
        &q,
    )
    .unwrap();
    assert!(r.on_reply(
        &mut w,
        &q.actor_id,
        q.stamp.id,
        q.stamp.epoch,
        Ok(observed),
        1
    ));
    let q = request(&mut r, &mut w);
    let last_user: serde_json::Value =
        serde_json::from_str(&q.messages.last().unwrap().content).unwrap();
    assert!(last_user["observation"].get("visible_props").is_none());
    let follow_up = local_tool_request_body(&q, "qwen3.5:2b");
    let calls = &follow_up["response_format"]["json_schema"]["schema"]["properties"]["calls"]
        ["items"]["anyOf"];
    let use_prop = calls
        .as_array()
        .unwrap()
        .iter()
        .find(|branch| branch["properties"]["name"]["const"] == "use_prop")
        .unwrap();
    assert_eq!(
        use_prop["properties"]["arguments"]["anyOf"][0]["properties"]["prop_id"]["const"],
        "bench"
    );
    // 空背包、完整空道具表与“列表不完整”不同：前者不提供可编造任意ID的简单别名。
    let mut empty = q.clone();
    let mut empty_observation: serde_json::Value =
        serde_json::from_str(&empty.messages.last().unwrap().content).unwrap();
    empty_observation["observation"]["visible_props"] = json!([]);
    empty_observation["observation"]["inventory"] = json!({"used":0,"slots":[]});
    empty.messages.last_mut().unwrap().content = empty_observation.to_string();
    let empty_wire = local_tool_request_body(&empty, "qwen3.5:2b");
    let empty_calls = empty_wire["response_format"]["json_schema"]["schema"]["properties"]["calls"]
        ["items"]["anyOf"]
        .as_array()
        .unwrap();
    assert!(!empty_calls
        .iter()
        .any(|branch| branch["properties"]["name"]["const"] == "use_prop"));
    assert!(empty_calls
        .iter()
        .any(|branch| branch["properties"]["name"]["const"] == "advanced_actions"));
    assert!(parse_local_tool_reply(&response(json!({"thought":"","calls":[{"name":"use_prop","arguments":{"prop_id":"imagined","verb":"吃饭"}}]}).to_string(), "stop"), &empty).is_err());
    let mut incomplete = empty.clone();
    empty_observation["observation"]["visible_props_source"] =
        json!({"context_source":"props","truncated":true});
    incomplete.messages.last_mut().unwrap().content = empty_observation.to_string();
    let incomplete_wire = local_tool_request_body(&incomplete, "qwen3.5:2b");
    assert!(
        incomplete_wire["response_format"]["json_schema"]["schema"]["properties"]["calls"]["items"]
            ["anyOf"]
            .as_array()
            .unwrap()
            .iter()
            .any(|branch| branch["properties"]["name"]["const"] == "use_prop")
    );
    // 只有地图完整时才枚举地点；原始请求和空心声也不会因此改写。
    let mut partial = q.clone();
    let system = partial
        .messages
        .iter_mut()
        .find(|message| message.role == agent::conversation::Role::System)
        .unwrap();
    let (prefix, map) = system.content.rsplit_once("\n\n已知地图：\n").unwrap();
    let mut map: serde_json::Value = serde_json::from_str(map).unwrap();
    map["known_places_source"] = json!({"context_source":"map","truncated":true});
    system.content = format!("{prefix}\n\n已知地图：\n{map}");
    partial.messages.push(agent::conversation::Message::text(
        agent::conversation::Role::Assistant,
        "我已走到别处。",
    ));
    let original = serde_json::to_value(&partial).unwrap();
    let partial_wire = local_tool_request_body(&partial, "qwen3.5:2b");
    assert_eq!(serde_json::to_value(&partial).unwrap(), original);
    let partial_move = partial_wire["response_format"]["json_schema"]["schema"]["properties"]
        ["calls"]["items"]["anyOf"]
        .as_array()
        .unwrap()
        .iter()
        .find(|branch| branch["properties"]["name"]["const"] == "move_to")
        .unwrap();
    assert!(
        partial_move["properties"]["arguments"]["properties"]["locale"]
            .get("enum")
            .is_none()
    );
    assert!(partial_wire["messages"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|message| message["role"] == "assistant")
        .all(|message| serde_json::from_str::<serde_json::Value>(
            message["content"].as_str().unwrap()
        )
        .unwrap()["calls"]
            .as_array()
            .is_some_and(|calls| !calls.is_empty())));
    // 随身道具可能来自别处，不能把眼前工作台列表误当作全部可用道具。
    let mut carrying = q.clone();
    let latest_observation = carrying
        .messages
        .iter_mut()
        .rev()
        .find(|message| message.role == agent::conversation::Role::User)
        .unwrap();
    let mut content: serde_json::Value = serde_json::from_str(&latest_observation.content).unwrap();
    assert_eq!(content["observation"]["locale"], "loc_b");
    content["observation"]["inventory"] = json!({"used":1,"slots":[{"items":["carried-water"]}]});
    content["observation"]["visible_props"] = json!([{"id":"bench","verbs":[{"verb":"制作器物"}]}]);
    latest_observation.content = content.to_string();
    let carrying_wire = local_tool_request_body(&carrying, "qwen3.5:2b");
    let carried_use = carrying_wire["response_format"]["json_schema"]["schema"]["properties"]
        ["calls"]["items"]["anyOf"]
        .as_array()
        .unwrap()
        .iter()
        .find(|branch| branch["properties"]["name"]["const"] == "use_prop")
        .unwrap();
    assert_eq!(
        carried_use["properties"]["arguments"]["properties"]["prop_id"],
        json!({"type":"string"})
    );
    assert_eq!(local_tool_request_body(&q, "qwen3.5:2b"), follow_up);
    // JSON 传输历史仍保留工具调用和结果的配对编号。
    let messages = follow_up["messages"].as_array().unwrap();
    assert!(messages.iter().any(|message| {
        message["role"] == "assistant"
            && serde_json::from_str::<serde_json::Value>(message["content"].as_str().unwrap())
                .is_ok_and(|value| {
                    value["thought"] == ""
                        && value["calls"][0]["id"] == move_id
                        && value["calls"][0]["name"] == "move_to"
                        && value["calls"][0]["arguments"] == json!({"locale":"loc_b"})
                })
    }));
    assert!(q
        .messages
        .iter()
        .any(|message| message.content == "这就去工作台。"));
    assert!(messages.iter().any(|message| {
        message["role"] == "user"
            && serde_json::from_str::<serde_json::Value>(message["content"].as_str().unwrap())
                .is_ok_and(|value| value["tool_result"]["call_id"] == move_id)
    }));
    // 历史中曾写错的参数也须完整保留，不能为了展示基础别名而偷偷修正旧调用。
    let mut malformed_history = q.clone();
    let historic_call = malformed_history
        .messages
        .iter_mut()
        .flat_map(|message| message.calls.iter_mut())
        .find(|call| call.id == move_id)
        .unwrap();
    historic_call.arguments["unexpected"] = json!("保留这项旧错误");
    let historic_arguments = historic_call.arguments.clone();
    let malformed_wire = local_tool_request_body(&malformed_history, "qwen3.5:2b");
    assert!(malformed_wire["messages"]
        .as_array()
        .unwrap()
        .iter()
        .any(|message| {
            message["role"] == "assistant"
                && serde_json::from_str::<serde_json::Value>(message["content"].as_str().unwrap())
                    .is_ok_and(|value| {
                        value["calls"][0]["id"] == move_id
                            && value["calls"][0]["name"] == "advanced_actions"
                            && value["calls"][0]["arguments"] == historic_arguments
                    })
        }));
    let advanced = parse_local_tool_reply(
        &response(
            json!({"thought":"","calls":[{"name":"advanced_actions","arguments":historic_arguments}]}).to_string(),
            "stop",
        ),
        &q,
    )
    .unwrap();
    assert_eq!(advanced.calls[0].name, "run_actions");
    assert_eq!(advanced.calls[0].arguments, historic_arguments);
    let used = parse_local_tool_reply(
        &response(
            json!({"thought":"","calls":[{"name":"use_prop","arguments":{"prop_id":"bench","verb":"制作器物"}}]}).to_string(),
            "stop",
        ),
        &q,
    )
    .unwrap();
    let use_id = used.calls[0].id.clone();
    assert!(r.on_reply(&mut w, &q.actor_id, q.stamp.id, q.stamp.epoch, Ok(used), 1));
    w.step(3.0);
    assert!(w.actor("r1").unwrap().actions.groups.values().any(|group| {
        group.status == protocol::GroupStatus::Succeeded
            && group.results.iter().any(|result| {
                result.verb == "制作器物" && result.status == protocol::ActionStatus::Succeeded
            })
    }));
    let after_use = life_request(&mut r, &mut w);
    let history = local_tool_request_body(&after_use, "qwen3.5:2b");
    assert!(history["messages"]
        .as_array()
        .unwrap()
        .iter()
        .any(|message| {
            message["role"] == "assistant"
                && serde_json::from_str::<serde_json::Value>(message["content"].as_str().unwrap())
                    .is_ok_and(|value| {
                        value["calls"][0]["id"] == use_id
                            && value["calls"][0]["name"] == "use_prop"
                            && value["calls"][0]["arguments"]
                                == json!({"prop_id":"bench","verb":"制作器物"})
                    })
        }));
}

/// 等的人迟迟不来：只填事件的等待一小时内也会醒来重看，不空等到饥渴才被叫醒（海难环岛里周屿
/// 等林晚带木头回来，一等就是一天的上限）；等自己的动作结果是等不到的，当场退回并指出该等什么。
#[test]
fn an_event_only_wait_wakes_within_the_hour_and_unreachable_events_are_refused() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    let q = life_request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "wait_for",
        json!({"event":"action","reason":"等别人捡完木头腾出木堆"}),
    );
    let q = life_request(&mut r, &mut w);
    let said = |q: &agent::runtime::AgentRequest, text: &str| {
        q.messages.iter().any(|m| m.content.contains(text))
    };
    assert!(said(&q, "等别人到来用 presence"), "等不到的事件当场退回");
    reply(
        &mut r,
        &mut w,
        &q,
        "wait_for",
        json!({"event":"presence","reason":"等何青带木头回来"}),
    );
    w.step(59.0);
    assert!(
        r.poll(&mut w, true).is_empty(),
        "等的人没来，一小时之内照常等"
    );
    w.step(2.0);
    let woke = life_request(&mut r, &mut w);
    assert!(said(&woke, r#""woke_by":"deadline""#), "到点醒来重看");
}
