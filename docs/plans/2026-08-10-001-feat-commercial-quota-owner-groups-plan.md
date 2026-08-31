---
title: Commercial Quota on Owner Groups - Plan
type: feat
date: 2026-08-10
topic: commercial-quota-owner-groups
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-brainstorm
execution: code
origin: customer clarification (client-owned screens + commercial share)
deepened: 2026-08-10
---

# Commercial Quota on Owner Groups - Plan

## Goal Capsule

- **Objective:** Дать владельцу экранов (и оператору) задавать бессрочную квоту доли commercial-эфира на однородной именованной группе точек; после успешного размещения commercial-медиаплана с `shows_per_hour` система мягко предупреждает о превышении (flash), не блокируя слот.
- **Product authority:** Product Contract ниже. Не возвращает секундный бюджет `AirtimeQuota`; календарная модель слота (`docs/plans/2026-08-06-001-feat-media-plan-as-airtime-slot-plan.md`) остаётся. Surrounding: отчёты/биллинг/штрафы и авто-filler — не active scope.
- **Open blockers:** нет.
- **Execution profile:** code; test-first для domain calculators, channel rule, soft flash path.
- **Stop conditions:** не возвращать `AirtimeQuota` seconds; не класть soft math в `ScreenOverlapGuard`; не hard-block размещение по квоте.
- **Tail ownership:** `ce-work` / implementer owns unit verification; CI green before merge.

---

## Product Contract

**Product Contract preservation:** changed: R11 / F3 / AE1 / Success Criteria — soft warning delivery = flash after successful create/reschedule (session-settled over pre-submit acknowledge). R8 enum name fixed to `placement_kind: commercial | own_atmosphere`. Outstanding Deferred-to-Planning resolved into KTDs (no scope change beyond delivery of R11).

### Summary

На экранах появляется клиент-владелец. На однородной группе владельца задаётся квота: % commercial + единица периода (час/сутки), бессрочно до изменения. Commercial-медиапланы (в т.ч. чужих org только через группу владельца — план placer на группе owner) несут `shows_per_hour`; потребление за час = сумма `N × длительность цикла ротации`. Сверка с % от минут работы локации; при превышении — flash после успешного occupy, размещение не блокируется. Own/atmosphere в числитель не входят.

### Problem Frame

На части локаций точки фактически принадлежат клиенту: он готов отдавать под сетевую рекламу только долю эфира, остальное — свой/атмосферный контент. Текущая модель «весь свободный календарь + FWW» не выражает потолок commercial-доли. Старая `AirtimeQuota` (секунды × окно как условие брони) для этого не подходит и уже снята.

### Key Decisions

- **Владение на Screen.** У экрана опциональный клиент-владелец. `(session-settled: user-directed — chosen over Location / hybrid)` Governs R1, R3.
- **Квота на именованной группе.** Носитель % — однородная группа владельца, не секундный бюджет слота. `(session-settled: user-directed — chosen over owner-policy without group / seconds AirtimeQuota)` Governs R4–R6.
- **Однородность группы.** Квоту можно задать только если все экраны группы имеют одного владельца. `(session-settled: user-directed — chosen over partial-screen accounting / group-agnostic %)` Governs R3, R4.
- **Знаменатель = часы локации.** % считается от минут работы локации в периоде; без часов квоту задать нельзя. `(session-settled: user-directed — chosen over full calendar / occupied windows only)` Governs R7, R12.
- **Числитель = commercial-планы.** В учёт идут только планы с меткой commercial placement. `(session-settled: user-directed — chosen over rotation content_type weight / whole-plan-if-any-commercial-asset)` Governs R8, R10.
- **Продажа инвентаря через группу владельца.** Чужой commercial на чужих экранах — только через группу владельца. `(session-settled: user-directed — chosen over any-org assembled groups / owner-only placement)` Governs R9.
- **Soft control.** Превышение → предупреждение; план не блокируется. `(session-settled: user-directed — chosen over hard reject / hard-for-foreign-soft-for-owner)` Governs R11.
- **Частота на медиаплане.** `shows_per_hour` на плане; время = `N × длительность цикла ротации`. `(session-settled: user-directed — chosen over rotation default / commercial-only field with no N)` Governs R10, R13.
- **Сутки = часовые срезы.** При единице «сутки» проверка режется по часам внутри суток. `(session-settled: user-directed — chosen over single day-total aggregation)` Governs R12.
- **Сумма без overlap-учёта.** Несколько commercial-планов в часе суммируются без вычета пересечений на экране (soft MVP). `(session-settled: user-directed — chosen over screen-timeline overlap accounting)` Governs R13.
- **Задают квоту владелец и оператор.** Бессрочно с момента задания/изменения. `(session-settled: user-directed — from feature brief)` Governs R4, R5.

<!-- ce-section: work-relationships -->
### How This Work Fits Together

This plan owns **commercial share quota on owner-homogeneous groups** (ownership, operating hours gate, soft consumption check).

Broader understanding (candidates, not committed roadmap):

- `docs/plans/2026-08-06-001-feat-media-plan-as-airtime-slot-plan.md` — **Depends on:** календарный слот/FWW без секундной ёмкости сохраняется; эта работа **Shares** MediaPlan/BPG/Screen, **не** возвращает capacity `AirtimeQuota`.
- Авто-filler / нейтральная добивка эфира — **Can proceed independently**; own/atmosphere здесь только через явные планы.
- Отчёты / биллинг / штрафы за превышение — **Can proceed independently** (explicit non-goal).
- Agent package / ScheduleItem — **Still to decide** timing; soft MVP не требует отказа пакета при превышении квоты.

### Actors

- A1. **Manager / administrator клиента-владельца** — владеет экранами; задаёт часы локации и квоту на своей однородной группе; ставит own/atmosphere и commercial планы.
- A2. **Manager / administrator другого клиента** — ставит commercial только через группу владельца; видит soft warning при превышении.
- A3. **Оператор** — назначает владельца экрана; может задавать часы и квоту; полный обзор.
- A4. **Broadcast Hub** — считает потребление commercial за час и отдаёт предупреждение.

### Key Flows

- F1. Назначение владельца и часов
  - **Trigger:** Точки клиента появляются в сети.
  - **Actors:** A3 (и/или A1 для часов)
  - **Steps:** Оператор назначает organization-владельца на Screen; владелец или оператор задаёт operating hours на Location.
  - **Outcome:** Экраны готовы к однородным группам и квоте.
  - **Covered by:** R1, R7

- F2. Задание квоты на группе
  - **Trigger:** Владелец/оператор хочет ограничить долю commercial.
  - **Actors:** A1, A3, A4
  - **Steps:** Выбирают однородную группу владельца; задают % и единицу периода (час/сутки); без часов локации — отказ; квота действует бессрочно до изменения.
  - **Outcome:** На группе активна commercial quota.
  - **Covered by:** R3–R7

- F3. Размещение commercial с N показов/час
  - **Trigger:** Владелец или чужой клиент размещает commercial на группе владельца.
  - **Actors:** A1 или A2, A4
  - **Steps:** Создают/переносят MediaPlan с `placement_kind=commercial` и `shows_per_hour`; FWW occupy как сейчас; после успеха — soft check; при превышении flash warning.
  - **Outcome:** План active; пользователь предупреждён при превышении.
  - **Covered by:** R8–R13

- F4. Own / atmosphere вне числителя
  - **Trigger:** Владелец добивает эфир своим контентом.
  - **Actors:** A1, A4
  - **Steps:** Создаёт план с `placement_kind=own_atmosphere`; время таких планов не увеличивает commercial-числитель.
  - **Outcome:** Квота commercial не затрагивается.
  - **Covered by:** R8

### Requirements

**Ownership and groups**

- R1. Screen может иметь опционального клиента-владельца (`organization`); экраны без владельца — флот без owner-quota.
- R2. Назначение владельца экрана доступно оператору.
- R3. Квоту можно задать только на группе, где все экраны принадлежат одному и тому же владельцу.
- R9. Commercial-размещение на экранах с владельцем допускается только через BroadcastPointGroup этого владельца; сборная группа другой org для commercial на чужих owned-экранах запрещена.

**Quota definition**

- R4. На однородной группе владельца задаётся commercial quota: процент и единица периода (`hour` | `day`).
- R5. Задавать и изменять квоту могут клиент-владелец (менеджер/админ его org) и оператор.
- R6. Квота действует бессрочно с момента задания или изменения; отдельного окна действия у квоты нет.
- R7. Часы работы Location обязательны для задания квоты; задают владелец связанных экранов и/или оператор; без часов — квоту задать нельзя.

**Placement and consumption**

- R8. У MediaPlan есть `placement_kind`: `commercial` | `own_atmosphere`; в числитель квоты входят только `commercial`.
- R10. У MediaPlan задаётся `shows_per_hour` (N ≥ 1 для commercial); расчётное время показа плана за час = `N × длительность цикла привязанной ротации`.
- R11. После успешного create/reschedule commercial-плана, если расчётное потребление превышает квоту в затронутых часах, система показывает предупреждение (flash) и не откатывает размещение.
- R12. Допустимое commercial-время за час = заданный % от минут operating hours локации, попадающих в этот час. При единице периода `day` проверка выполняется по каждому часу суток отдельно тем же часовым срезом.
- R13. Потребление часа на группе = сумма расчётных времён всех overlapping commercial-планов на этой группе за час, без вычета реального overlap на экране.

**Non-goals encoded as requirements boundaries**

- R14. Система в этом объёме не выставляет штрафы, не ведёт биллинг показов и не строит отчётный UI по квоте (кроме warning при размещении).

### Acceptance Examples

- AE1. Soft warning on exceed
  - **Covers:** R10, R11, R12, R13
  - **Given:** Группа владельца, квота 60%/hour, локация работает 60 мин в часе; ротация циклом 4 мин; уже есть commercial-план 5 показов/час (20 мин).
  - **When:** Новый commercial-план на ту же группу с 10 показами/час (40 мин) в том же часе.
  - **Then:** План при свободном календаре создаётся; flash о превышении (20+40 > 36).

- AE2. Day unit still hourly slices
  - **Covers:** R12
  - **Given:** Квота с единицей `day` и тем же %.
  - **When:** Размещение затрагивает несколько часов суток.
  - **Then:** Превышение оценивается per-hour; сутки не схлопываются в один агрегат.

- AE3. Heterogeneous group blocked
  - **Covers:** R3, R4
  - **Given:** В группе экраны двух разных владельцев.
  - **When:** Попытка задать квоту.
  - **Then:** Квоту задать нельзя.

- AE4. Foreign commercial only via owner group
  - **Covers:** R9
  - **Given:** Экраны принадлежат org A.
  - **When:** Org B пытается создать commercial-план на своей группе, собранной из экранов A.
  - **Then:** Размещение commercial отклоняется правилом канала; через группу A — допускается (с soft quota check).

- AE5. Own/atmosphere excluded from numerator
  - **Covers:** R8
  - **Given:** Квота и commercial уже у потолка часа.
  - **When:** Владелец добавляет own/atmosphere-план на ту же группу.
  - **Then:** Warning квоты commercial не срабатывает из-за этого плана.

- AE6. No operating hours — no quota
  - **Covers:** R7
  - **Given:** У локации экранов группы нет operating hours.
  - **When:** Владелец задаёт %.
  - **Then:** Квоту сохранить нельзя до задания часов.

### Success Criteria

- Владелец и оператор могут назначить/изменить бессрочную квоту на однородной группе при наличии часов локации.
- Менеджер при превышении commercial-доли видит flash после успешного размещения.
- Чужой commercial на owned-экранах идёт только через группу владельца (план placer на группе owner).
- Календарный FWW и модель слота без секундной ёмкости не ломаются.

### Scope Boundaries

**In scope**

- Screen owner; Location operating hours; quota on homogeneous owner BPG; MediaPlan placement kind + shows_per_hour; soft warning flash; foreign commercial via owner group only.

**Deferred for later**

- Отчёты по факту/плану квоты, биллинг, штрафы.
- Авто-filler / нейтральная добивка без явного медиаплана.
- Учёт реального overlap на timeline экрана в числителе.
- Hard enforcement квоты.
- Pre-submit acknowledge / modal before occupy.

**Outside this work / anti-patterns**

- Возврат `AirtimeQuota` как бюджета секунд и условия брони слота.
- Отдельный холд без медиаплана.

### Dependencies / Assumptions

- MediaPlan-as-slot / FWW остаются источником календарной эксклюзивности (`docs/solutions/architecture-patterns/media-plan-as-airtime-slot.md`).
- Длительность цикла: item → asset → default 15s (KTD5).
- Operating hours: weekly schedule on Location (KTD4).

### Outstanding Questions

**Resolve Before Planning:** нет.

**Deferred to Planning / Implementation**

- Точный JSON/UI shape weekly hours (в пределах KTD4).
- i18n copy flash warning.
- Нужен ли `shows_per_hour` на own_atmosphere в UI (не влияет на числитель; default omit).

### Sources / Research

- Prior anti-capacity: `docs/plans/2026-08-06-001-feat-media-plan-as-airtime-slot-plan.md`, `docs/solutions/architecture-patterns/media-plan-as-airtime-slot.md`, `CONCEPTS.md`.
- Historical seconds quota dropped: `db/migrate/20260806100000_drop_airtime_quotas_and_add_media_plan_cancelled.rb`.
- Org-owns-group today: `app/domain/airtime/occupy_with_plan.rb`, `app/models/media_plan.rb`, `app/policies/application_policy.rb`.

---

## Planning Contract

### Key Technical Decisions

- KTD1. **План placer на группе owner.** `MediaPlan`/`AirtimeBooking.organization` = placer; `broadcast_point_group` может принадлежать owner org. Ослабить `OccupyWithPlan`/`Reschedule`/`MediaPlan` org-match для commercial (и policy_scope eligible owner groups). Own/atmosphere и non-commercial по-прежнему только на своей группе. `(session-settled: user-directed — chosen over keep org-owns-group: R9 иначе нереализуем)` Instantiates R9.
- KTD2. **Soft warning = flash после успешного occupy/reschedule.** Не двухшаговый `acknowledge_quota_warning`. Check вызывается **после** успешного FWW; flash[:warning]; план не откатывается. `(session-settled: user-directed — chosen over pre-submit acknowledge)` Instantiates R11.
- KTD3. **CommercialQuota domain рядом с Airtime, не внутри Guard.** Pure calculators + `CommercialQuota::Check`; `ScreenOverlapGuard` остаётся только календарным FWW. Не создавать `AirtimeQuota` table. Instantiates R12, R13; honors slot learning.
- KTD4. **Operating hours на Location как weekly schedule (JSONB).** Достаточно для минут-в-часе; TZ организации владельца / location org context — implementer follows existing org TZ helpers if any, else document in U2. Без hours → нельзя сохранить quota columns. Instantiates R7, R12.
- KTD5. **Cycle duration: item → asset → 15s default.** `RotationItem#display_duration_seconds` → `MediaAsset#duration_seconds` → `15`. Soft MVP допускает занижение. `(session-settled: user-directed — chosen over hard-fail without duration)` Instantiates R10.
- KTD6. **Quota columns on BroadcastPointGroup.** Nullable `commercial_quota_percent`, `commercial_quota_period` (`hour`|`day`); set/clear = indefinite until changed. Homogeneity + hours gate on assign. Instantiates R3–R6.
- KTD7. **Hard channel rule separate from soft quota.** Commercial на группе, чьи экраны имеют owner ≠ group.organization (или смесь владельцев / чужие owned screens на чужой группе) → ArgumentError/validation fail. Soft quota never substitutes for this. Instantiates R9.
- KTD8. **`shows_per_hour` required for commercial; optional/ignored for own_atmosphere numerator.** Instantiates R8, R10.

### Technical Design

```
Screen.owner_organization (optional)
Location.operating_hours (weekly jsonb)
BroadcastPointGroup.commercial_quota_{percent,period}
MediaPlan.placement_kind + shows_per_hour

OccupyWithPlan / Reschedule
  → FWW as today
  → (after success) CommercialQuota::Check → flash if exceeded

CommercialQuota::CycleDuration(rotation)
CommercialQuota::HourlyAllowance(location, hour, percent)
CommercialQuota::Consumption(group, hour, excluding: optional plan)
CommercialQuota::Check(plan_attrs) → { exceeded:, hours: [...] }
```

Allowance for a clock hour: minutes of operating hours intersecting that hour × (percent/100), converted to seconds. If group screens span multiple locations, use the **strictest** hour allowance among locations (min) for soft MVP — document in U4; avoid inventing multi-location averaging.

### Assumptions

- Default still duration 15s is acceptable for soft MVP underestimation risk (KTD5).
- Weekly hours JSONB is enough; no per-exception holidays in v1.
- Foreign placer sees owner groups only when placing commercial (policy), not full CRUD on owner BPG.

### Risks

| Risk | Mitigation |
|------|------------|
| Cross-org occupy widens tenant leak | Narrow policy: read-only select of eligible owner groups; no edit membership for foreign |
| Soft sum overcounts overlapping plans | Accepted for soft MVP (R13); document in UI copy later |
| 15s default under-reports | Follow-up: require durations for commercial; not this plan |
| Hours missing → no quota | Clear validation (AE6) |

### Alternatives Considered

- Pre-submit acknowledge — rejected (KTD2).
- Seconds `AirtimeQuota` — anti-pattern per slot learning.
- Soft math inside ScreenOverlapGuard — rejected (KTD3).

### Open Questions

- None blocking. Implementation may refine weekly hours JSON schema within KTD4.

### Implementation Units Overview

| ID | Unit | Depends on | Primary proof |
|----|------|------------|---------------|
| U1 | Screen owner + Location hours schema/admin+LK | — | model/request |
| U2 | BPG quota fields + homogeneity/hours gates | U1 | model |
| U3 | MediaPlan placement_kind + shows_per_hour | — | model |
| U4 | CommercialQuota calculators + Check | U1–U3 | domain specs |
| U5 | Channel rule + cross-org occupy/reschedule/policies | U2–U3 | domain + policy |
| U6 | LK/Admin UX: quota, hours, form fields, flash | U4–U5 | request |

Suggested sequence: U1 → U2 → U3 → U4 → U5 → U6 (U3 can parallel U1/U2).

---

## Implementation Units

### U1. Screen owner and Location operating hours

- **Goal:** Persist optional screen owner and location weekly operating hours; expose to operator (admin) and owner hours edit in LK where policy allows.
- **Risk:** Medium — foundation for R7/R1.
- **Dependencies:** none
- **Files:** `db/migrate/*_add_owner_to_screens_and_hours_to_locations.rb`, `app/models/screen.rb`, `app/models/location.rb`, `app/dashboards/screen_dashboard.rb`, `app/dashboards/location_dashboard.rb`, `app/policies/screen_policy.rb`, `app/policies/location_policy.rb`, `app/controllers/` (LK location hours if present), `spec/models/screen_spec.rb`, `spec/models/location_spec.rb`, `spec/requests/admin/screens_spec.rb` (or equivalent)
- **Approach:** `screens.owner_organization_id` optional FK; `locations.operating_hours` jsonb (weekly windows). Operator sets owner via Administrate. Owner org managers/admins and operator may edit hours on locations that have their owned screens (policy detail in implementer judgment within R7).
- **Patterns:** existing Fleet/Administrate dashboards; `FleetPolicy`.
- **Test scenarios:**
  - Screen can save with/without owner_organization.
  - Location rejects quota-dependent consumers when hours blank (covered more in U2); hours round-trip JSON.
  - Non-operator cannot assign screen owner.
- **Verification:** model + admin request specs green.

### U2. BroadcastPointGroup commercial quota

- **Goal:** Store indefinite commercial quota on homogeneous owner groups; gate on hours.
- **Risk:** Medium
- **Dependencies:** U1
- **Files:** `db/migrate/*_add_commercial_quota_to_broadcast_point_groups.rb`, `app/models/broadcast_point_group.rb`, `app/controllers/broadcast_point_groups_controller.rb`, `app/views/broadcast_point_groups/*`, `app/dashboards/broadcast_point_group_dashboard.rb`, `app/policies/broadcast_point_group_policy.rb`, `spec/models/broadcast_point_group_spec.rb`, `spec/requests/broadcast_point_groups_spec.rb`
- **Approach:** Columns `commercial_quota_percent` (1–100), `commercial_quota_period` enum hour/day. On set: all screens same `owner_organization_id` == `group.organization_id`; every screen’s location has operating hours. Clear quota allowed. Owner managers/admins + operator can set.
- **Test scenarios:**
  - AE3: heterogeneous → cannot set quota.
  - AE6: missing hours → cannot set quota.
  - Homogeneous + hours → set/update/clear succeeds; indefinite (no ends_at).
- **Verification:** model + request specs.

### U3. MediaPlan placement_kind and shows_per_hour

- **Goal:** Add placement metadata required for numerator and N×cycle.
- **Risk:** Low–Medium
- **Dependencies:** none (parallel OK)
- **Files:** `db/migrate/*_add_placement_to_media_plans.rb`, `app/models/media_plan.rb`, `app/controllers/media_plans_controller.rb` (strong params), factories, `spec/models/media_plan_spec.rb`
- **Approach:** enum `placement_kind` commercial|own_atmosphere; integer `shows_per_hour`. Validate presence/≥1 when commercial (KTD8). Pass through `OccupyWithPlan`/`Reschedule` create attrs.
- **Test scenarios:**
  - commercial without shows_per_hour invalid.
  - own_atmosphere valid without shows_per_hour.
  - enum values persist.
- **Verification:** model specs.

### U4. CommercialQuota domain calculators

- **Goal:** Pure check for soft warning; no FWW coupling.
- **Risk:** Medium — formula correctness for AE1/AE2.
- **Dependencies:** U1–U3
- **Files:** `app/domain/commercial_quota/cycle_duration.rb`, `hourly_allowance.rb`, `consumption.rb`, `check.rb`, `spec/domain/commercial_quota/*_spec.rb`
- **Approach:** CycleDuration per KTD5. HourlyAllowance from location hours ∩ hour × percent. Consumption sums `shows_per_hour * cycle` for active commercial plans overlapping hour on group (include candidate plan). Check iterates hours touched by window; for `day` period still per-hour slices (R12). Multi-location: min allowance (Technical Design). Return exceeded + hour list. No DB writes.
- **Test scenarios:**
  - AE1 numbers (20+40 > 36).
  - AE2 multi-hour day unit.
  - AE5 own_atmosphere excluded from consumption.
  - Fallback 15s when durations nil.
  - No quota configured → Check not exceeded (no warn).
- **Verification:** domain specs only; test-first preferred.

### U5. Channel rule and cross-org occupy

- **Goal:** Enforce R9 hard; allow placer plan on owner group for commercial.
- **Risk:** High — tenant boundary
- **Dependencies:** U2, U3
- **Files:** `app/domain/airtime/occupy_with_plan.rb`, `app/domain/airtime/reschedule.rb`, `app/models/media_plan.rb`, `app/policies/broadcast_point_group_policy.rb`, `app/policies/media_plan_policy.rb`, `app/policies/application_policy.rb` (scope helpers), `spec/domain/airtime/occupy_with_plan_spec.rb`, `spec/domain/airtime/reschedule_spec.rb`, `spec/policies/*`
- **Approach:** Replace blanket org-owns-group with: (a) own group always OK for own/atmosphere and commercial on own screens; (b) commercial on foreign group OK iff group.organization is screen-owner homogeneous and all screens owned by that org; (c) commercial on placer’s group that includes foreign-owned screens → reject (KTD7). Rotation still owned by placer. Policy scope: own groups ∪ commercial-eligible owner groups (read for form select). Same-org MediaPlanConflictDetector unchanged; FWW Guard unchanged.
- **Test scenarios:**
  - AE4 reject and allow paths.
  - Existing same-org occupy still works.
  - Foreign own_atmosphere on owner group rejected.
  - Policy: foreign user cannot update owner group membership.
- **Verification:** domain + policy specs; update specs that assumed org-owns-group always.

### U6. LK/Admin UX and soft flash

- **Goal:** Wire forms, collections, flash after create/reschedule.
- **Risk:** Medium — UX + params
- **Dependencies:** U4, U5
- **Files:** `app/controllers/media_plans_controller.rb`, `app/controllers/admin/media_plans_controller.rb`, `app/views/media_plans/_form.html.slim`, BPG/location views, `config/locales/mediateca.en.yml`, `spec/requests/media_plans_spec.rb`, `spec/requests/admin/media_plans_spec.rb`
- **Approach:** After successful OccupyWithPlan/Reschedule, run Check for commercial; set flash warning (KTD2). Form: placement_kind, shows_per_hour; group collection includes eligible owner groups for commercial. Admin: owner on screen, hours on location, quota on BPG.
- **Test scenarios:**
  - AE1 request: create succeeds + flash present.
  - Reschedule exceed → flash.
  - Under quota → no warning flash.
  - Foreign commercial via owner group create path happy.
- **Verification:** request specs green.

---

## Verification Contract

- **Automated:** `bundle exec rspec` focusing on touched specs; full suite before merge.
- **Manual smoke:** assign owner → set hours → set 60%/hour quota → place commercial with N that exceeds → confirm flash and plan active; place via second org on owner group; attempt commercial on foreign assembled group → rejected.
- **Quality gates:** RuboCop on touched files; no new AirtimeQuota model/table.

## Definition of Done

- All U1–U6 scenarios pass; AE1–AE6 covered by automated tests where applicable.
- Product Contract R1–R14 satisfied without seconds quota.
- CONCEPTS vocabulary used (commercial quota, screen owner, shows per hour).
- No soft math inside ScreenOverlapGuard; FWW unchanged in spirit.

## Appendix

### Research notes

- Repo patterns: occupy org-owns-group at `app/domain/airtime/occupy_with_plan.rb:52`; slot learning forbids capacity AirtimeQuota.
- External research: skipped — settled approach + strong local Airtime patterns.
