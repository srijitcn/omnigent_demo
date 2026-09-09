---
name: debate
description: Have the Claude, GPT, and Gemini sub-agents critique the current plan across a configurable number of rounds (default 1), then converge on a single refined plan. Use in step 4 of ontogent's pipeline, after Claude drafts the plan and before presenting it to the user.
---

# debate — three model families argue the plan into shape

ontogent has drafted a plan with `claude`. Before showing it to the user,
stress-test it: relay the plan to all three model-family sub-agents, have them
critique it (and each other) for a number of rounds, then converge on one
refined plan. Every voice runs through the same Databricks credential — the
point is three genuinely different families (🟠 Claude / 🔵 GPT / 🟢 Gemini)
pulling on the same plan.

## Rounds

The user picks how many rounds of back-and-forth to run. **Default: 1 round.**
A "round" is one full cross-critique exchange (each partner sees and criticizes
the others' latest positions). Honor an explicit count ("debate this for 2
rounds"); otherwise run 1.

## Procedure

1. **Round 0 — collect opening critiques.** Dispatch the drafted plan to all
   three sub-agents in parallel via `sys_session_send` (`purpose: explore`), each
   with a stable per-partner title — the goal slug with the partner's name
   attached (e.g. `debate-<slug>-claude`, `debate-<slug>-gpt`,
   `debate-<slug>-gemini`). Ask each to critique the plan and give its improved
   version. Paste the plan (and the ontology context) as text — the partners
   share no memory. End your turn; collect all three with `sys_read_inbox`.

2. **For each debate round (default 1):**
   - Send each partner the OTHER TWO partners' latest positions and ask it to
     critique those and then give its own updated plan. Reuse each partner's own
     title so it continues its thread. Dispatch all three in the same turn so
     they run concurrently.
   - End your turn; collect the three updated positions with `sys_read_inbox`.
   - Always cross the positions: in round N, each partner critiques the others'
     round N-1 positions — never only its own.

3. **Converge.** After the final round, YOU (ontogent) write the convergence —
   you are the moderator, not a fourth debater:

       ## 🟠 Claude — final position
       <Claude's last plan, lightly trimmed>

       ## 🔵 GPT — final position
       <GPT's last plan, lightly trimmed>

       ## 🟢 Gemini — final position
       <Gemini's last plan, lightly trimmed>

       ## How the debate moved the plan
       <2-5 bullets: what each conceded, what held, agreements, and any genuine
        remaining disagreement — don't paper over it>

       ## Refined plan
       <the single, strongest merged plan, grounded in the ontology, with a clear
        file/component breakdown and acceptance criteria — this is what you carry
        into step 5 (present) and step 7 (implement)>

## Notes

- Keep it even-handed. Attribute every position to its model; never silently
  merge or drop a voice. The value is in seeing three families disagree and
  reconcile.
- One round usually surfaces the real disagreement; more rounds tend to converge
  or repeat. If a round produces no new movement, say so and converge early.
- If a partner returns an empty/unclear result mid-debate, inspect its
  conversation with `sys_session_get_history` before re-dispatching — don't
  silently drop a voice.
- Ground the critique in the ontology context: a plan that ignores the domain
  entities/relationships Genie surfaced is a weak plan, and the debate should say so.
