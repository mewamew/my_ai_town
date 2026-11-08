//! 作品状态的规则：创建、修订、撤下、阅读记录，以及阅读与写作在活动里的定稿。
use super::*;
use crate::error::{KernelError, Result};
use crate::{
    actor::Actor,
    affordance::Affordances,
    outcome::Receipt,
    props::Completion,
    topology::{Prop, Topology},
};
use protocol::ContentDetail;

impl ContentState {
    /// 作品数与阅读记录数；host 据此判断作品或阅读是否变化。
    pub fn revision(&self) -> (usize, usize) {
        (
            self.documents.len(),
            self.readings.values().map(|r| r.len()).sum(),
        )
    }

    /// 新放置的可读道具进入作品表。
    pub(crate) fn capture(&mut self, prop: &Prop) {
        if let Some(text) = &prop.readable {
            self.documents.insert(
                prop.id.clone(),
                Document {
                    versions: vec![text.clone()],
                    withdrawn: prop.withdrawn,
                },
            );
        }
    }

    pub(crate) fn detail(&self, topo: &Topology, id: &str) -> Result<ContentDetail> {
        let prop = topo
            .prop(id)
            .ok_or_else(|| KernelError::content("道具不存在"))?;
        let document = self
            .documents
            .get(id)
            .ok_or_else(|| KernelError::content("此道具不是书籍或公告"))?;
        Ok(ContentDetail {
            board: prop.board.clone(),
            content: document.versions.last().map(Text::view),
            id: id.into(),
            locale: prop.locale.clone(),
            versions: document.versions.iter().map(Text::metadata).collect(),
            withdrawn: document.withdrawn,
        })
    }

    /// 公告加一个版本；正文改动后道具表由调用方按作品状态重排。
    pub(crate) fn revise_bulletin(
        &mut self,
        id: &str,
        expected_version: u32,
        title: String,
        author: String,
        text: String,
    ) -> Result<()> {
        let document = self
            .documents
            .get_mut(id)
            .ok_or_else(|| KernelError::content("公告不存在"))?;
        let last = document
            .versions
            .last()
            .ok_or_else(|| KernelError::content("公告无版本"))?;
        ensure!(
            last.kind == Kind::Bulletin && !document.withdrawn,
            KernelError::content("只能修订已张贴的公告")
        );
        ensure!(
            last.version == expected_version,
            KernelError::content("公告已被修改，请刷新后编辑")
        );
        let mut revised = last.clone();
        revised.title = title;
        revised.author = author;
        revised.text = text;
        revised.version += 1;
        revised.origin = Origin::Player;
        revised.validate()?;
        document.versions.push(revised);
        Ok(())
    }

    pub(crate) fn withdraw_bulletin(&mut self, id: &str, expected_version: u32) -> Result<()> {
        let d = self
            .documents
            .get_mut(id)
            .ok_or_else(|| KernelError::content("公告不存在"))?;
        ensure!(
            d.versions
                .last()
                .is_some_and(|t| t.kind == Kind::Bulletin && t.version == expected_version),
            KernelError::content("公告版本已变化或不是公告")
        );
        d.withdrawn = true;
        Ok(())
    }

    /// 只接受调用者自己的、真正完成的阅读事实。正文不依赖当前地图或当前修订。
    pub fn reading_result(&self, actor: &str, event_id: u64) -> Result<&Reading> {
        self.readings
            .get(actor)
            .and_then(|r| r.get(&event_id))
            .ok_or_else(|| KernelError::content("这不是本人已完成的阅读记录"))
    }

    pub(crate) fn record_reading(
        &mut self,
        actor: &str,
        event_id: u64,
        pending: &Pending,
        now: f64,
    ) {
        if let Pending::Reading { prop_id, content } = pending {
            self.readings.entry(actor.into()).or_default().insert(
                event_id,
                Reading {
                    prop_id: prop_id.clone(),
                    content: content.clone(),
                    at: now,
                },
            );
        }
    }

    /// 读完的回执：带正文来源，并说明是否读过同一作品的其他版本。
    pub(crate) fn reading_receipt(&self, actor: &str, prop_id: &str, content: &Text) -> Receipt {
        let previous = self.readings.get(actor).and_then(|reads| {
            reads
                .values()
                .rev()
                .find(|r| r.content.work_id == content.work_id)
        });
        Receipt {
            text: crate::outcome::finished_reading(content, prop_id),
            readable: Some(protocol::ReadableFact {
                id: prop_id.into(),
                version: content.fingerprint(),
                previously_read: previous.is_some(),
                previous_version: previous.map(|r| r.content.fingerprint()),
            }),
        }
    }
}

/// 写作动作必须带草稿，其他动作不能带。
pub(crate) fn check_draft(
    affordances: &Affordances,
    draft: &protocol::ActionDraft,
    locale: &str,
) -> Result<()> {
    let writing = affordances
        .action(draft.prop_id.as_deref(), locale, &draft.intent.verb)
        .is_some_and(|a| a.completion == Completion::WriteBook);
    match (&draft.writing, writing) {
        (Some(d), true) => Text {
            work_id: "validation".into(),
            version: 1,
            kind: Kind::Book,
            title: d.title.clone(),
            author: "作者".into(),
            text: d.text.clone(),
            origin: Origin::Player,
        }
        .validate(),
        (None, true) => Err(KernelError::content(
            "写作需要 writing.title 和 writing.text",
        )),
        (Some(_), false) => Err(KernelError::content("只有写作动作可以携带 writing 草稿")),
        _ => Ok(()),
    }
}

/// 活动开始时冻结正文：阅读锁定当前版本，写作把草稿定成作品。`taken` 说一个编号是否已经被
/// 别的道具或别人写到一半的书占了，新书的编号要避开。
pub(crate) fn pending_for(
    affordances: &Affordances,
    topo: &Topology,
    a: &Actor,
    taken: &dyn Fn(&str) -> bool,
) -> Result<Option<Pending>> {
    let prop_id = a
        .current
        .action
        .as_ref()
        .and_then(|b| b.draft.prop_id.as_deref());
    let completion = affordances
        .action(prop_id, &a.locus.locale, &a.current.verb)
        .map(|a| a.completion.clone());
    match completion {
        Some(Completion::ReadBook | Completion::ReadBulletin) => {
            let id = prop_id
                .ok_or_else(|| KernelError::content("阅读必须明确选择具体书籍或公告实例"))?;
            let p = topo
                .prop(id)
                .filter(|p| !p.withdrawn)
                .ok_or_else(|| KernelError::content("作品已撤下"))?;
            Ok(Some(Pending::Reading {
                prop_id: id.into(),
                content: p
                    .readable
                    .clone()
                    .ok_or_else(|| KernelError::content("道具没有可读正文"))?,
            }))
        }
        Some(Completion::WriteBook) => writing_draft(affordances, a, taken).map(Some),
        _ => Ok(None),
    }
}

fn writing_draft(
    affordances: &Affordances,
    a: &Actor,
    taken: &dyn Fn(&str) -> bool,
) -> Result<Pending> {
    let binding = a
        .current
        .action
        .as_ref()
        .ok_or_else(|| KernelError::content("写作须通过带草稿的动作命令提交"))?;
    check_draft(affordances, &binding.draft, &a.locus.locale)?;
    let draft = binding
        .draft
        .writing
        .as_ref()
        .ok_or_else(|| KernelError::content("写作需要 writing.title 和 writing.text"))?;
    // 书的编号也是村民要抄的，取短的一段哈希（props::short_hash）
    let key = crate::props::short_hash(&format!("{}/{}", a.id, binding.action_id), |key| {
        taken(&format!("written:{key}"))
    });
    let id = format!("written:{key}");
    let text = Text {
        work_id: id.clone(),
        version: 1,
        kind: Kind::Book,
        title: draft.title.clone(),
        author: a.name.clone(),
        text: draft.text.clone(),
        origin: Origin::Resident {
            actor: a.id.clone(),
        },
    };
    text.validate()?;
    Ok(Pending::Writing {
        placement: Box::new(book_placement(id, a.locus.locale.clone(), text, None)),
    })
}
