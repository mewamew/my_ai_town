//! 仓库里发布的内容能被 host 正常加载：HD-2D 地图、内置道具库与内置村民库。
//! 只有这一个用例读真实内容，其余用例都用 tests/fixtures 下的夹具。
use crate::support::*;
use host::application::{
    COMPATIBILITY_PATH, LEGACY_PROP_CATALOG_PATH, PROP_CATALOG_PATH, SCENE_ASSETS_PATH,
};
use kernel::avatar::WalkMap;
use serde_json::{json, Value};

/// 随应用发的内置地图（管理服务的 BUILTIN_TOWNS）
const PUBLISHED_MAPS: [&str; 3] = [
    "data/maps/2d-town/map.json",
    "data/maps/spring-valley/map.json",
    "data/maps/broken-towers/map.json",
];
const LIBRARY: &str = "config/resident-library";

fn published(relative: &str) -> String {
    repo_root().join(relative).to_string_lossy().into_owned()
}

/// 按 host 启动时的做法：读道具库（含地图引用的旧道具）、校验地图、编译行走地图。
fn walk_map(path: &str) -> (Value, WalkMap) {
    let doc = read_json(&repo_root().join(path));
    let catalog = host::props::PropLibrary::load(
        &published(PROP_CATALOG_PATH),
        &published(LEGACY_PROP_CATALOG_PATH),
        None,
        &doc,
    )
    .unwrap()
    .catalog;
    let validated =
        host::maps::validate(&doc, &catalog, &repo_root().join(SCENE_ASSETS_PATH)).unwrap();
    let topo = kernel::Topology::from_json(&validated.topology, &catalog).unwrap();
    let map = host::maps::walk::compile(&doc, &topo).unwrap().unwrap();
    (doc, map)
}

#[test]
fn published_maps_props_and_library_load_in_the_host() {
    for path in PUBLISHED_MAPS {
        // 二维地图：每个房间一对进出口，门两侧都有不被家具挡住的落脚点。
        let (doc, map) = walk_map(path);
        assert_eq!(
            map.portals.len(),
            doc["layout"]["spaces"].as_array().unwrap().len() * 2
        );
        for p in &map.portals {
            assert!(
                map.safe_near(&p.from, &map.obstacles).is_some(),
                "{path} {} 外侧",
                p.id
            );
            assert!(
                map.safe_near(&p.to, &map.obstacles).is_some(),
                "{path} {} 内侧",
                p.id
            );
        }
        // HD-2D 地图都能用正式道具库与村民库启动 host，村民库里的第一份模板可以加入。
        let mut town = Town::empty();
        town.write(
            "config/application.json",
            json!({
                "port":0,"topology_path":published(path),
                "prop_catalog_path":published(PROP_CATALOG_PATH),
                "legacy_prop_catalog_path":published(LEGACY_PROP_CATALOG_PATH),
                "scene_assets_path":published(SCENE_ASSETS_PATH),
                "compatibility_path":published(COMPATIBILITY_PATH),
                "resident_library_path":published(LIBRARY),
                "providers_path":"config/providers.json","credentials_path":"config/credentials.json"
            }),
        );
        town.args = map_args(&published(path));
        let mut ws = town.start();
        let library = reply(
            &mut ws,
            json!({"type":"get_resident_library","filter":{}}),
            "resident_library",
        );
        let template = library["templates"][0]["template_id"].as_str().unwrap();
        let outcome = join(&mut ws, template, None);
        assert_eq!(outcome["ok"], true, "{path}：{outcome}");
    }
}
