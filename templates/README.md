# Шаблоны проекта

Обычному пользователю не нужно выбирать или копировать шаблоны вручную. Начните с команды:

```powershell
.\ai-rules.ps1 prompt connect -ProjectRoot C:\path\to\project
```

Во время подключения хаб добавит только отсутствующие файлы:

- [`AGENTS.md`](AGENTS.md) — короткая точка входа для агента;
- [`RULESET.md`](RULESET.md) — выбранные правила, причины выбора и исключения;
- [`PROJECT_RULES.md`](PROJECT_RULES.md) — особенности проекта и команды проверки.

Существующие файлы не перезаписываются. Если проект уже содержит `AGENTS.md`, агент объединит с ним только нужные маршруты.

Готовые запросы находятся отдельно:

- [`PROJECT_CONNECT_PROMPT.md`](../workflows/PROJECT_CONNECT_PROMPT.md) — подключение проекта;
- [`PROJECT_AUDIT_PROMPT.md`](../workflows/PROJECT_AUDIT_PROMPT.md) — завершение подключения и первичная проверка;
- [`PROJECT_DEEP_AUDIT_PROMPT.md`](../workflows/PROJECT_DEEP_AUDIT_PROMPT.md) — подключение и запуск глубокого аудита;
- [`PROJECT_STUDY_PROMPT.md`](../workflows/PROJECT_STUDY_PROMPT.md) — подключение и начало изучения проекта через `ai-rules.ps1 prompt study -ProjectRoot <путь>`.

После подключения общие правила находятся в `.ai-rules/upstream/`. Локальные `RULESET.md` и `PROJECT_RULES.md` остаются под управлением проекта.

## Расширенные шаблоны

Используйте их только когда проекту действительно нужна дополнительная структура:

- [`PROJECT_RULES.full.md`](PROJECT_RULES.full.md) — подробная карта правил проекта;
- [`PRODUCT.md`](PRODUCT.md) — описание продукта;
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — описание архитектуры;
- [`DECISION.md`](DECISION.md) — отдельное значимое решение;
- [`DECISIONS.md`](DECISIONS.md) — карта значимых решений, если у проекта ещё нет подходящего указателя;
- [`RESEARCH.md`](RESEARCH.md) — проверяемое исследование;
- [`PROJECT_KNOWLEDGE.md`](PROJECT_KNOWLEDGE.md) — устойчивые знания о проекте;
- [`SESSION_CONTEXT.md`](SESSION_CONTEXT.md) — временная передача контекста.

Не создавайте документ только потому, что существует шаблон. Сначала определите читателя, задачу документа и место хранения.

Низкоуровневые команды описаны в [`sync/README.md`](../sync/README.md).
