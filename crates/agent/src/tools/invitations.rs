//! 发邀请与回应邀请的工具，各用独立参数结构。
use super::*;
use crate::session::InvitationReplyFailure;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Offer {
    partner_id: String,
    interaction: protocol::InteractionKind,
    message: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Reply {
    interaction_id: String,
    accept: bool,
    message: String,
}

pub(super) fn offer(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let mut args = call.arguments.clone();
    let partner = args["partner_id"].as_str().map(str::to_owned);
    resolve_leader(
        ctx.world,
        &ctx.session.actor_id,
        partner.as_deref(),
        &mut args["interaction"],
    );
    let a: Offer = decode(&args)?;
    execute_interaction(
        ctx,
        call,
        InteractionCommand::Offer {
            partner_id: a.partner_id,
            interaction: a.interaction,
            message: a.message,
        },
    )
}

pub(super) fn reply(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let a: Reply = match decode(&call.arguments) {
        Ok(a) => a,
        Err(error) => {
            let ids: Vec<_> = ctx
                .world
                .interactions()
                .for_actor(&ctx.session.actor_id)
                .into_iter()
                .filter(|i| {
                    i.partner == ctx.session.actor_id && i.status == InteractionStatus::Offered
                })
                .map(|i| i.id.clone())
                .collect();
            let attempts = ctx
                .session
                .invitation_reply_failure
                .as_ref()
                .filter(|f| f.invitation_ids == ids)
                .map_or(1, |f| f.attempts.saturating_add(1));
            ctx.session.invitation_reply_failure = Some(InvitationReplyFailure {
                invitation_ids: ids.clone(),
                attempts,
            });
            let message = format!("{error}；请修正后调用 reply_invitation，只填 interaction_id、accept、message。当前可回应的邀请编号：{}。accept 必须由你明确选择 true 或 false；不要原样重发错误参数。", json!(ids));
            return Err(ToolError::new(ToolErrorKind::InvalidArguments, message));
        }
    };
    let result = execute_interaction(
        ctx,
        call,
        InteractionCommand::Reply {
            interaction_id: a.interaction_id,
            accept: a.accept,
            message: a.message,
        },
    );
    if result.is_ok() {
        ctx.session.invitation_reply_failure = None;
    }
    result
}
