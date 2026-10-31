//! 每种线上消息一份样本，供几何边界检查和前端类型比对使用。
//! 另补完整化身和道具状态，不展开可选字段与参数矩阵。
use protocol::*;
use serde_json::json;

pub fn tuning() -> NeedsTuning {
    NeedsTuning {
        fullness_decay: 0.05,
        energy_decay: 0.025,
        labor_rate: 0.04,
        voiced: 60.0,
        ring: 35.0,
        ring_reset: 45.0,
        collapse: 15.0,
    }
}

fn thought() -> ThoughtView {
    ThoughtView {
        sim_minutes: 430.0,
        trigger_info: TriggerInfo::text("队列见底"),
        text: "眼皮直打架。可这批活明早要交。".into(),
        line: "眼皮直打架。".into(),
        clock: "D1 07:10".into(),
    }
}

fn action_result() -> ActionResult {
    ActionResult {
        action_id: "a1".into(),
        group_id: "g1".into(),
        prop_id: Some("bench".into()),
        verb: "工作".into(),
        started_at: Some(420.0),
        ended_at: 450.0,
        status: ActionStatus::Succeeded,
        changes: vec!["完成打磨".into()],
        reason: None,
        event_ids: vec![3],
    }
}

fn agent_view() -> ResidentAgentView {
    ResidentAgentView {
        state: AgentState::Thinking,
        reason: "正在等待模型响应".into(),
        goals: vec![ResidentGoalView {
            id: "read".into(),
            title: "去图书馆读书".into(),
            status: GoalStatus::Active,
            reason: "想学木工".into(),
            commitment: "吃过饭后去".into(),
            next_steps: vec!["先吃饭".into()],
            updated_at: 431.0,
        }],
        results: vec![
            ActionResultView {
                result: action_result(),
                verb_kind: VerbKind::Prop,
            },
            ActionResultView {
                result: ActionResult {
                    prop_id: None,
                    started_at: None,
                    status: ActionStatus::Failed,
                    reason: Some("门锁着".into()),
                    ..action_result()
                },
                verb_kind: VerbKind::Inventory,
            },
        ],
        interactions: vec![ResidentInteractionView {
            id: "i1".into(),
            title: "交谈".into(),
            status: InteractionStatus::Running,
            participants: vec!["阿树".into(), "小禾".into()],
            result: "正在聊".into(),
        }],
        memories: vec![ResidentMemoryView {
            memory_id: 7,
            kind: MemoryKind::Episode,
            source: EvidenceSource::Observed,
            status: MemoryStatus::Active,
            confidence: 0.9,
            text: "图书馆今天开放".into(),
            at: 425.0,
            replaces: vec![],
            events: vec![WorldFact {
                event_id: 3,
                at: 425.0,
                kind: FactKind::Readable,
                text: "读了公告".into(),
                objects: vec!["indoor_library".into()],
                action_id: Some("a1".into()),
                readable: Some(ReadableFact {
                    id: "b1".into(),
                    version: "v1".into(),
                    previously_read: false,
                    previous_version: None,
                }),
            }],
        }],
        daily_calls: 3,
        daily_limit: 120,
        daily_tokens: 12_000,
        daily_input_tokens: 10_000,
        daily_cache_hit_tokens: 4_000,
        replies: 3,
        stale_replies: 1,
    }
}

fn body() -> BodyView {
    BodyView {
        revision: 3,
        life: Life::Alive,
        conditions: vec![BodyCondition {
            kind: BodyConditionKind::Injury,
            severity: 1.0,
            since: 400.0,
            source: "摔了一跤".into(),
        }],
        can_decide: true,
        can_move: true,
        can_labor: false,
        limitation: "身体低值，不能劳作".into(),
        causes: vec!["受伤".into()],
        exposure: [0.0, 0.0, 0.0],
        history: vec![BodyEvent {
            at: 400.0,
            kind: BodyEventKind::Condition,
            source: "摔了一跤".into(),
            text: "出现受伤".into(),
        }],
        wound: None,
    }
}

/// 遇害的死者：名册上带伤口。
fn killed_body() -> BodyView {
    BodyView {
        life: Life::Dead,
        conditions: vec![],
        can_decide: false,
        can_move: false,
        can_labor: false,
        limitation: "已死亡".into(),
        causes: vec![],
        wound: Some("胸口一处刀伤".into()),
        ..body()
    }
}

fn member(id: &str, at: At, activity: ActivityKind) -> RosterMember {
    RosterMember {
        appearance: None,
        inventory: InventoryView {
            capacity: 4,
            slots: vec![],
            used: 1,
        },
        chat: Some(ChatPresence {
            id: "chat1".into(),
            participants: vec!["阿树".into()],
            turn: None,
        }),
        speech: Some(SpeechView {
            chat_id: "chat1".into(),
            seq: 1,
            at: 430.0,
            text: "早".into(),
            line: "早".into(),
        }),
        movement: Some(MovementView {
            route: "edge_a__b".into(),
            navigation_revision: 2,
            destination_station: "place_arrival_cafe".into(),
            phase: MovementPhase::Travel,
        }),
        id: id.into(),
        name: "阿树".into(),
        kind: MemberKind::Resident,
        at,
        verb: "前往".into(),
        verb_kind: VerbKind::Goto,
        activity,
        needs: vec![NeedState {
            kind: Need::Energy,
            need: "精力".into(),
            value: 88.0,
            band: NeedBand::Steady,
            text: String::new(),
        }],
        body: Some(body()),
        plan: PlanView {
            current: "前往 花房咖啡馆".into(),
            upcoming: vec!["工作（30 分钟）".into()],
        },
        thought: Some(thought()),
        resident_agent: Some(agent_view()),
    }
}

fn appearance() -> Appearance {
    Appearance {
        marker: "树".into(),
        color: "green".into(),
        profile: Some("rigged-oldzhou".into()),
        look: Some(VillagerLook {
            hair: HairStyle::Ponytail,
            outfit: Outfit::Apron,
            hair_color: "#5a3626".into(),
            hair_tip: Some("#4aa86a".into()),
            eye_color: "#4c77da".into(),
            skin: "#f6ece0".into(),
            top: "#f4f6f4".into(),
            bottom: "#4a4a50".into(),
            accent: "#e44a4e".into(),
            collar: Some("#ece4d2".into()),
            apron: Some("#58b078".into()),
            belt: Some("#8a6a44".into()),
            ornament: Some("#e8c070".into()),
            headband: Some("#e44a4e".into()),
            hat: true,
            ahoge: true,
            clip: true,
            beard: true,
            headwear: None,
            face: Some(FaceGear::Glasses),
            beard_style: None,
            held: Some(HeldItem::Fan),
            pattern: Some(LookPattern {
                on: PatternTarget::Top,
                color: "#2e2e36".into(),
                rows: vec!["####".into(), "....".into(), "####".into(), "....".into()],
            }),
        }),
    }
}

fn template() -> ResidentTemplate {
    ResidentTemplate {
        template_id: "builtin_ashu".into(),
        version: 1,
        builtin: true,
        archived: false,
        fields: TemplateFields {
            name: "阿树".into(),
            age: "28".into(),
            gender: "男".into(),
            intro: "木工".into(),
            tags: vec!["手艺".into()],
            personality: "沉稳".into(),
            speech: "话少".into(),
            background: "在镇上长大".into(),
            situation: String::new(),
            drives: "把手艺做好".into(),
            interests: "读书".into(),
            occupation: "木工".into(),
            appearance: appearance(),
        },
    }
}

fn limits() -> AgentLimits {
    AgentLimits {
        calls_per_wake: 6,
        calls_per_day: 120,
        tokens_per_day: 300_000,
        total_calls: 10_000,
        total_tokens: 30_000_000,
        stale_replies_before_pause: 2,
        model_failures_before_pause: 3,
    }
}

fn usage_row() -> ResidentUsage {
    ResidentUsage {
        id: "resident_ashu".into(),
        name: "阿树".into(),
        daily_calls: 3,
        daily_tokens: 12_000,
        daily_input_tokens: 10_000,
        daily_cache_hit_tokens: 4_000,
        replies: 3,
        stale_replies: 1,
        in_flight: true,
        paused: Some("额度用尽：今天的调用已用完".into()),
    }
}

fn notebook_entry() -> NotebookEntry {
    NotebookEntry {
        key: "page:places/library.md".into(),
        version: "1:1:abc".into(),
        category: NotebookCategory::Places,
        title: "图书馆".into(),
        text: "白天开放".into(),
        text_chars: 4,
        at: 430.0,
        day: Some(1),
        note_status: Some(NoteStatus::Candidate),
        goal_status: Some(GoalStatus::Paused),
        source_count: 1,
        history_count: 0,
        pending: false,
        next_steps: vec![],
        reason: String::new(),
        related: vec![NotebookLink {
            key: "goal:read".into(),
            title: "去图书馆读书".into(),
            category: NotebookCategory::Goals,
        }],
    }
}

fn home() -> HomeView {
    HomeView {
        locale: "home_01".into(),
        name: "一号住宅".into(),
        occupant: Some("阿树".into()),
    }
}

fn join_outcome() -> JoinOutcome {
    JoinOutcome {
        op_id: "op1".into(),
        ok: true,
        message: "已加入".into(),
        resident_id: Some("resident_xiaohe".into()),
        name: Some("小禾".into()),
        home: Some("home_01".into()),
        joined_at: Some(430.0),
        revision: 2,
    }
}

fn weather_view() -> WeatherView {
    WeatherView {
        world_id: "world-1".into(),
        revision: 2,
        kind: WeatherKind::Rain,
        mode: WeatherMode::Fixed,
        changed_at: 480.,
        last_transition: Some(WeatherTransition {
            id: 1,
            at: 480.,
            from: WeatherKind::Clear,
            to: WeatherKind::Rain,
            source: WeatherSource::Manual,
        }),
    }
}

fn capabilities() -> PropCapabilities {
    let choice = |id: &str, label: &str| Choice {
        id: id.into(),
        label: label.into(),
    };
    PropCapabilities {
        completion_effects: vec![choice("restore", "恢复")],
        completions: vec![choice("activity", "普通活动")],
        conditions: vec![choice("meal_window", "供餐时段")],
        duration: DurationRange { max: 60, min: 1 },
        effects: vec![choice("labor", "劳作")],
        max_actions: 8,
        needs: vec![choice("energy", "精力")],
        rate: RateRange { max: 5, min: 0.1 },
        schema_version: 1,
        supports_recipients: true,
        supports_supply: true,
    }
}

fn population(revision: u64) -> PopulationView {
    PopulationView {
        world_id: "w1".into(),
        revision,
        residents: vec![ResidentRegistration {
            id: "resident_ashu".into(),
            name: "阿树".into(),
            home: Some("home_01".into()),
            home_name: "一号住宅".into(),
            joined_at: Some(420.0),
            joined_clock: Some("D1 07:00".into()),
            template_id: Some("builtin_ashu".into()),
            template_version: Some(1),
            appearance: appearance(),
            model: Some(ModelChoice {
                provider: "deepseek".into(),
                model: "deepseek-chat".into(),
            }),
        }],
        homes: vec![home()],
        entry_name: Some("南入口".into()),
    }
}

pub fn server_samples() -> Vec<ServerMsg> {
    vec![
        ServerMsg::WeatherSaved {
            request_id: "weather-1".into(),
            world_id: "world-1".into(),
            ok: false,
            code: Some(WeatherCode::RevisionConflict),
            message: "请重新读取".into(),
            environment: Some(weather_view()),
        },
        ServerMsg::WorldIdentity {
            town_id: Some("default-town".into()),
            map_hash: "abc".into(),
        },
        ServerMsg::AvatarState {
            state: AvatarSession {
                view: AvatarSight::Own(AvatarView::Unsupported { supported: false }),
                world_id: "w1".into(),
                speed: 1.0,
                controlled: true,
                occupied: true,
                recent: None,
                goals: None,
                lease: Some(AvatarLease {
                    epoch: "e1".into(),
                    resume_token: "t1".into(),
                    sequence: 3,
                }),
                client_positions: true,
                walk: Some(AvatarWalk {
                    metres_per_minute: 12.0,
                    sprint_factor: 2.4,
                }),
                position: Some(PositionAck {
                    position_error: None,
                    position_sequence: 3,
                }),
            },
        },
        ServerMsg::AvatarResult {
            request_id: "a1".into(),
            ok: true,
            code: AvatarResultCode::Ok,
            message: String::new(),
            state: AvatarSession {
                view: AvatarSight::Occupied {
                    actor: (),
                    supported: true,
                },
                world_id: "w1".into(),
                speed: 1.0,
                controlled: false,
                occupied: true,
                recent: None,
                goals: None,
                lease: None,
                client_positions: false,
                walk: None,
                position: None,
            },
        },
        ServerMsg::ChatHistory {
            resident: "resident_ashu".into(),
            request_id: "r1".into(),
            chat_id: Some("chat1".into()),
            offset: 0,
            total: 1,
            chats: vec![ChatSummary {
                id: "chat1".into(),
                locale: "indoor_cafe".into(),
                participants: vec!["阿树".into(), "小禾".into()],
                status: InteractionStatus::Running,
                created_at: 430.0,
                ended_at: None,
                entries: 1,
            }],
            entries: vec![ChatEntry {
                seq: 1,
                at: 430.0,
                actor: "resident_ashu".into(),
                name: "阿树".into(),
                kind: ChatEntryKind::Speech,
                text: "早".into(),
                audience: ["resident_xiaohe".to_string()].into(),
            }],
        },
        ServerMsg::WorldSettings {
            state: WorldSettingsView {
                max_chars: 6000,
                mock: false,
                model: "m".into(),
                persistent: true,
                physiology: PhysiologySwitches::default(),
                provider: "p".into(),
                ready: true,
                revision: 1,
                world_id: "w1".into(),
                worldview: "小镇".into(),
            },
        },
        ServerMsg::WorldSettingsSaved {
            request_id: "r2".into(),
            ok: true,
            message: "已保存".into(),
        },
        ServerMsg::Props {
            catalog: PropsCatalog {
                capabilities: capabilities(),
                definition_actions: Default::default(),
                definitions: vec![],
                instances: vec![],
                locations: vec![PlaceRef {
                    id: "indoor_cafe".into(),
                    name: "咖啡馆".into(),
                    residential: false,
                }],
                persistent: true,
                schema_version: 1,
                spatial: None,
                world_id: "w1".into(),
            },
        },
        ServerMsg::PropResult {
            request_id: "r3".into(),
            ok: false,
            message: "无效".into(),
            preview: None,
        },
        ServerMsg::Roster {
            environment: None,
            sim_minutes: 432.5,
            clock: "D1 07:12".into(),
            speed: 1.0,
            pace: 12.5,
            period: "上午".into(),
            holds: vec![WorldHold {
                resident_id: "resident_ashu".into(),
                resident: "阿树".into(),
                kind: PauseKind::Fault,
                reason: "模型连续 3 次请求失败：鉴权失败（检查密钥）".into(),
                cause: HoldCause::Auth,
                provider: "DeepSeek".into(),
            }],
            locales: vec![RosterLocale {
                locale: "edge_a__b".into(),
                members: vec![
                    member(
                        "resident_ashu",
                        At::Transit {
                            elapsed: 1.25,
                            total: 3.5,
                            toward: "outdoor_plaza_01".into(),
                        },
                        ActivityKind::Advancing,
                    ),
                    member(
                        "resident_b",
                        At::Station {
                            station: "place_arrival_cafe".into(),
                        },
                        ActivityKind::Placeholder,
                    ),
                    member("resident_c", At::Offstage, ActivityKind::Placeholder),
                    RosterMember {
                        body: Some(killed_body()),
                        ..member(
                            "resident_d",
                            At::Station {
                                station: "place_arrival_cafe".into(),
                            },
                            ActivityKind::Placeholder,
                        )
                    },
                ],
            }],
        },
        ServerMsg::Event {
            sim_minutes: 432.5,
            clock: "D1 07:12".into(),
            text: "阿树 到达 广场".into(),
            info: EventInfo::movement("resident_ashu", "阿树"),
        },
        ServerMsg::ModelConfig {
            active: Some(ActiveModelChoice {
                provider: "p1".into(),
                model: "m1".into(),
            }),
            providers: vec![ProviderView {
                id: "p1".into(),
                name: "服务商".into(),
                base_url: "https://example.invalid/v1".into(),
                key_mask: "sk-a…7890".into(),
            }],
            builtin_stale: true,
        },
        ServerMsg::ConfigSaved {
            request_id: "req-1".into(),
            ok: true,
            message: "已保存".into(),
        },
        ServerMsg::ModelTestResult {
            request_id: "req-1".into(),
            provider: "p1".into(),
            ok: true,
            message: "收到".into(),
            latency_ms: 120,
        },
        ServerMsg::AgentConfig {
            resident_id: "resident_ashu".into(),
            resident: "阿树".into(),
            persona: "# 阿树\n姓名：阿树".into(),
            tuning: tuning(),
            health_marks: [10.0, 30.0, 70.0],
            model_binding: Some(ModelChoice {
                provider: "p1".into(),
                model: "m2".into(),
            }),
        },
        ServerMsg::AgentSaved {
            request_id: "req-1".into(),
            ok: true,
            message: "已设当前值".into(),
        },
        ServerMsg::Error {
            request_id: Some("op1".into()),
            message: "世界里没有这个人".into(),
        },
        ServerMsg::WorldReset {
            clock: "D1 07:00".into(),
        },
        ServerMsg::Diary {
            resident: "阿树".into(),
            days: vec![DiaryDay {
                label: "D1".into(),
                receipts: vec![
                    ReceiptView {
                        sim_minutes: 440.0,
                        clock: "D1 07:20".into(),
                        text: "到达 工作坊".into(),
                        alert: None,
                    },
                    ReceiptView {
                        sim_minutes: 450.0,
                        clock: "D1 07:30".into(),
                        text: "健康耗尽，死亡。原因：持续饥饿".into(),
                        alert: Some(Alert::Death(DeathCause {
                            shortages: vec![Need::Fullness],
                            conditions: vec![BodyConditionKind::Poison],
                            killed: None,
                        })),
                    },
                    ReceiptView {
                        sim_minutes: 460.0,
                        clock: "D1 07:40".into(),
                        text: "遇害身亡，胸口一处刀伤。原因：阿明使用菜刀／持刀袭击".into(),
                        alert: Some(Alert::Death(DeathCause {
                            shortages: vec![],
                            conditions: vec![],
                            killed: Some(Killing {
                                by: EventActor {
                                    id: "resident_aming".into(),
                                    name: "阿明".into(),
                                },
                                wound: "胸口一处刀伤".into(),
                            }),
                        })),
                    },
                ],
                thoughts: vec![thought()],
                summary: Some("干了一天。".into()),
                current: false,
            }],
        },
        ServerMsg::Notebook {
            resident: "resident_ashu".into(),
            request_id: "r4".into(),
            notebook: Some(Box::new(NotebookView {
                sim_minutes: 432.5,
                last_reflection_at: Some(420.0),
                reflecting: false,
                retry_after: Some(450.0),
                pending_events: 2,
                counts: vec![NotebookCount {
                    category: NotebookCategory::Places,
                    count: 1,
                }],
                offset: 0,
                total: 1,
                next_offset: Some(1),
                entries: vec![notebook_entry()],
                recent_updates: vec![],
            })),
            error: None,
        },
        ServerMsg::NotebookDetail {
            resident: "resident_ashu".into(),
            request_id: "r5".into(),
            detail: Some(Box::new(NotebookDetail {
                key: "page:places/library.md".into(),
                version: "1:1:abc".into(),
                section: NotebookSection::Sources,
                offset: 0,
                total: 1,
                next_offset: None,
                text: String::new(),
                entries: vec![notebook_entry()],
            })),
            error: None,
        },
        ServerMsg::AgentLimits {
            limits: limits(),
            ranges: AgentLimitRanges {
                calls_per_wake: LimitRange {
                    min: 1,
                    max: Some(6),
                },
                calls_per_day: LimitRange { min: 1, max: None },
                tokens_per_day: LimitRange {
                    min: 34_048,
                    max: None,
                },
                total_calls: LimitRange { min: 1, max: None },
                total_tokens: LimitRange { min: 1, max: None },
                stale_replies_before_pause: LimitRange {
                    min: 1,
                    max: Some(20),
                },
                model_failures_before_pause: LimitRange {
                    min: 1,
                    max: Some(20),
                },
            },
            usage: AgentUsage {
                lifetime_calls: 30,
                lifetime_tokens: 120_000,
                residents: vec![usage_row()],
            },
        },
        ServerMsg::Population {
            population: population(2),
        },
        ServerMsg::ResidentAppearanceSaved {
            request_id: "look-1".into(),
            resident_id: "resident_ashu".into(),
            ok: true,
            message: "外观已保存".into(),
            population: PopulationView {
                world_id: "w1".into(),
                revision: 3,
                residents: vec![],
                homes: vec![],
                entry_name: None,
            },
        },
        ServerMsg::Usage {
            summary: UsageSummary {
                today_calls: 3,
                today_tokens: 12_000,
                today_input_tokens: 10_000,
                today_cache_hit_tokens: 4_000,
                lifetime_calls: 30,
                lifetime_tokens: 120_000,
                lifetime_input_tokens: 100_000,
                lifetime_cache_hit_tokens: 40_000,
                calls_per_day: 120,
                tokens_per_day: 300_000,
                total_calls: 10_000,
                total_tokens: 30_000_000,
                in_flight: 1,
            },
            residents: vec![usage_row()],
            requests: vec![RequestView {
                id: 9,
                resident_id: "resident_ashu".into(),
                resident: "阿树".into(),
                kind: RequestKind::Life,
                clock: "D1 07:12".into(),
                sim_minutes: 432.5,
                sent_at: 1_700_000_000,
                reserved_tokens: 4_000,
                estimated_tokens: 3_500,
                status: RequestStatus::Adopted,
                detail: "run_actions".into(),
                latency_ms: Some(1_200),
                input_tokens: Some(3_400),
                output_tokens: Some(200),
                cache_hit_tokens: Some(1_000),
            }],
        },
        ServerMsg::ResidentLibrary {
            templates: vec![TemplateCard {
                template_id: "builtin_ashu".into(),
                version: 1,
                builtin: true,
                archived: false,
                name: "阿树".into(),
                intro: "木工".into(),
                tags: vec!["手艺".into()],
                appearance: appearance(),
                status: TemplateStatus::Joined,
                resident_id: Some("resident_ashu".into()),
            }],
            custom_root: "~/MyAiTown/resident-library".into(),
        },
        ServerMsg::ResidentTemplate {
            template: Some(template()),
            persona: "# 阿树".into(),
            error: None,
        },
        ServerMsg::TemplatePersona {
            persona: "# 阿树".into(),
            error: Some("姓名不能为空".into()),
        },
        ServerMsg::TemplateGenerated {
            request_id: "r6".into(),
            ok: true,
            message: "已生成".into(),
            fields: Some(Box::new(template().fields)),
        },
        ServerMsg::TemplateSaved {
            request_id: "req-1".into(),
            ok: true,
            message: "已保存".into(),
            template: Some(template()),
        },
        ServerMsg::JoinPreview {
            preview: JoinPreview {
                ok: true,
                problems: vec![],
                template_id: "builtin_xiaohe".into(),
                template_version: 1,
                name: "小禾".into(),
                home: Some("home_02".into()),
                home_name: Some("二号住宅".into()),
                entry_name: "南入口".into(),
                clock: "D1 07:12".into(),
                persona_chars: 800,
                free_homes: vec![home()],
            },
        },
        ServerMsg::ResidentJoined {
            outcome: join_outcome(),
        },
        ServerMsg::JoinResult {
            op_id: "op1".into(),
            outcome: Some(join_outcome()),
        },
    ]
}

fn prop_action() -> PropActionView {
    PropActionView {
        conditions: vec!["供餐时段".into()],
        consumes_item: false,
        effects: vec!["饱腹每分钟恢复 1 点".into()],
        id: "eat".into(),
        label: "吃饭".into(),
        minutes: 30.0,
        portion_name: Some("一碗饭".into()),
        recipient: false,
        remaining: None,
        result: "吃饱了".into(),
        supply: Some(SupplyView {
            cost: 1,
            initial: 20,
        }),
    }
}

fn content_origin() -> ContentOrigin {
    ContentOrigin::Resident {
        actor: "resident_ashu".into(),
    }
}

fn content_text() -> ContentText {
    ContentText {
        author: "阿树".into(),
        kind: ContentKind::Book,
        origin: content_origin(),
        text: "正文".into(),
        title: "木工手记".into(),
        version: 1,
        work_id: "book1".into(),
    }
}

fn content_metadata() -> ContentMetadata {
    ContentMetadata {
        author: "佚名".into(),
        fingerprint: "abc".into(),
        kind: ContentKind::Bulletin,
        origin: ContentOrigin::Builtin,
        title: "公告".into(),
        version: 2,
        work_id: "board1".into(),
    }
}

fn locus(at: At) -> Locus {
    Locus {
        locale: "indoor_cafe".into(),
        at,
    }
}

fn free(elevation: Option<f64>, yaw: Option<f64>) -> At {
    At::Free {
        space: "town_outdoor".into(),
        position: [1.0, 2.0],
        elevation,
        yaw,
    }
}

fn chat_entry(kind: ChatEntryKind) -> ChatEntry {
    ChatEntry {
        seq: 2,
        at: 431.0,
        actor: "resident_ashu".into(),
        name: "阿树".into(),
        kind,
        text: "来了".into(),
        audience: ["player".to_string()].into(),
    }
}

/// 有控制目标时的完整化身视图：聊天与双方互动各一项。
fn avatar_state() -> AvatarState {
    AvatarState {
        actor: AvatarActor {
            activity: "停留".into(),
            appearance: appearance(),
            body: Some(body()),
            busy: false,
            id: "player".into(),
            inventory: InventoryView {
                capacity: 4,
                slots: vec![InventorySlot {
                    actions: vec![prop_action()],
                    definition: Some("core:bread@1".into()),
                    items: vec!["bread_1".into()],
                    name: "面包".into(),
                    quantity: 1,
                    readable: Some(content_metadata()),
                }],
                used: 1,
            },
            locus: locus(free(Some(0.5), Some(1.2))),
            name: "我".into(),
            needs: vec![NeedState {
                kind: Need::Fullness,
                need: "饱腹".into(),
                value: 40.0,
                band: NeedBand::Mild,
                text: "有些饿".into(),
            }],
            present: true,
            remaining: "还剩 3 分钟".into(),
            revision: 4,
        },
        awaiting_arrival: false,
        can_drop: true,
        feedback: vec!["拾取 面包；共 1 件".into()],
        interactions: vec![
            AvatarInteraction::Chat(AvatarChatItem {
                can_request_turn: true,
                can_speak: false,
                entries: vec![
                    chat_entry(ChatEntryKind::Speech),
                    chat_entry(ChatEntryKind::Joined),
                    chat_entry(ChatEntryKind::Left),
                    chat_entry(ChatEntryKind::Ended),
                ],
                expires_at: 440.0,
                id: "chat1".into(),
                initiator: "player".into(),
                kind: InteractionKind::Talk,
                locale: "indoor_cafe".into(),
                members: ["player".to_string(), "resident_ashu".to_string()].into(),
                message: "聊聊？".into(),
                partner: "resident_ashu".into(),
                reason: None,
                reply: Some("好".into()),
                status: InteractionStatus::Running,
                turn: Some("resident_ashu".into()),
                response_error: Some("模型返回的回应格式有误，正在尝试修正。".into()),
            }),
            AvatarInteraction::Pair(AvatarPairItem {
                accepted: None,
                can_request_turn: false,
                can_speak: false,
                changes: vec![],
                created_at: 430.0,
                duration_minutes: 5.0,
                ended_at: None,
                event_ids: [("player".to_string(), vec![1])].into(),
                expires_at: 440.0,
                id: "give1".into(),
                initiator: "player".into(),
                kind: InteractionKind::Give {
                    items: vec!["bread_1".into()],
                },
                locale: "indoor_cafe".into(),
                message: "送你".into(),
                partner: "resident_ashu".into(),
                reason: None,
                reply: None,
                started_at: None,
                status: InteractionStatus::Offered,
                response_error: None,
            }),
            AvatarInteraction::Pair(AvatarPairItem {
                accepted: Some(true),
                can_request_turn: false,
                can_speak: false,
                changes: vec!["吃了一碗饭".into()],
                created_at: 430.0,
                duration_minutes: 30.0,
                ended_at: Some(470.0),
                event_ids: Default::default(),
                expires_at: 440.0,
                id: "serve1".into(),
                initiator: "resident_ashu".into(),
                kind: InteractionKind::Serve {
                    prop_id: "table".into(),
                    verb: "吃饭".into(),
                },
                locale: "indoor_cafe".into(),
                message: "请你吃饭".into(),
                partner: "player".into(),
                reason: Some("吃完了".into()),
                reply: Some("谢谢".into()),
                started_at: Some(440.0),
                status: InteractionStatus::Succeeded,
                response_error: None,
            }),
        ],
        mode: AvatarMode::Possession,
        navigation_revision: 2,
        nearby: vec![NearbyPerson {
            activity: "工作".into(),
            available: false,
            can_talk: true,
            id: "resident_ashu".into(),
            name: "阿树".into(),
        }],
        nearby_chats: vec![NearbyChat {
            id: "chat2".into(),
            locale: "indoor_cafe".into(),
            members: ["resident_b".to_string()].into(),
        }],
        portals: vec![PortalView {
            id: "door1".into(),
            label: "咖啡馆门口".into(),
        }],
        props: vec![AvatarPropView {
            actions: vec![prop_action()],
            bulletin_board: false,
            carried: false,
            contents: vec![StoredItem {
                definition: None,
                id: "cup_1".into(),
                name: "杯子".into(),
            }],
            id: "cupboard".into(),
            name: "碗柜".into(),
            portable: false,
            storage_slots: 8,
        }],
        reading: Some(content_text()),
        supported: true,
        units: 10.0,
    }
}

fn avatar_session(view: AvatarSight) -> AvatarSession {
    AvatarSession {
        view,
        world_id: "w1".into(),
        speed: 1.0,
        controlled: true,
        occupied: true,
        recent: Some(vec![RecentEvent {
            at: 430.0,
            text: "到达 咖啡馆".into(),
        }]),
        goals: Some(vec![AvatarGoal {
            status: GoalStatus::Completed,
            text: "去图书馆读书".into(),
        }]),
        lease: None,
        client_positions: false,
        walk: None,
        position: None,
    }
}

/// 道具定义原文（内核 props::Definition 的 JSON）：一件道具带齐各种效果、补给与正文。
/// 内核测试（kernel/tests/props.rs）核对这份 JSON 读进内核类型再写出来不变。
fn definition() -> serde_json::Value {
    serde_json::from_str(include_str!("prop-definition.json")).unwrap()
}

fn prop_view(location: ItemLocation, actions: Vec<PropActionEntry>) -> PropView {
    PropView {
        actions,
        board: Some("board1".into()),
        bulletin_board: false,
        custom: true,
        definition: Some("core:bench@1".into()),
        id: "user:bench".into(),
        locale: "indoor_cafe".into(),
        location: Some(location),
        location_name: Some("咖啡馆".into()),
        name: "工作台".into(),
        occupants: vec!["resident_ashu".into()],
        on_map: true,
        portable: true,
        position: Some([1.0, 0.0, 2.0]),
        readable: Some(content_metadata()),
        stack_limit: 1,
        storage_slots: 0,
        walk_position: Some(locus(free(None, None))),
        withdrawn: false,
    }
}

/// 补充两份完整运行状态；不枚举所有可选字段和参数变体。
pub fn shape_samples() -> (Vec<ServerMsg>, Vec<ClientMsg>) {
    (
        vec![
            ServerMsg::AvatarState {
                state: avatar_session(AvatarSight::Own(AvatarView::Present(Box::new(
                    avatar_state(),
                )))),
            },
            ServerMsg::Props {
                catalog: PropsCatalog {
                    capabilities: capabilities(),
                    definition_actions: [("core:bench@1".to_string(), vec![prop_action()])].into(),
                    definitions: vec![definition()],
                    instances: vec![prop_view(
                        ItemLocation::Carried {
                            actor: "resident_ashu".into(),
                        },
                        vec![PropActionEntry::Defined(prop_action())],
                    )],
                    locations: vec![],
                    persistent: false,
                    schema_version: 1,
                    spatial: None,
                    world_id: "w1".into(),
                },
            },
        ],
        vec![
            avatar(AvatarCommand::Action {
                revision: 3,
                action: ActionDraft {
                    inventory: Some(InventoryAction::PickUp {
                        items: vec!["bread_1".into()],
                    }),
                    ..draft("拾取")
                },
            }),
            interact(InteractionCommand::Offer {
                partner_id: "resident_ashu".into(),
                interaction: InteractionKind::Talk,
                message: "一起聊聊？".into(),
            }),
        ],
    )
}

fn avatar(command: AvatarCommand) -> ClientMsg {
    ClientMsg::Avatar {
        world_id: "w1".into(),
        request_id: "a1".into(),
        epoch: "e1".into(),
        sequence: 2,
        command,
    }
}

fn draft(verb: &str) -> ActionDraft {
    ActionDraft {
        intent: IntentDraft {
            verb: verb.into(),
            locale: None,
            target: None,
            duration_minutes: None,
            until: None,
        },
        inventory: None,
        prop_id: None,
        recipient: None,
        writing: None,
    }
}

fn interact(command: InteractionCommand) -> ClientMsg {
    avatar(AvatarCommand::Interact {
        revision: 3,
        command,
    })
}

pub fn client_samples() -> Vec<ClientMsg> {
    let provider = ProviderConfigMsg {
        id: "p1".into(),
        name: "服务商".into(),
        base_url: "https://example.invalid/v1".into(),
    };
    vec![
        ClientMsg::Avatar {
            world_id: "w1".into(),
            request_id: "a1".into(),
            epoch: "e1".into(),
            sequence: 1,
            command: AvatarCommand::View,
        },
        ClientMsg::AvatarInput {
            world_id: "w1".into(),
            epoch: "e1".into(),
            sequence: 1,
            navigation_revision: 1,
            direction: [1., 0.],
            pose: Some(AvatarPose {
                actor: "resident_ashu".into(),
                locale: "road".into(),
                space: "town_outdoor".into(),
                position: [1., 2., 3.],
                yaw: 0.5,
            }),
        },
        ClientMsg::GetChatHistory {
            resident: "resident_ashu".into(),
            request_id: "r1".into(),
            chat_id: Some("chat1".into()),
            offset: 50,
        },
        ClientMsg::SetWeather {
            world_id: "world-1".into(),
            request_id: "weather-1".into(),
            expected_revision: 0,
            mode: WeatherMode::Fixed,
            kind: Some(WeatherKind::Rain),
        },
        ClientMsg::GetWorldSettings,
        ClientMsg::SetWorldview {
            request_id: "r2".into(),
            world_id: "w1".into(),
            expected_revision: 1,
            text: "小镇".into(),
        },
        ClientMsg::SetPhysiology {
            request_id: "r1".into(),
            world_id: "w1".into(),
            expected_revision: 2,
            switches: PhysiologySwitches {
                fullness: false,
                ..Default::default()
            },
        },
        ClientMsg::GetProps,
        ClientMsg::Content {
            request_id: "r3".into(),
            world_id: "w1".into(),
            command: ContentCommand::Create {
                id: "b2".into(),
                locale: "indoor_library".into(),
                title: "通知".into(),
                author: "管理员".into(),
                text: "今天开放".into(),
                board: Some("board".into()),
            },
        },
        ClientMsg::ValidateProp {
            request_id: "r4".into(),
            definition: definition(),
        },
        ClientMsg::SaveProp {
            request_id: "r5".into(),
            definition: definition(),
        },
        ClientMsg::RemoveProp {
            request_id: "r6".into(),
            world_id: "w1".into(),
            id: "bench".into(),
        },
        ClientMsg::PlaceProp {
            request_id: "r7".into(),
            world_id: "w1".into(),
            instance: json!({"id": "user:bench", "definition": "core:bench@1", "locale": "loc_a", "name": "工作台", "board": "board1"}),
            near: Some(PlaceNear {
                space: "town_outdoor".into(),
                position: [12.5, 8.],
            }),
        },
        ClientMsg::SetSpeed {
            request_id: "req-1".into(),
            speed: 20.0,
        },
        ClientMsg::GetModelConfig,
        ClientMsg::SetModelConfig {
            request_id: "req-1".into(),
            active: Some(ActiveModelChoice {
                provider: "p1".into(),
                model: "m1".into(),
            }),
            providers: vec![provider.clone()],
            keys: vec![ProviderKeyMsg {
                provider: "p1".into(),
                api_key: "sk-test".into(),
            }],
        },
        ClientMsg::SetResidentModel {
            request_id: "req-1".into(),
            resident: "resident_ashu".into(),
            model: ModelChoice {
                provider: "p1".into(),
                model: "m2".into(),
            },
        },
        ClientMsg::RestartBuiltinModel {
            request_id: "req-1".into(),
        },
        ClientMsg::TestModelConnection {
            request_id: "req-1".into(),
            provider,
            model: "m1".into(),
            api_key: None,
        },
        ClientMsg::GetAgentConfig {
            resident: Some("resident_ashu".into()),
        },
        ClientMsg::SetPersona {
            request_id: "req-1".into(),
            resident: "resident_ashu".into(),
            text: "# 阿树".into(),
        },
        ClientMsg::ResetWorld {
            request_id: "req-1".into(),
        },
        ClientMsg::GetPopulation,
        ClientMsg::SetResidentAppearance {
            request_id: "look-1".into(),
            world_id: "w1".into(),
            expected_revision: 2,
            resident_id: "resident_ashu".into(),
            appearance: appearance(),
        },
        ClientMsg::GetUsage,
        ClientMsg::GetResidentLibrary {
            filter: LibraryFilter {
                query: "木".into(),
                kind: LibraryKind::Builtin,
                include_archived: true,
            },
        },
        ClientMsg::GetResidentTemplate {
            template_id: "builtin_ashu".into(),
        },
        ClientMsg::SaveResidentTemplate {
            request_id: "req-1".into(),
            template_id: Some("custom_1".into()),
            expected_version: Some(2),
            fields: Box::new(template().fields),
        },
        ClientMsg::PreviewTemplatePersona {
            fields: Box::new(template().fields),
        },
        ClientMsg::GenerateResidentTemplate {
            request_id: "r8".into(),
            brief: "一个爱读书的渔民".into(),
        },
        ClientMsg::ArchiveResidentTemplate {
            request_id: "req-1".into(),
            template_id: "custom_1".into(),
            expected_version: 2,
            archived: true,
        },
        ClientMsg::PreviewResidentJoin {
            template_id: "builtin_xiaohe".into(),
            name: Some("小禾".into()),
            home: Some("home_02".into()),
        },
        ClientMsg::JoinResident {
            op_id: "op1".into(),
            world_id: "w1".into(),
            template_id: "builtin_xiaohe".into(),
            template_version: 1,
            name: "小禾".into(),
            home: Some("home_02".into()),
            model: Some(ModelChoice {
                provider: "deepseek".into(),
                model: "deepseek-chat".into(),
            }),
        },
        ClientMsg::GetResidentJoinResult {
            world_id: "w1".into(),
            op_id: "op1".into(),
        },
        ClientMsg::GetDiary {
            resident: Some("resident_ashu".into()),
        },
        ClientMsg::GetNotebook {
            resident: "resident_ashu".into(),
            request_id: "r9".into(),
            query: NotebookQuery {
                category: NotebookCategory::Places,
                search: "图书馆".into(),
                offset: 12,
                focus: Some("page:places/library.md".into()),
            },
        },
        ClientMsg::GetNotebookDetail {
            resident: "resident_ashu".into(),
            request_id: "r10".into(),
            query: NotebookDetailQuery {
                key: "page:places/library.md".into(),
                version: "1:1:abc".into(),
                section: NotebookSection::History,
                offset: 0,
            },
        },
        ClientMsg::GetAgentLimits,
        ClientMsg::SetAgentLimits {
            request_id: "req-1".into(),
            limits: limits(),
        },
    ]
}
