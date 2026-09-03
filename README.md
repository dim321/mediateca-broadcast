# Mediateca Broadcast

## Справочник сфер деятельности

Канонический список сфер хранится в `lib/data/business_spheres.csv`. Загрузка в БД — rake-задача `directory:business_spheres:import` (идемпотентна: создаёт только отсутствующие записи, сравнение без учёта регистра).

**Development:**

```bash
docker compose exec web bundle exec rake directory:business_spheres:import
```

**Test:**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rake directory:business_spheres:import
```

Перед полной перезагрузкой справочника таблицу нужно очистить вручную (FK `profiles.business_sphere_id` с `ON DELETE RESTRICT`):

```bash
docker compose exec web bin/rails runner 'Directory::BusinessSphere.delete_all'
docker compose exec -e RAILS_ENV=test web bin/rails runner 'Directory::BusinessSphere.delete_all'
```

Если у профилей уже выбрана сфера, сначала обнулите ссылку:

```bash
docker compose exec web bin/rails runner 'Profile.update_all(business_sphere_id: nil)'
```

После правок CSV повторно запустите `directory:business_spheres:import`.

