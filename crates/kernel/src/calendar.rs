//! 时段名、三餐时段、日期换算。全部按时间查表，没有随机源进内核。

use crate::topology::MealWindow;
use crate::{time_of_day, DAY};

#[derive(Clone, Copy)]
enum Period {
    Dawn,
    Morning,
    Noon,
    Afternoon,
    Evening,
    Night,
}

impl Period {
    fn at(minutes: f64) -> Self {
        let t = time_of_day(minutes);
        if t < 360.0 {
            Self::Dawn
        } else if t < 660.0 {
            Self::Morning
        } else if t < 810.0 {
            Self::Noon
        } else if t < 1050.0 {
            Self::Afternoon
        } else if t < 1200.0 {
            Self::Evening
        } else {
            Self::Night
        }
    }
    fn name(self) -> &'static str {
        match self {
            Self::Dawn => "凌晨",
            Self::Morning => "上午",
            Self::Noon => "晌午",
            Self::Afternoon => "下午",
            Self::Evening => "傍晚",
            Self::Night => "夜里",
        }
    }
}

pub fn period(minutes: f64) -> &'static str {
    Period::at(minutes).name()
}

/// 此刻在供餐时段内的那一餐；不在时段内为 None。表为空（测试拓扑）= 不限时。
pub fn meal_at(meals: &[MealWindow], minutes: f64) -> Option<&MealWindow> {
    let t = time_of_day(minutes);
    meals.iter().find(|m| t >= m.start && t < m.end)
}

pub fn day_index(minutes: f64) -> i64 {
    (minutes / DAY).floor() as i64
}

/// 读「D2 14:00」这样的时钟写法，返回世界分钟（D1 00:00 是 0）；写法不对为空。
pub fn parse_clock(text: &str) -> Option<f64> {
    let (day, time) = text.trim().strip_prefix('D')?.split_once(' ')?;
    let (hour, minute) = time.trim().split_once(':')?;
    let (day, hour, minute) = (
        day.parse::<u32>().ok()?,
        hour.parse::<u32>().ok()?,
        minute.parse::<u32>().ok()?,
    );
    (day > 0 && hour < 24 && minute < 60)
        .then(|| f64::from(day - 1) * crate::DAY + f64::from(hour * 60 + minute))
}
