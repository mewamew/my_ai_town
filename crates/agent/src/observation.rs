//! 只投影本人状态、眼前对象与已知地图。观察仪的世界全貌不进入村民上下文。
use crate::{interaction, prompts, resident, AgentError};
use kernel::{world::ActKind, World};
use serde_json::{json, Value};

/// 一次观察最多带的新事件数。
const EVENTS_PER_OBSERVATION: usize = 24;
/// 事件正文进入观察时的截断长度。
pub const EVENT_TEXT_CHARS: usize = 400;

/// 不随位置变化的部分：家、已知地图与基础动作。放在 system 消息里，请求前缀保持稳定。
pub fn static_map(world: &World, actor: &str) -> Result<Value, AgentError> {
    let a = resident(world, actor)?;
    let places: Vec<_> = world
        .topo
        .places
        .iter()
        .map(|p| {
            // 别人的住宅只列名字；本人的家和公共处所列那里能做的事。
            let others_home = p.residential && a.home.as_deref() != Some(p.locale.as_str());
            let verbs: Vec<&str> = if others_home {
                vec![]
            } else {
                world
                    .affordances
                    .options(&p.locale)
                    .iter()
                    .map(|s| s.verb.as_str())
                    .collect()
            };
            json!({"id":p.locale,"name":p.name,"verbs":verbs})
        })
        .collect();
    Ok(json!({
        "home": a.home,
        "known_places": places,
        "basic_actions": [
            {"verb":"前往","parameters":prompts::GO_PARAMETERS},
            {"verb":"停留","parameters":prompts::STAY_PARAMETERS}
        ]
    }))
}

fn prop_view(world: &World, actor: &str, p: &kernel::topology::Prop) -> Value {
    let verbs: Vec<_> = p
        .verbs
        .iter()
        .map(|v| {
            json!({
                "verb": v.verb,
                "action_id": v.action.as_ref().map(|a| &a.id),
                "minutes": v.duration_minutes,
                "description": v.action.as_ref().map(|a| kernel::props::action_description_for(a, world.physiology())),
                "remaining": v.action.as_ref().and_then(|a| world.props().supply_remaining(&p.id, a))
            })
        })
        .collect();
    let mut view = json!({
        "id": p.id,
        "name": p.name,
        "portable": p.portable,
        "storage_slots": p.storage_slots,
        "stored_items": world.container_items(actor, &p.id),
        "readable": p.readable.as_ref().map(kernel::content::Text::metadata),
        "board": p.board,
        "bulletin_board": p.bulletin_board,
        "verbs": verbs
    });
    with_description(&mut view, p);
    view
}

/// 道具定义写了说明才附带；遮蔽处另外标出。
fn with_description(view: &mut Value, p: &kernel::topology::Prop) {
    if !p.description.is_empty() {
        view["description"] = json!(p.description);
    }
    if p.shelter {
        view["shelter"] = json!(true);
    }
}

fn people_here(world: &World, actor: &str, locale: &str) -> Vec<Value> {
    world
        .actor_ids()
        .into_iter()
        .filter(|id| id != actor)
        .filter_map(|id| {
            let other = world.actor(&id)?;
            if other.locus.locale != locale {
                return None;
            }
            let mut body = json!({
                "life": if other.needs.body.dead { "dead" } else { "alive" },
                "conditions": other.needs.active_conditions().iter().map(|c| c.kind).collect::<Vec<_>>(),
                "limitation": other.needs.limitation()
            });
            // 遇害的尸体看得见伤口，看不见凶手。
            if let Some(k) = &other.needs.body.killed {
                body["wound"] = json!(k.wound);
            }
            Some(json!({
                "id": id,
                "name": other.name,
                "activity": other.current.verb,
                "available": world.actor(&id).is_some_and(|a| a.interaction_available()),
                "can_talk": world.talk_available(&id),
                "body": body
            }))
        })
        .collect()
}

/// 随时间和位置变化的部分：新事件、身体、眼前道具与人、互动。
pub fn observe(world: &World, actor: &str, after: u64) -> Result<(Value, u64), AgentError> {
    let a = resident(world, actor)?;
    let mut cursor = after;
    let events: Vec<_> = a
        .journal
        .events_after(after)
        .iter()
        .take(EVENTS_PER_OBSERVATION)
        .map(|event| {
            cursor = event.event_id;
            let mut event = event.clone();
            event.text = event.text.chars().take(EVENT_TEXT_CHARS).collect();
            event
        })
        .collect();
    let props: Vec<_> = world
        .topo
        .props()
        .iter()
        .filter(|p| p.locale == a.locus.locale && !p.withdrawn)
        .map(|p| prop_view(world, actor, p))
        .collect();
    let remaining = match &a.current.kind {
        ActKind::Travel { journey, .. } => format!(
            "去{}，{}",
            world.topo.locale_name(&journey.dest_locale),
            a.current.left_text()
        ),
        _ => a.current.left_text(),
    };
    let interactions: Vec<_> = world
        .interactions()
        .for_actor(actor)
        .iter()
        .map(|i| interaction::observation(world, actor, i))
        .collect();
    let value = json!({
        "actor_id": actor,
        "environment": world.weather_context(actor),
        "inventory": world.inventory_view(actor),
        "sim_minutes": world.minutes(),
        "clock": world.clock(),
        "revision": a.actions.revision,
        "locale": a.locus.locale,
        "location": world.topo.locale_name(&a.locus.locale),
        "needs": needs_for_model(a),
        "body": world.body_view(actor),
        "current": {
            "verb": a.current.verb,
            "description": a.current.content_label(),
            "remaining": remaining
        },
        "visible_props": props,
        "people_here": people_here(world, actor, &a.locus.locale),
        "events": events,
        "event_cursor": cursor,
        "more_events": cursor < a.journal.cursor(),
        "interactions": interactions,
        "nearby_chats": world.nearby_chats(actor),
    });
    Ok((value, cursor))
}

pub fn inspect(world: &World, actor: &str, id: &str) -> Result<Value, AgentError> {
    resident(world, actor)?;
    if let Some(item) = world.interactions().of(actor, id) {
        return Ok(json!({"interaction":interaction::observation(world,actor,item)}));
    }
    if let Some(prop) = world
        .topo
        .props()
        .iter()
        .find(|p| p.id == id && world.can_access_prop(actor, p))
    {
        let switches = world.physiology();
        let actions: Vec<_> = prop
            .verbs
            .iter()
            .filter_map(|v| {
                let spot = world.affordances.for_prop(&prop.id, &v.verb)?;
                let mut action = json!({
                    "verb": v.verb,
                    "action_id": v.action.as_ref().map(|a| &a.id),
                    "description": v.action.as_ref().map(|a| kernel::props::action_description_for(a, switches)),
                    "minimum_minutes": spot.minutes,
                    "remaining": v.action.as_ref().and_then(|a| world.props().supply_remaining(&prop.id, a)),
                    "labor": spot.labor
                });
                // 关掉的生理项不出现在村民能看到的数值里。
                for (on, key, rate) in [
                    (switches.fullness, "fullness_per_minute", spot.fullness_rate),
                    (switches.energy, "energy_per_minute", spot.energy_rate),
                    (switches.water, "water_per_minute", spot.water_rate),
                    (switches.health, "health_per_minute", spot.health_rate),
                ] {
                    if on {
                        action[key] = json!(rate);
                    }
                }
                Some(action)
            })
            .collect();
        let mut view = json!({
            "at": world.minutes(),
            "prop_id": prop.id,
            "portable": prop.portable,
            "stored_items": world.container_items(actor, &prop.id),
            "location": world.inventory().location(&prop.id),
            "locale": prop.locale,
            "readable": prop.readable.as_ref().map(kernel::content::Text::metadata),
            "board": prop.board,
            "actions": actions,
            "occupants": world.prop_occupants(&prop.id)
        });
        with_description(&mut view, prop);
        return Ok(view);
    }
    if let Some(place) = world.topo.places.iter().find(|p| p.locale == id) {
        return Ok(json!({"at":world.minutes(),"place_id":id,"name":place.name}));
    }
    Err(AgentError::NotFound(
        "对象不在眼前，也不属于已知地图".into(),
    ))
}

/// 给模型看的需求：名字、数值、档位与说明。需求种类只给前端判断用，不进观察，
/// 模型看到的内容与加这个字段之前相同。
fn needs_for_model(a: &kernel::world::Actor) -> Vec<Value> {
    a.needs
        .states()
        .into_iter()
        .map(|n| json!({"need": n.need, "value": n.value, "band": n.band, "text": n.text}))
        .collect()
}
