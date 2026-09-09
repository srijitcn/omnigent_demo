# Ontology context

This file is ontogent's accumulated, ontology-grounded context. It starts
(almost) empty. On each run, ontogent asks the Databricks **Genie** MCP server
about your goal, distills the response into domain **keywords** and an
**ontology** (entities, their attributes, and the relationships between them),
and **appends a new timestamped section below**. The planner and the debate read
this file so the plan is grounded in your data's own vocabulary.

Leave the heading above in place. Everything below the line is machine-appended.

---

<!-- ontogent appends grounding sections here, e.g.:

## 2026-09-08T14:03Z — Goal: "a churn-risk dashboard for subscription accounts"

**Keywords:** account, subscription, churn, MRR, tenure, plan tier, usage, dunning

**Ontology**
- Entity: Account — attributes: account_id, plan_tier, mrr, signup_date, status
- Entity: Subscription — attributes: subscription_id, account_id (→ Account), term, renewal_date
- Entity: UsageEvent — attributes: account_id (→ Account), event_ts, feature, count
- Relationship: Account 1—* Subscription
- Relationship: Account 1—* UsageEvent
- Note (from Genie): churn is modeled as status='cancelled' within 30d of renewal_date

-->
