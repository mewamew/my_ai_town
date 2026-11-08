//! 天气拥有独立随机流；时钟、身体和位置仍属于原有子系统。
mod exposure;
mod policy;
mod rules;
mod schedule;
use crate::error::Result;
use crate::World;
use protocol::{WeatherTransition, WeatherView};
pub use rules::WeatherRules;
pub use schedule::{WeatherRequest, WeatherSnapshot, WeatherState};

impl World {
    pub fn enable_weather(
        &mut self,
        rules: WeatherRules,
        seed: u32,
        world_id: String,
    ) -> Result<()> {
        self.weather = Some(WeatherState::new(rules, seed, self.minutes, world_id)?);
        Ok(())
    }
    pub fn bind_weather_world(&mut self, id: &str) {
        if let Some(w) = &mut self.weather {
            w.bind_world(id);
        }
    }
    pub fn weather(&self) -> Option<&WeatherState> {
        self.weather.as_ref()
    }
    /// 此刻的气候；地图没有天气时是温带。
    pub fn climate(&self) -> protocol::Climate {
        self.weather
            .as_ref()
            .map_or_else(Default::default, |w| w.climate)
    }
    /// 改气候：下一次换天气起按它抽，眼下的天气不变。地图没有天气时拒绝。
    pub fn set_climate(&mut self, climate: protocol::Climate) -> Result<()> {
        let w = self.weather.as_mut().ok_or_else(|| {
            crate::KernelError::weather(
                protocol::WeatherCode::WeatherUnavailable,
                "此地图未启用 2D 天气",
            )
        })?;
        w.climate = climate;
        Ok(())
    }
    pub fn set_weather(&mut self, request: WeatherRequest) -> Result<WeatherView> {
        let w = self.weather.as_ref().ok_or_else(|| {
            crate::KernelError::weather(
                protocol::WeatherCode::WeatherUnavailable,
                "此地图未启用 2D 天气",
            )
        })?;
        if let Some(view) = w.cached(&request)? {
            return Ok(view);
        }
        let event = self.weather.as_mut().unwrap().set(&request, self.minutes)?;
        if let Some(event) = event {
            self.record_weather(event);
        }
        self.check_weather_activities();
        Ok(self
            .weather
            .as_ref()
            .expect("上面已确认启用天气")
            .view
            .clone())
    }
    pub(crate) fn advance_weather(&mut self) {
        let event = self.weather.as_mut().and_then(|w| w.tick(self.minutes));
        if let Some(event) = event {
            self.record_weather(event);
        }
        self.check_weather_activities();
    }
    fn record_weather(&mut self, event: WeatherTransition) {
        let text = format!("天气变化：{} → {}", event.from.label(), event.to.label());
        let object = format!(
            "weather:{}:{}",
            self.weather.as_ref().unwrap().view.world_id,
            event.id
        );
        for actor in self
            .actors
            .values_mut()
            .filter(|a| !a.needs.body.dead && !matches!(a.locus.at, protocol::At::Offstage))
        {
            actor.journal.fact(
                event.at,
                protocol::FactKind::Observation,
                text.clone(),
                vec![object.clone()],
                None,
                None,
            );
        }
        self.log(protocol::EventInfo::default(), text);
    }
}
