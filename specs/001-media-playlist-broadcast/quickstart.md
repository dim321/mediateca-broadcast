# Quickstart: разработка фичи `001-media-playlist-broadcast`

## Предусловия

- Devcontainer с **Ruby 4.x**, **Rails 8**, **PostgreSQL 18** (см. конституцию).
- `ffprobe` / FFmpeg в образе для метаданных видео/аудио (добавить в Dockerfile
  devcontainer при инициализации приложения).

## Шаги после генерации приложения

1. Скопировать переменные: `cp .env.example .env` (или аналог).
2. `bin/setup` — миграции, seed при необходимости.
3. Запуск: `bin/dev` или `bin/rails server` + `bin/jobs` (Solid Queue).
4. Хранилище: для локали — disk; для интеграционных тестов — `test` service.
5. Запуск тестов: `bundle exec rspec` (или выбранный раннер после `rails new`).

## Проверка сценариев из спецификации

| История | Минимальная проверка |
|--------|----------------------|
| US1 | Загрузка файла, статус `processing` → `ready`, превью |
| US2 | DnD в плейлисте → `PATCH reorder` → тот же порядок после reload |
| US3 | Теги + фильтр; группа точек |
| US4 | Расписание UTC + TZ точки; конфликт → ошибка |
| US5 | Request spec устройства + ручной прогон плеера против staging |

## Контракт устройства

См. [contracts/device-api-v1.md](./contracts/device-api-v1.md). Для локальной
отладки использовать `curl` с выданным `device_token` после фиктивной
регистрации точки.
