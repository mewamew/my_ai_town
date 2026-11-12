//! 新道具在二维图上的位置：跟在世界旁边保存，不写进不可变的地图。
use crate::error::ApiError;
use crate::storage::{read_json, write_json};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::path::Path;

const MAX_INSTANCES: usize = 4096;
const MAX_ID_LENGTH: usize = 150;
/// 房间内候选位置按 12×12 网格取。
const ROOM_GRID: usize = 12;

fn mark(id: &str, space: &str, x: f64, y: f64) -> Value {
    json!({ "id": id, "space": space, "x": x, "y": y })
}

pub fn positions(dir: &Path, document: &Value, instances: &Value) -> Result<Vec<Value>, ApiError> {
    let list = instances
        .as_array()
        .filter(|a| a.len() <= MAX_INSTANCES)
        .ok_or_else(|| ApiError::bad("道具列表超过限制"))?;
    let file = dir.join("prop-layout.json");
    let mut saved: Map<String, Value> = match read_json(&file) {
        Ok(Value::Object(map)) => map,
        Ok(_) => Map::new(),
        Err(e) if e.status == 404 => Map::new(),
        Err(e) => return Err(e),
    };
    let layout = &document["layout"];
    let empty = Vec::new();
    let fixed: HashMap<&str, Value> = layout["props"]
        .as_array()
        .unwrap_or(&empty)
        .iter()
        .filter_map(|p| {
            let id = p["id"].as_str()?;
            Some((
                id,
                json!({ "id": id, "space": p["space"], "x": p["x"], "y": p["y"] }),
            ))
        })
        .collect();
    let by_id = |key: &str| -> HashMap<&str, &Value> {
        layout[key]
            .as_array()
            .unwrap_or(&empty)
            .iter()
            .filter_map(|v| Some((v["id"].as_str()?, v)))
            .collect()
    };
    let (rooms, regions) = (by_id("spaces"), by_id("regions"));
    let mut changed = false;
    for p in list {
        let (Some(id), Some(locale)) = (p["id"].as_str(), p["locale"].as_str()) else {
            return Err(ApiError::bad("道具编号无效"));
        };
        if id.len() > MAX_ID_LENGTH {
            return Err(ApiError::bad("道具编号无效"));
        }
        if fixed.contains_key(id) || saved.contains_key(id) {
            continue;
        }
        let room = rooms.get(locale);
        let region = regions.get(locale);
        if room.is_none() && region.is_none() {
            return Err(ApiError::bad("道具所在地点不存在"));
        }
        let space = if room.is_some() {
            locale
        } else {
            "town_outdoor"
        };
        let occupied: Vec<(f64, f64)> = fixed
            .values()
            .chain(saved.values())
            .filter(|m| m["space"] == space)
            .filter_map(|m| Some((m["x"].as_f64()?, m["y"].as_f64()?)))
            .collect();
        let candidates: Vec<(f64, f64)> = if let Some(room) = room {
            let b = &room["bounds"];
            let n = |k: &str| b[k].as_f64().unwrap_or(0.0);
            let (x, y, w, h) = (n("x"), n("y"), n("width"), n("height"));
            let step = (ROOM_GRID + 1) as f64;
            (0..ROOM_GRID)
                .flat_map(|row| {
                    (0..ROOM_GRID).map(move |col| {
                        (
                            x + w * (col + 1) as f64 / step,
                            y + h * (row + 1) as f64 / step,
                        )
                    })
                })
                .collect()
        } else {
            let region = region.unwrap();
            let size = region["cell_size"].as_f64().unwrap_or(0.0);
            region["cells"]
                .as_array()
                .unwrap_or(&empty)
                .iter()
                .filter_map(|c| Some((c[0].as_f64()?, c[1].as_f64()?)))
                .map(|(x, y)| ((x + 0.5) * size, (y + 0.5) * size))
                .collect()
        };
        // 取离已有道具最远的候选位置。
        let mut best = None;
        let mut best_distance = -1.0;
        for &(cx, cy) in &candidates {
            let distance = occupied
                .iter()
                .map(|&(qx, qy)| (cx - qx).hypot(cy - qy))
                .fold(10000.0_f64, f64::min);
            if distance > best_distance {
                best = Some((cx, cy));
                best_distance = distance;
            }
        }
        let (bx, by) = best.ok_or_else(|| ApiError::bad("没有可用道具位置"))?;
        saved.insert(id.to_owned(), mark(id, space, bx, by));
        changed = true;
    }
    if changed {
        write_json(&file, &Value::Object(saved.clone()))?;
    }
    Ok(list
        .iter()
        .filter_map(|p| {
            let id = p["id"].as_str()?;
            fixed.get(id).or_else(|| saved.get(id)).cloned()
        })
        .collect())
}
