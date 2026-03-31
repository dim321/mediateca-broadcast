# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]
**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: [Ruby 4.x]  
**Primary Dependencies**: [Rails 8, Hotwire (Turbo + Stimulus), Slim, ViewComponent, Tailwind CSS, Inertia (if justified), NEEDS CLARIFICATION]  
**Storage**: PostgreSQL 18 (обязательно по конституции; отклонения только с ADR)  
**Testing**: [RSpec  + system tests (Capybara), contract/integration tests]  
**Target Platform**: [Linux server + modern browser]
**Project Type**: [Rails web application]  
**Performance Goals**: [domain-specific, e.g., 1000 req/s, 10k lines/sec, 60 fps or NEEDS CLARIFICATION]  
**Constraints**: [domain-specific, e.g., <200ms p95, <100MB memory, offline-capable or NEEDS CLARIFICATION]  
**Scale/Scope**: [domain-specific, e.g., 10k users, 1M LOC, 50 screens or NEEDS CLARIFICATION]

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [ ] TDD: тесты написаны до реализации (Red -> Green -> Refactor) и зафиксирован red-state.
- [ ] DDD: определены bounded context, агрегаты/сущности и доменные инварианты.
- [ ] UI: выбран Hotwire-first подход; если выбран Inertia, есть ADR с UX-метриками.
- [ ] UI stack: представления на Slim, UI через ViewComponent, стилизация на Tailwind CSS.
- [ ] Runtime/Tooling: Devcontainer обновлен и воспроизводим локально.
- [ ] Delivery: план деплоя/отката через Kamal для изменений, влияющих на release.
- [ ] Authorization: разграничение прав через Pundit или CanCanCan; новые правила
  доступа — с тестами политик/abilities.
- [ ] Admin: операции в админке через Avo; доступ к ресурсам и действиям согласован
  с теми же политиками/abilities, что и основное приложение.
- [ ] Data: схема и миграции под PostgreSQL 18; отклонение от конституции только с ADR.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
app/
├── controllers/
├── models/
├── views/
│   └── [feature]/*.slim
├── components/
│   └── [feature]/*_component.rb
├── javascript/
│   └── controllers/
└── domain/
    └── [bounded_context]/

spec/ or test/
├── models|unit/
├── requests|integration/
├── system/
└── components/

config/
├── deploy.yml
└── environments/

.devcontainer/
└── devcontainer.json
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
