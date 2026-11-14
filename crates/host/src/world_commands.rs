//! 启动门槛、运行世界设定与模式切换。所有客户端共用此处校验。
use crate::runtime::{Outcome, Runtime};
use host::{
    world_settings::{instructions_chars, WorldSettings, INSTRUCTIONS_MAX_CHARS},
    HostError,
};
use protocol::{
    AgentState, GameModeChoice, Life, PhysiologySwitches, ServerMsg, WorldSettingsView,
};

impl Runtime {
    /// 保存世界观是事务：所有居民改用新指令并存盘，任一步失败都回到修改前；无论成败都回发当前设定与 roster。
    pub(crate) fn save_worldview(
        &mut self,
        request_id: String,
        expected_revision: u64,
        text: &str,
    ) -> Outcome {
        let result = self
            .check_worldview(expected_revision, text)
            .map_err(|e| e.to_string())
            .and_then(|next| {
                self.transact(|rt| rt.apply_worldview(next))
                    .map_err(|aborted| aborted.to_string())
            });
        Outcome::none()
            .and_all(self.world_settings_msg())
            .and_reply(ServerMsg::WorldSettingsSaved {
                request_id,
                ok: result.is_ok(),
                message: result.err().unwrap_or_else(|| {
                    "世界观已保存，世界保持暂停；点「开始」让村民自主生活".into()
                }),
            })
            .and_all(self.roster())
    }

    /// 保存世界级生理开关：和世界观共用修订号与回执；成功才存盘。
    pub(crate) fn save_physiology(
        &mut self,
        request_id: String,
        expected_revision: u64,
        switches: PhysiologySwitches,
    ) -> Outcome {
        let result = self.set_physiology(expected_revision, switches);
        let persist = result.is_ok();
        let outcome = Outcome::none()
            .and_all(self.world_settings_msg())
            .and_reply(ServerMsg::WorldSettingsSaved {
                request_id,
                ok: result.is_ok(),
                message: result
                    .err()
                    .unwrap_or_else(|| "生理设置已保存并应用，世界已暂停；点「开始」继续".into()),
            })
            .and_all(self.roster());
        if persist {
            outcome.persisted()
        } else {
            outcome
        }
    }

    /// 打开或关掉化身神力：只是一个开关，不暂停世界、不打断谁，也不占世界设定的修订号
    /// （正在别的页面改的世界观不会因此被拒）。存盘失败时撤回。回执后广播世界设定。
    pub(crate) fn save_miracles(&mut self, request_id: String, enabled: bool) -> Outcome {
        let result = self
            .transact(|rt| {
                rt.world.set_miracles(enabled);
                Ok::<_, HostError>(())
            })
            .map_err(|aborted| aborted.to_string());
        Outcome::none()
            .and_all(self.world_settings_msg())
            .and_reply(ServerMsg::WorldSettingsSaved {
                request_id,
                ok: result.is_ok(),
                message: result.err().unwrap_or_else(|| {
                    if enabled {
                        "化身神力已打开：化身能对够得着的人复活、治愈、补满".into()
                    } else {
                        "化身神力已关闭".into()
                    }
                }),
            })
    }

    /// 改气候：和神力开关一样不暂停世界、不占修订号；存盘失败时撤回。回执后广播世界设定。
    pub(crate) fn save_climate(
        &mut self,
        request_id: String,
        climate: protocol::Climate,
    ) -> Outcome {
        let result = self
            .transact(|rt| rt.world.set_climate(climate).map_err(HostError::from))
            .map_err(|aborted| aborted.to_string());
        Outcome::none()
            .and_all(self.world_settings_msg())
            .and_reply(ServerMsg::WorldSettingsSaved {
                request_id,
                ok: result.is_ok(),
                message: result.err().unwrap_or_else(|| match climate {
                    protocol::Climate::Temperate => "气候改成了温带：天气照常".into(),
                    protocol::Climate::Tropical => {
                        "气候改成了热带：不再下雪，雷暴少一半，淋雨湿得慢一半".into()
                    }
                }),
            })
    }

    /// 打开或关掉玩法（不带 choice 是关掉）。没给种子时随机取一个：潮水圈从下一个天亮起公布第一圈，
    /// 狼人杀按此刻镇上的村民发身份，执剑人之夜按此刻镇上的村民排座次、定身份。不暂停世界：玩法的公告到点会自己写进每个人的经历。
    pub(crate) fn save_game_mode(
        &mut self,
        request_id: String,
        choice: Option<GameModeChoice>,
    ) -> Outcome {
        let roll = |seed: Option<u32>| Some(seed.unwrap_or_else(|| rand::random::<u32>().max(1)));
        let choice = choice.map(|c| match c {
            GameModeChoice::Tide { seed } => GameModeChoice::Tide { seed: roll(seed) },
            GameModeChoice::Werewolf { seed, day_hours } => GameModeChoice::Werewolf {
                seed: roll(seed),
                day_hours,
            },
            GameModeChoice::Swordholder { seed, day_hours } => GameModeChoice::Swordholder {
                seed: roll(seed),
                day_hours,
            },
            GameModeChoice::Frostlight {
                seed,
                duration_hours,
            } => GameModeChoice::Frostlight {
                seed: roll(seed),
                duration_hours,
            },
        });
        let result = self
            .transact(|rt| {
                rt.world.set_game_mode(choice.as_ref())?;
                Ok::<_, HostError>(())
            })
            .map_err(|aborted| aborted.to_string());
        Outcome::none()
            .and_all(self.world_settings_msg())
            .and_reply(ServerMsg::WorldSettingsSaved {
                request_id,
                ok: result.is_ok(),
                message: result.err().unwrap_or_else(|| match choice {
                    Some(GameModeChoice::Tide { .. }) => {
                        "潮水圈已打开：下一个天亮公布第 1 圈，之后两天每天两圈，最后一圈公布时来船"
                            .into()
                    }
                    Some(GameModeChoice::Werewolf { .. }) => {
                        "狼人杀已打开：身份已发下，天亮开局；每天 16:30 敲钟、17:00 议事".into()
                    }
                    Some(GameModeChoice::Swordholder { .. }) => {
                        "执剑人之夜已打开：天亮开局，16:30 敲钟、17:00 演说和投票，19:00 交接"
                            .into()
                    }
                    Some(GameModeChoice::Frostlight { .. }) => {
                        "霜灯镇已开局：安排燃料与粮食，维持热源，带着居民熬过风暴".into()
                    }
                    None => "玩法已关掉，世界恢复原样".into(),
                }),
            })
    }

    /// 玩法管理与普通世界操作使用同一存盘事务；失败不会留下已扣物资或已生效的法令。
    pub(crate) fn control_game_mode(
        &mut self,
        request_id: String,
        command: &protocol::GameModeAction,
    ) -> Outcome {
        let result = self
            .transact(|rt| rt.world.game_mode_control(command).map_err(HostError::from))
            .map_err(|aborted| aborted.to_string());
        let ok = result.is_ok();
        let message = result.unwrap_or_else(|error| error);
        Outcome::reply(ServerMsg::WorldSettingsSaved {
            request_id,
            ok,
            message,
        })
        .and_all(self.roster())
    }

    /// 打开或关掉陌生环境：世界暂停，居民的旧安排作废、重新观察（已知地图变了）。
    pub(crate) fn save_strangers(&mut self, request_id: String, enabled: bool) -> Outcome {
        let result = self
            .transact(|rt| {
                if rt.world.strangers() != enabled {
                    rt.speed = 0.0;
                    rt.world.set_strangers(enabled);
                    for r in rt.population.residents.values() {
                        rt.driver.runtime.world_changed(
                            &mut rt.world,
                            &r.id,
                            "世界设定已修改，请重新观察和安排",
                        );
                    }
                }
                Ok::<_, HostError>(())
            })
            .map_err(|aborted| aborted.to_string());
        Outcome::none()
            .and_all(self.world_settings_msg())
            .and_reply(ServerMsg::WorldSettingsSaved {
                request_id,
                ok: result.is_ok(),
                message: result.err().unwrap_or_else(|| {
                    if enabled {
                        "村民现在初来乍到：只知道眼下所在的地方和家，别处要走过去才知道".into()
                    } else {
                        "村民现在熟悉这里：知道每个地方在哪、能做什么".into()
                    }
                }),
            })
    }

    /// 开关变化后世界暂停，所有居民的旧安排作废、重新观察；数值不动。
    fn set_physiology(
        &mut self,
        revision: u64,
        switches: PhysiologySwitches,
    ) -> Result<(), String> {
        if revision != self.world_settings.revision {
            return Err("世界设定已被其他页面修改，请重新读取后再保存".into());
        }
        if self.world.physiology() == switches {
            return Ok(());
        }
        self.speed = 0.0;
        self.world.set_physiology(switches);
        for r in self.population.residents.values() {
            self.driver.runtime.world_changed(
                &mut self.world,
                &r.id,
                "世界设定已修改，请重新观察和安排",
            );
        }
        self.world_settings.revision += 1;
        Ok(())
    }

    /// 修改前的检查：修订号、非空、长度，以及每位居民的人设加世界观不超上限。返回修改后的设定。
    fn check_worldview(&self, revision: u64, text: &str) -> Result<WorldSettings, HostError> {
        if revision != self.world_settings.revision {
            return Err(HostError::Rejected(
                "世界设定已被其他页面修改，请重新读取后再保存".into(),
            ));
        }
        let text = text.trim();
        if text.is_empty() {
            return Err(HostError::Rejected("请填写世界观后再保存".into()));
        }
        let mut next = self.world_settings.clone();
        next.worldview = text.into();
        next.validate()?;
        for r in self.population.residents.values() {
            if instructions_chars(&r.persona, text) > INSTRUCTIONS_MAX_CHARS {
                return Err(HostError::Rejected(format!(
                    "{} 的人设与世界观合计超过 {INSTRUCTIONS_MAX_CHARS} 字，请缩短后保存",
                    r.name
                )));
            }
        }
        next.revision += 1;
        Ok(next)
    }

    /// 事务里的改动：世界停下，每位居民作废当前动作版本（迟到模型回复不能执行）并改用新指令。
    fn apply_worldview(&mut self, next: WorldSettings) -> Result<(), HostError> {
        self.speed = 0.0;
        for r in self.population.residents.values() {
            self.driver.runtime.world_changed(
                &mut self.world,
                &r.id,
                "世界观已修改，请重新观察和安排",
            );
            self.driver
                .set_persona(&mut self.world, &r.id, &r.persona, &next.worldview)?;
        }
        self.world_settings = next;
        Ok(())
    }

    pub(crate) fn world_settings_msg(&self) -> ServerMsg {
        let state = WorldSettingsView {
            climate: self.world.climate(),
            game_mode: self.world.game_mode().map(str::to_owned),
            max_chars: host::world_settings::MAX_WORLDVIEW_CHARS,
            miracles: self.world.miracles(),
            strangers: self.world.strangers(),
            mock: self.driver.mock,
            model: self.driver.target.model.clone(),
            persistent: self.store.is_some(),
            physiology: self.world.physiology(),
            provider: self.driver.target.provider.clone(),
            ready: self.world_settings.ready(),
            recording: self.world_settings.recording,
            revision: self.world_settings.revision,
            world_id: self.population.world_id.clone(),
            worldview: self.world_settings.worldview.clone(),
        };
        ServerMsg::WorldSettings { state }
    }

    /// 名册：内核投影加上 Agent 状态与外观；世界没开始运行时，空等的人写明还没决定下一步
    /// （只说这个人，世界暂停由页面的暂停提示和顶栏说明）。
    pub(crate) fn roster(&self) -> ServerMsg {
        let mut msg = self.driver.roster(&self.world, self.speed);
        if let ServerMsg::Roster { pace, holds, .. } = &mut msg {
            // 和选定速度一样按正常速度的倍数发：页面只关心快了几倍
            *pace = self.pace / self.base_pace();
            *holds = self.town_holds();
        }
        let waiting =
            |id: &str| -> bool { self.world.actor(id).is_some_and(|a| a.waiting_for_plan()) };
        let reason = (!self.world_settings.ready()).then_some("等待设置世界观");
        if let (Some(reason), ServerMsg::Roster { locales, .. }) = (reason, &mut msg) {
            for member in locales.iter_mut().flat_map(|l| &mut l.members) {
                if member
                    .body
                    .as_ref()
                    .is_some_and(|b| b.life == Life::Dead || !b.can_decide)
                {
                    continue;
                }
                if let Some(agent) = &mut member.resident_agent {
                    agent.state = AgentState::Unconfigured;
                    agent.reason = reason.into();
                }
                if waiting(&member.id) {
                    member.plan.current = reason.into();
                }
            }
        }
        if let ServerMsg::Roster { locales, .. } = &mut msg {
            for member in locales.iter_mut().flat_map(|locale| &mut locale.members) {
                if let Some(resident) = self.population.residents.get(&member.id) {
                    member.appearance = Some(resident.appearance.clone());
                }
            }
        }
        if self.world_settings.ready() && self.speed == 0.0 {
            if let ServerMsg::Roster { locales, .. } = &mut msg {
                for member in locales.iter_mut().flat_map(|l| &mut l.members) {
                    if waiting(&member.id)
                        && member
                            .resident_agent
                            .as_ref()
                            .is_some_and(|a| a.state == AgentState::Undecided)
                    {
                        member.plan.current = "还没决定下一步".into();
                    }
                }
            }
        }
        msg
    }
}
