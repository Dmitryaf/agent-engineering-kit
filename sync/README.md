# Синхронизация правил с проектами

## Обычное использование

Для обычных операций используйте корневой [`ai-rules.ps1`](../ai-rules.ps1) из корня checkout хаба:

- `init` — первичное подключение;
- `status` — состояние проекта;
- `plan` — план текущей pinned revision;
- `apply` — повторное применение текущей pinned revision;
- `update` — переход на текущую revision checkout хаба.

Типичный маршрут:

```powershell
.\ai-rules.ps1 init -ProjectRoot C:\path\to\project -Profiles standard-product
.\ai-rules.ps1 doctor -ProjectRoot C:\path\to\project
.\ai-rules.ps1 update -ProjectRoot C:\path\to\project
.\ai-rules.ps1 update -ProjectRoot C:\path\to\project -Apply
```

Инструкция для обычного пользователя находится в корневом [`README.md`](../README.md).

## Низкоуровневый sync-контракт

Прямые команды ниже нужны для отладки и интеграции. Корневой CLI вызывает те же initializer и sync-скрипты и не создаёт второй механизм синхронизации.

Внутренний машинный контракт отделён от вывода CLI. `src/SyncPlan.psm1` возвращает типизированный `AiRules.SyncPlan`, а `src/ProjectState.psm1` — общий `AiRules.ProjectState` для `status` и `doctor`. `scripts/sync-rules.ps1` и `ai-rules.ps1` только отображают эти объекты и выполняют разрешённое действие. Строка `Summary:` предназначена человеку и не используется для принятия внутренних решений.

Версия manifest/lock `0.2` использует локальную pull-модель:

```text
checkout AI Rules Hub
→ .ai-rules/manifest.json
→ Plan
→ ручная проверка
→ Apply
→ автономный снимок в .ai-rules/upstream/
```

После `Apply` обычная работа проекта не требует доступа к хабу.

## Структура подключённого проекта

```text
project/
├── AGENTS.md
└── .ai-rules/
    ├── manifest.json
    ├── lock.json
    ├── RULESET.md
    ├── PROJECT_RULES.md
    └── upstream/
        ├── CORE.md
        ├── INDEX.md
        ├── rules/
        └── profiles/
```

| Файл | Владелец | Назначение | Ручное редактирование |
| --- | --- | --- | --- |
| `AGENTS.md` | проект | Короткая автоматически обнаруживаемая точка входа | да |
| `.ai-rules/manifest.json` | проект | Выбранные revision, topics и profiles | да |
| `.ai-rules/lock.json` | sync | Точная установленная revision, состав и SHA-256 | нет |
| `.ai-rules/RULESET.md` | проект | Композиция и явные исключения | да |
| `.ai-rules/PROJECT_RULES.md` | проект | Уникальная специфика и маршрутизация проекта | да |
| `.ai-rules/upstream/` | синхронизация | Управляемый снимок выбранных общих правил и профилей | нет |

`upstream/INDEX.md` генерируется только из catalog и manifest, содержит назначение и условия чтения effective-набора и входит в lock/hash. Это карта навигации, а не дополнительный источник истины.

`.ai-rules/` целиком не является управляемой областью. Синхронизация записывает только `upstream/` и `lock.json`.

Несовпадение revision проекта и `HEAD` локального хаба само по себе не означает доступное обновление. Пользовательский CLI проверяет Git ancestry и различает более новый, более старый, расходящийся и недоступный checkout. Этот relation нужен только для безопасного объяснения направления перехода и не меняет checkout.

Целостность уже установленного снимка проверяется независимо: `doctor` вычисляет SHA-256 каждого файла по записи в `lock`. Для текстовых файлов окончания строк нормализуются в LF и контрольная сумма считается по UTF-8 без BOM; бинарные файлы проверяются обычным SHA-256. Поэтому отсутствие нужной `revision` в локальной копии не мешает обнаружить ручное изменение управляемой копии.

## Граница владения

- `Apply` копирует `add` и `update` только в `.ai-rules/upstream/`, затем при необходимости обновляет `.ai-rules/lock.json`.
- Корневой `AGENTS.md`, `.ai-rules/manifest.json`, `.ai-rules/RULESET.md` и `.ai-rules/PROJECT_RULES.md` принадлежат проекту.
- Изменённый вручную upstream-файл получает состояние `conflict`; `Apply` останавливается и не перезаписывает его.
- Исключённый из manifest upstream-файл получает состояние `orphan`, `orphan-modified` или `orphan-missing`. Версия `0.2` не удаляет orphan-файлы автоматически.
- `Plan` ничего не записывает.
- Повторный `Apply` при неизменном составе не переписывает upstream-файлы и lock.
- Каждый Markdown-файл темы из `rules/`, кроме `CORE.md` и `README.md`, регистрируется ровно одним topic ID в catalog.

## 1. Первичное подключение

Запусти из корня checkout хаба:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File scripts/init-project-sync.ps1 `
  -ProjectRoot C:\path\to\project `
  -Profiles standard-product `
  -SeedProjectFiles
```

Initializer:

- создаёт `.ai-rules/`;
- создаёт `.ai-rules/manifest.json` версии `0.2`;
- добавляет корневой `AGENTS.md`, только если его ещё нет;
- добавляет `.ai-rules/RULESET.md` и `.ai-rules/PROJECT_RULES.md`, только если их ещё нет;
- не создаёт `lock.json` и `upstream/`;
- не запускает `Apply`.

Заполни незаполненные места в локальных файлах. В `.ai-rules/RULESET.md` перечисли профиль, темы и исключения. В `.ai-rules/PROJECT_RULES.md` запиши только специфику проекта и относительные маршруты к его документации.

## 2. Plan

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File scripts/sync-rules.ps1 `
  -ProjectRoot C:\path\to\project `
  -Mode Plan
```

Проверь:

1. revision и `Hub dirty`;
2. manifest `.ai-rules/manifest.json`;
3. управляемый корень `.ai-rules/upstream`;
4. что `add` и `update` содержат только выбранные правила и профили;
5. отсутствие неожиданных `conflict`, `orphan` и `orphan-modified`;
6. соответствие manifest и `.ai-rules/RULESET.md`.

`Plan` не создаёт `lock.json`, `upstream/` и не меняет пользовательские файлы.

## 3. Apply

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File scripts/sync-rules.ps1 `
  -ProjectRoot C:\path\to\project `
  -Mode Apply
```

Низкоуровневый `Apply` работает только когда `source.revision` содержит полный SHA текущего commit, а checkout хаба чист. Незакреплённый manifest допускает только `Plan`; для первого применения используй корневой `update -Apply`, который явно закрепляет текущую revision.

Запись управляемых файлов и `lock.json` выполняется как одна локальная транзакция. Если одна из операций завершается ошибкой, синхронизация восстанавливает существовавшие файлы байт-в-байт, удаляет созданные этой попыткой файлы и пустые каталоги и возвращает ошибку. Аварийное завершение процесса или системы не считается успешно обработанной ошибкой и требует проверки diff перед повтором.

После выполнения:

1. просмотреть diff `.ai-rules/upstream/` и `.ai-rules/lock.json`;
2. убедиться, что корневой `AGENTS.md`, `.ai-rules/manifest.json`, `.ai-rules/RULESET.md` и `.ai-rules/PROJECT_RULES.md` не изменились;
3. выполнить проверки проекта;
4. зафиксировать обновление правил отдельным коммитом после явного разрешения владельца.

В проект коммитятся корневой `AGENTS.md`, вся `.ai-rules/` вместе с пользовательскими файлами, `lock` и снимком `upstream`, а также относящаяся к проекту документация. При этом владельцем `RULESET.md` и `PROJECT_RULES.md` остаётся проект, а не синхронизация.

## 4. Обычная работа

Хаб не нужен. Агент читает:

1. `.ai-rules/RULESET.md` по маршруту из корневого `AGENTS.md`;
2. `.ai-rules/PROJECT_RULES.md`;
3. `.ai-rules/upstream/CORE.md`;
4. `.ai-rules/upstream/INDEX.md`;
5. все выбранные профили из индекса;
6. только относящиеся к текущей задаче правила или процессы из индекса;
7. релевантные проектные документы, код и тесты.

Точный состав определяется manifest, lock и status, а условия чтения берутся из производного индекса. Не читать весь `upstream/` или все темы профиля перед каждой задачей. Общие правила не редактируются внутри проекта; проектная специфика меняется в `.ai-rules/PROJECT_RULES.md`, исключения — в `.ai-rules/RULESET.md`. После pinning отсутствие маршрута к `INDEX.md` делает подключение inconsistent.

Предварительный `update` из изменённой рабочей копии строит просмотр по рабочим файлам, а не только по снимку коммита, и явно сообщает базовый SHA `HEAD`. Такой результат нельзя применить: сначала нужно сохранить или отменить изменения хаба и повторить просмотр. `update -Apply` из изменённой рабочей копии остаётся запрещённым.

## 5. Обновление общих правил

1. Получи полный SHA выбранного commit хаба:

   ```powershell
   git -C C:\path\to\ai-rules-hub rev-parse HEAD
   ```

2. Запиши все 40 символов в `.ai-rules/manifest.json`:

   ```json
   "source": {
     "repository": "ai-rules-hub",
     "revision": "0123456789abcdef0123456789abcdef01234567"
   }
   ```

3. Переключи checkout хаба на этот commit. Для pinned `Apply` checkout должен быть чистым.
4. Запусти `Plan` и проверь таблицу действий.
5. Разреши `conflict` вручную и проверь orphan-файлы.
6. Запусти `Apply`.
7. Обнови композицию в `.ai-rules/RULESET.md`, если выбор изменился.
8. Просмотри diff и выполни проверки проекта.

`source.revision: null` допустим только для локальной подготовки и `Plan`. Любой `Apply` требует полный SHA и чистый checkout хаба.

## 6. Отмена обновления

Если обновление уже зафиксировано, откати его отдельный проектный commit штатным Git-процессом. До коммита можно:

1. вернуть предыдущий `source.revision` в `.ai-rules/manifest.json`;
2. переключить checkout хаба на этот commit;
3. проверить обратные `update` через `Plan`;
4. выполнить `Apply`;
5. проверить diff и тесты проекта.

## Lock-контракт `0.2`

`.ai-rules/lock.json` содержит:

- `schemaVersion: "0.2"`;
- время последнего фактического изменения lock;
- repository, полный revision, dirty-state и версию каталога;
- путь manifest `.ai-rules/manifest.json`;
- управляемый корень `.ai-rules/upstream`;
- итоговые topics и profiles;
- для каждого управляемого файла или файла в состоянии `orphan`: источник, путь назначения относительно проекта, нормализованный SHA-256 и состояние.

Запись `generated/effective-index` фиксирует производный `upstream/INDEX.md` наравне с копируемыми файлами.

Target вне `.ai-rules/upstream/` или путь через symlink, junction и другой reparse-point считается ошибкой lock-контракта. Хаб отклоняет такой путь до записи, потому что по PowerShell 5.1 не может надёжно доказать сохранение границы проекта.

## Состояния Plan

| Состояние | Значение | Действие пользователя |
| --- | --- | --- |
| `add` | Upstream-файла ещё нет | проверить намеренность выбора |
| `update` | Source изменился, target соответствует старому lock | просмотреть изменение |
| `unchanged` | Source и target совпадают | ничего |
| `conflict` | Upstream-файл изменён локально или появился без lock | разрешить вручную до `Apply` |
| `orphan` | Файл больше не выбран и не изменён | проверить ссылки; автоматического удаления нет |
| `orphan-modified` | Исключённый файл изменён локально | сохранить решение вручную |
| `orphan-missing` | Исключённый файл уже отсутствует | проверить ожидаемый состав |

## Старый формат `0.1`

До пилотного подключения реальные потребители `.ai-rules-hub.json` и `.ai-rules-hub.lock.json` не обнаружены. Версия `0.2` не поддерживает два параллельных формата и не выполняет молчаливую миграцию.

Если старые файлы всё же появятся, initializer остановится при обнаружении `.ai-rules-hub.json` или `.ai-rules-hub.lock.json`, а sync потребует `.ai-rules/manifest.json`. Перенос пользовательских `RULESET.md` и `PROJECT_RULES.md` должен выполняться отдельным явным изменением после просмотра их содержимого.

Версия `0.2` не выполняет удалённую загрузку, массовое обновление проектов, автоматическое объединение конфликтов и автоматическое удаление файлов в состоянии `orphan`.

## Перенос `project-study` в workflows

Идентификатор manifest `project-study` сохранён для совместимости версии `0.2`, но его source перемещён из `rules/PROJECT_STUDY.md` в `workflows/PROJECT_STUDY.md`. Для ранее подключённого проекта следующий Plan показывает новый `.ai-rules/upstream/workflows/PROJECT_STUDY.md` как `add`, а старый `.ai-rules/upstream/rules/PROJECT_STUDY.md` как `orphan` или `orphan-modified`.

Apply не удаляет старый файл и не меняет project-owned `AGENTS.md`. Сначала проверь новый workflow, затем явно обнови локальный маршрут на `.ai-rules/upstream/workflows/PROJECT_STUDY.md`. Старый orphan можно удалить вручную только после проверки входящих ссылок и отдельного разрешения владельца. Команды `prompt connect` и `prompt audit` сохраняют прежний CLI-контракт; прямые канонические файлы теперь находятся в каталоге `workflows/` хаба.
