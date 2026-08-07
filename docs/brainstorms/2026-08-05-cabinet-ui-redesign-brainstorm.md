---
date: 2026-08-05
topic: cabinet-ui-redesign
---

# Cabinet UI Redesign (Clean SaaS)

## What We're Building

Светлая оболочка личного кабинета мультитенант SaaS Mediateca Broadcast: sidebar + workspace. Визуальный язык — чистый SaaS (нейтральные поверхности, один primary-акцент, много воздуха). Первая итерация: layout + ключевые экраны (медиатека, логин, списки ротаций / групп экранов / медиапланов).

## Why This Approach

Рассмотрены альтернативы: тёмный «control room» и минимальный refresh без смены структуры. Выбран sidebar + светлый workspace — удобнее для операторов, которые часто переключают разделы; светлая чистая эстетика лучше соответствует мультитенант SaaS, чем media/broadcast-тематика.

## Key Decisions

- **Каркас**: sidebar слева + основной workspace справа (responsive: drawer на мобиле).
- **Эстетика**: Clean SaaS — серые/base поверхности, синий или бирюзовый primary, без тяжёлого декора.
- **Стек UI**: Tailwind CSS 4 + daisyUI 5 (компоненты navbar/menu/btn/card/alert/drawer).
- **Tenant context**: вверху sidebar — бренд продукта + имя `Current.organization`; switcher позже, сейчас только отображение.
- **Top bar**: email текущего пользователя + Sign out; flash — toast/alert в workspace.
- **Объём v1**:
  - layout (`application.html.erb` → drawer/sidebar shell);
  - login;
  - Media library (upload zone + grid);
  - index-страницы: Rotations, Screen groups, Media plans.
- **Вне scope v1**: show/edit/new формы, org switcher, тёмная тема, кастомный брендинг per-tenant.

## Open Questions

- Точный primary color (blue vs teal) — решить при подключении daisyUI theme.
- Нужен ли пункт «Media library» явно в sidebar (сейчас root = media_assets#index) — да, для discoverability.
- Active state навигации: по `controller_name` / path helper.

## Next Steps

→ Plan written: `docs/plans/2026-08-05-001-feat-cabinet-ui-redesign-plan.md` (includes Hotwire reactivity). Execute via `ce-work` or implement manually.
