# Admin station show: agent package/config preview — дизайн

## Цель

На странице показа станции в операторской админке (`/admin/stations/:id`)
показать оператору ровно те JSON-тела, которые станция получает с hub:

- полный ответ `GET /api/agent/v2/package`;
- полный ответ `GET /api/agent/v1/config`.

Это диагностический preview «что увидит агент», а не отдельная табличная
проекция плейлиста (та уже есть выше на странице).

## Поведение

1. В `Admin::StationsController#show` после загрузки станции/плейлиста/телеметрии
   вызвать:
   - `Playlists::PackageFromPlaylists.call(station: @station)` → `@agent_package`;
   - `Agent::ConfigBuilder.call(station: @station)` → `@agent_config`.
2. Билдеры вызываются **as-is**. Для package это значит: при промахе дат
   горизонта ставится в очередь regenerate — та же семантика, что у живого
   `GET /api/agent/v2/package`. Отдельный флаг `enqueue_missing` / preview-режим
   не вводится.
3. Доменные билдеры и agent-контроллеры не меняют контракт ответа.

## UI

Два блока Flowbite внизу `app/views/admin/stations/show.html.erb`, после
секции телеметрии и перед кнопками Edit / Back / Destroy:

1. заголовок `admin.stations.agent_package_v2` + `<pre>` с
   `JSON.pretty_generate(@agent_package)`;
2. заголовок `admin.stations.agent_config_v1` + `<pre>` с
   `JSON.pretty_generate(@agent_config)`.

Стиль карточек — как у существующих секций страницы
(`bg-white border border-gray-200 rounded-lg p-6`). Pre: моноширинный мелкий
текст, горизонтальный скролл (`overflow-x-auto`), без daisyUI-классов.

Ключи i18n (ru + en), например:

- `admin.stations.agent_package_v2` — «Пакет агента (v2)» /
  «Agent package (v2)»;
- `admin.stations.agent_config_v1` — «Конфиг агента (v1)» /
  «Agent config (v1)».

## Вне scope

- Табличный разбор `entries` / `screen_map` (оператор смотрит сырой JSON).
- Отдельный admin endpoint или proxy к `/api/agent/*`.
- Изменение shape v1 config / v2 package.
- Preview без side effects (enqueue при miss остаётся).

## Тестирование

Request-спека `spec/requests/admin/stations_spec.rb` (show):

1. HTML содержит заголовки обеих секций;
2. в теле страницы есть ключевые поля package (`"entries"`, `"screen_map"`,
   `"etag"`) и config (`"station_id"`, `"screens"`, `"offline_cache_hours"`);
3. при отсутствии current-плейлистов на горизонте открытие show ставит в
   очередь regenerate (как AE10 / поведение PackageFromPlaylists).

Отдельный domain-флаг не тестируем — поведение билдера не меняется.
