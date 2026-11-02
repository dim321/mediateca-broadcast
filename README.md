# 🚀 Mediateca Broadcast

**Mediateca Broadcast** — операторский хаб цифровой рекламы на экранах и аудиоустройствах: организации размещают заказы на трансляцию медиа-роликов на общих экранах, станции кэшируют суточные эфирные плейлисты, агенты на устройствах отчитываются о проигрывании. Клиентский кабинет и админка оператора покрывают медиапланы, коммерческие заказы, портреты эфира и флот станций.

[![CI](https://github.com/dim321/mediateca-broadcast/actions/workflows/ci.yml/badge.svg)](https://github.com/dim321/mediateca-broadcast/actions/workflows/ci.yml)
![Ruby](https://img.shields.io/badge/Ruby-4.0.9-red?logo=ruby)
![Rails](https://img.shields.io/badge/Rails-8.1-red?logo=rubyonrails)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-blue?logo=postgresql)

**English:** [README.en.md](README.en.md)

---

## 🌟 Основные возможности

- **Мультитенантность по организациям** — клиенты, оператор и изоляция данных в кабинете (Pundit); админка оператора без Pundit.
- **Эфирное окно (MediaPlan-as-slot)** — занятие календаря экранов медиапланом с first-write-wins, advisory-блокировками и проверкой пересечений.
- **Коммерческие заказы** — сетка по экранам и часам, активация с занятием слотов, мягкая проверка коммерческой квоты (процент, без отката occupy).
- **Суточный плейлист** — материализованная проекция эфира на станцию; пересборка после occupy/cancel/reschedule; API v2 для новых агентов.
- **Портрет эфира и сервисные темы** — циклическая структура блоков, нейтральный filler, приветствие/закрытие по расписанию локации.
- **Agent API** — Bearer-токен станции, `v1` (legacy package + play events) и `v2` (package из плейлистов), телеметрия и команды.
- **Два UI-мира** — клиентский кабинет (Slim, Hotwire, daisyUI 5) и `/admin` (ERB, Flowbite; без daisyUI).
- **Справочники оператора** — например сферы деятельности (`Directory::BusinessSphere`) с импортом из CSV.
- **Деплой через Kamal** — production-контейнеры; локально — Docker Compose и `bin/dev`.

Подробный словарь домена: [`CONCEPTS.md`](CONCEPTS.md). Ролевой онбординг: [`docs/guides/onboarding/`](docs/guides/onboarding/).

---

## 🛠 Стек технологий

### Backend

| Компонент | Технология |
|-----------|------------|
| Язык / фреймворк | Ruby **4.0.9**, Rails **~> 8.1.4** |
| БД | PostgreSQL **18** (`pg`) |
| Сервер | Puma, Thruster (production) |
| Фоновые задачи | **Solid Queue** (не Sidekiq) |
| Кэш / Cable | **Solid Cache**, **Solid Cable** (адаптеры на PostgreSQL) |
| Авторизация | `bcrypt` + `Current.user` (не Devise) |
| Авторизация (кабинет) | Pundit |
| Доменная логика | `app/domain/` — callable service objects |
| Медиа | Active Storage, `ruby-vips`, ffmpeg; S3-совместимое хранилище в production |
| i18n | По умолчанию **русский** (`config.i18n.default_locale = :ru`) |

### Frontend

| Комponent | Технология |
|-----------|------------|
| Интерактивность | Hotwire (**Turbo**, **Stimulus**), importmap |
| Стили | **Tailwind CSS 4** (`tailwindcss-rails`) |
| Кабинет | Slim, **daisyUI 5**, ViewComponent |
| Админка | ERB, **Flowbite 4** (отдельная сборка `admin.css`) |

### Database & ops

| Комponent | Технология |
|-----------|------------|
| Поиск в админке | Ransack, Kaminari |
| Логи (production) | Lograge |
| Локальная среда | Docker Compose (`compose.yaml`), Foreman (`Procfile.dev`) |
| CI/CD | **GitHub Actions** (`.github/workflows/ci.yml`) |
| Деплой | Kamal (`config/deploy.yml`) |

> **Примечание:** Redis и Sidekiq в проекте **не используются**. Отдельной интеграции Sentry в кодовой базе нет.

---

## ⚙️ Системные требования и зависимости

### Рекомендуемый путь — Docker Compose

- Docker и Docker Compose
- Опционально: файл `.env` (см. [`.env.example`](.env.example))

### Локально на хосте (без Docker)

| Зависимость | Версия / примечание |
|-------------|---------------------|
| Ruby | **4.0.9** (`.ruby-version`) |
| Bundler | совместимый с `Gemfile.lock` |
| PostgreSQL | **18** (или совместимый; `DB_HOST` не задавайте — socket) |
| Node.js | **22** (как в CI; для `npm ci` / daisyUI / Flowbite) |
| ffmpeg | обработка медиа |
| libvips | превью и варианты Active Storage |
| Foreman | ставится автоматически при первом запуске `bin/dev` |

Redis **не требуется**.

---

## 🚀 Быстрый старт

### 1. Клонирование

```bash
git clone git@github.com:dim321/mediateca-broadcast.git
cd mediateca-broadcast
```

### 2. Переменные окружения

```bash
cp .env.example .env
```

При работе через **Docker Compose** не задавайте `DB_HOST=localhost` в `.env` — в контейнере `web` уже используется `DB_HOST=postgres`. Подробности в комментариях `.env.example`.

### 3. Запуск через Docker Compose (рекомендуется)

```bash
docker compose up --build
```

- Приложение: [http://localhost:3000](http://localhost:3000)
- PostgreSQL с хоста: `localhost:5432`, пользователь/пароль `postgres` / `postgres`

Первичная настройка внутри контейнера (если нужно отдельно от автоматического сценария):

```bash
docker compose run --rm web bin/setup --skip-server
```

Импорт справочника сфер деятельности (опционально):

```bash
docker compose exec web bundle exec rake directory:business_spheres:import
```

См. [`docs/guides/directory-business-spheres-import.md`](docs/guides/directory-business-spheres-import.md).

### 4. Запуск на хосте

```bash
bundle install
npm install
bin/setup          # db:prepare (dev + test), tailwindcss:build, затем bin/dev
# или только сервер без setup:
bin/dev            # Foreman: Rails + tailwind watch + admin CSS watch
```

`bin/dev` поднимает процессы из `Procfile.dev` (порт **3000** по умолчанию).

### 5. База данных

| Команда | Назначение |
|---------|------------|
| `bin/rails db:prepare` | создать БД, миграции, загрузить schema |
| `bin/rails db:seed` | начальные данные (см. `db/seeds.rb`) |
| `bin/setup --reset` | `db:reset` в dev (разрушительно) |

В Docker для **тестов** всегда передавайте `RAILS_ENV=test`, иначе RSpec подключится к development БД:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

---

## 🧪 Тестирование и линтинг

### Полный локальный CI (рекомендуется после изменений)

В Docker:

```bash
docker compose exec -e RAILS_ENV=test web bin/ci
```

`bin/ci` последовательно запускает: `bin/setup --skip-server`, RuboCop, RSpec, bundler-audit, importmap audit, Brakeman.

### Отдельные команды

```bash
# RSpec
docker compose exec -e RAILS_ENV=test web bundle exec rspec
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/path/to/spec.rb

# RuboCop
bin/rubocop

# Безопасность
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit

# Autoload
bin/rails zeitwerk:check
```

### GitHub Actions

На каждый **push в `main`** и **pull request** workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) выполняет:

1. **scan_ruby** — Brakeman, bundler-audit  
2. **scan_js** — importmap audit  
3. **lint** — RuboCop  
4. **test** — PostgreSQL 18, `npm ci`, сборка Tailwind, `db:test:prepare`, Zeitwerk, **RSpec**

---

## 📁 Архитектура и структура проекта

### Поверхности приложения

| Путь | Аудитория | UI / auth |
|------|-----------|-----------|
| `/` | Менеджеры и бухгалтерия клиента | Slim, daisyUI, Pundit |
| `/admin` | Только организация оператора | Flowbite, без Pundit |
| `/api/agent` | Агент станции (Bearer token) | JSON |

### Доменный слой

Бизнес-операции сосредоточены в **`app/domain/`** (наследники `ServiceObject`, вызов `Foo::Bar.call`):

| Область | Примеры |
|---------|---------|
| `airtime/` | `OccupyWithPlan`, `Cancel`, `Reschedule`, `ScreenLock`, `ScreenOverlapGuard` |
| `playlists/` | `GenerateForDate`, `EnqueueRegen`, `PackageFromPlaylists` |
| `advertising/` | заказы, активация, сетка, валидация клипов |
| `agent/` | package/config, play events, команды, телеметрия |
| `commercial_quota/` | мягкая проверка процента коммерции |
| `portraits/`, `rotations/`, `service_themes/` | портрет эфира и сервисные ротации |

**Инварианты (кратко):** истина эфира — MediaPlan + подтверждённый booking; плейлист — проекция, не второй writer occupy. После успешного occupy/cancel/reschedule — `Playlists::EnqueueRegen` **вне** транзакции FWW. Agent **v1** package не менять по контракту; новые агенты — **v2**.

### Полезные каталоги

| Путь | Содержание |
|------|------------|
| [`AGENTS.md`](AGENTS.md) | Сводка для разработчиков и ассистентов |
| [`CONCEPTS.md`](CONCEPTS.md) | Глоссарий домена |
| [`docs/solutions/`](docs/solutions/) | Зафиксированные решения и паттерны |
| [`specs/002-monitors-broadcast-tz/contracts/`](specs/002-monitors-broadcast-tz/contracts/) | Контракты Agent API v1/v2 |
| [`lib/data/`](lib/data/) | CSV-справочники (сферы деятельности и др.) |

Структура тестов зеркалирует `app/` (например `app/domain/airtime/cancel.rb` → `spec/domain/airtime/cancel_spec.rb`).

---

## 🚢 Production / Kamal

Production разворачивается через **[Kamal 2](https://kamal-deploy.org/)**, не через корневой `compose.yaml` (Compose — только локальная разработка). Образ собирается из production [`Dockerfile`](Dockerfile) (Puma + Thruster, ffmpeg, libvips).

### Конфигурация

| Файл | Назначение |
|------|------------|
| [`config/deploy.yml`](config/deploy.yml) | Сервис, хосты, proxy/SSL, registry, env, accessories |
| [`bin/deploy`](bin/deploy) | Загрузка `.env` и вызов Kamal (`bundle exec kamal`) |
| [`.kamal/secrets`](.kamal/secrets) | Подстановка секретов из ENV / `config/master.key` (без сырых паролей в git) |
| [`config/recurring.yml`](config/recurring.yml) | Расписание Solid Queue в production (плейлисты, purge, рекламные заказы) |

Публичный хост и TLS задаются в `deploy.yml` (`proxy.host`, Let's Encrypt). Переменные `APP_HOST` / `APP_PROTOCOL` нужны агентам и загрузкам медиа с внешних станций.

### Секреты и окружение перед деплоем

Секреты и переменные для Kamal задаются в **`.env`** (не коммитьте файл; шаблон — [`.env.example`](.env.example)). Файл [`.kamal/secrets`](.kamal/secrets) подставляет их в `config/deploy.yml` (в т.ч. `RAILS_MASTER_KEY` из `config/master.key`).

Перед любой командой Kamal нужно, чтобы переменные из `.env` были в окружении. Для этого используйте обёртку **`bin/deploy`** — она делает `set -a`, `source .env`, затем вызывает `bundle exec kamal`:

```bash
# Примеры (аргументы те же, что у kamal)
bin/deploy deploy
bin/deploy logs
bin/deploy console
```

Не вызывайте `bin/kamal` напрямую, если секреты лежат только в `.env` — без экспорта deploy упадёт на registry/БД/S3.

Минимальный набор в `.env` для production (имена см. `.env.example` и `.kamal/secrets`):

- `MEDIATECA_BROADCAST_DATABASE_PASSWORD` — пароль PostgreSQL accessory (тот же для `POSTGRES_PASSWORD` в secrets)
- `KAMAL_REGISTRY_USER` / `KAMAL_REGISTRY_PASSWORD` — login в приватный registry
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — **rustfs** (S3-compatible), bucket `media`, endpoint в `deploy.yml`

В контейнере приложения: `DB_HOST=mediateca_broadcast-db`, `ACTIVE_STORAGE_SERVICE=rustfs`, `SOLID_QUEUE_IN_PUMA=true` (воркеры Solid Queue внутри Puma на текущей топологии).

### Accessories

В `deploy.yml` описаны:

- **`registry`** — Docker Registry `:5555` на сервере деплоя (push/pull образов Kamal)
- **`db`** — PostgreSQL **18**, доступ с хоста только на `127.0.0.1:5432`

Первый запуск accessories (один раз или после пересоздания):

```bash
bin/deploy accessory boot registry
bin/deploy accessory boot db
```

Для HTTP-registry без TLS на всех участниках push/pull может понадобиться `insecure-registries` в Docker — см. комментарии в `config/deploy.yml`.

### Деплой и эксплуатация

```bash
# Сборка, push в registry, rolling deploy
bin/deploy deploy

# Логи, консоль, psql
bin/deploy logs
bin/deploy console
bin/deploy dbc
```

Алиасы (`console`, `shell`, `logs`, `dbc`) заданы в `deploy.yml` и вызываются через **`bin/deploy`**, не через `bin/kamal`.

После деплоя миграции выполняются в рамках образа/хуков Kamal (стандартный Rails 8 + Kamal flow). При ручном вмешательстве:

```bash
bin/deploy app exec 'bin/rails db:migrate'
```

### Фоновые задачи в production

Solid Queue обрабатывает jobs из Puma (`SOLID_QUEUE_IN_PUMA`). Периодические задачи (`config/recurring.yml`, секция `production:`):

- каждые **15 минут** — горизонт генерации плейлистов (`Playlists::DispatchHorizonJob`)
- **04:00** — purge устаревших плейлистов
- **03:00** — завершение просроченных рекламных заказов
- hourly — очистка finished jobs в Solid Queue

При масштабировании на несколько web-серверов имеет смысл вынести job-роль в отдельный `servers.job` (закомментированный шаблон в `deploy.yml`).

---

## 📝 Лицензия

В корне репозитория **нет файла `LICENSE`**. Условия использования и распространения кода определяются правообладателем проекта. При публикации под open-source лицензией добавьте `LICENSE` и обновите этот раздел.

---

## 📚 Дополнительно

- [Онбординг по ролям](docs/guides/onboarding/README.md)
- [Импорт сфер деятельности](docs/guides/directory-business-spheres-import.md)
- [Гайд менеджера](docs/guides/manager-guide.md)
