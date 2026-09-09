# Шаблоны подключённого проекта

## Обычное использование

Из корня checkout хаба выполните:

```powershell
.\ai-rules.ps1 prompt connect -ProjectRoot C:\path\to\project
```

Самый простой путь — получить готовый запрос командой `.\ai-rules.ps1 prompt connect -ProjectRoot C:\path\to\project` и передать его AI-агенту. Он подберёт минимальный набор, выполнит `connect` для подготовки и preview, остановится перед `-Apply`, а после разрешения проверит результат. Канонический запрос хранится в [`../workflows/PROJECT_CONNECT_PROMPT.md`](../workflows/PROJECT_CONNECT_PROMPT.md).

CLI создаст отсутствующие `AGENTS.md`, `.ai-rules/RULESET.md` и `.ai-rules/PROJECT_RULES.md`, но не перезапишет существующие файлы. После подключения запрос `.\ai-rules.ps1 prompt audit` помогает завершить локальный слой и провести отдельный аудит без исправления проекта; общие правила вручную переносить не нужно. Канонический запрос хранится в [`../workflows/PROJECT_AUDIT_PROMPT.md`](../workflows/PROJECT_AUDIT_PROMPT.md). Полный пользовательский сценарий находится в корневом [`README.md`](../README.md).

При подключении существующего проекта шаблоны описывают фактическое состояние: ссылка ведёт только к реально существующему источнику, отсутствующий источник отмечается `не установлен`, а неизвестная проверка — `не установлена`. Не создавайте документацию, инструменты или CI ради заполнения шаблона и не устраняйте найденные разрывы в рамках подключения; запишите их в `RULESET.md` для отдельного решения владельца.

Управляемые правила и сгенерированная карта чтения `INDEX.md` находятся только в `.ai-rules/upstream/`; `.ai-rules/RULESET.md` и `.ai-rules/PROJECT_RULES.md` принадлежат проекту и не перезаписываются синхронизацией. Подмодуль Git, удалённая загрузка и автоматическое массовое внедрение пока не используются.

## Рекомендуемый набор документов

| Шаблон | Когда нужен |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) | всегда |
| [`RULESET.md`](RULESET.md) → `.ai-rules/RULESET.md` | всегда |
| [`PROJECT_RULES.md`](PROJECT_RULES.md) → `.ai-rules/PROJECT_RULES.md` | всегда |
| [`PROJECT_RULES.full.md`](PROJECT_RULES.full.md) | расширенная замена минимального project rules, когда реально нужны подробные источники истины и маршрутизация |
| [`PRODUCT.md`](PRODUCT.md) | пользовательский продукт |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | проект с устойчивыми техническими границами |
| [`PROJECT_KNOWLEDGE.md`](PROJECT_KNOWLEDGE.md) | длительный проект с частыми паузами/сессиями |
| [`SESSION_CONTEXT.md`](SESSION_CONTEXT.md) | активная незавершённая работа |
| [`DECISION.md`](DECISION.md) | значимое решение с альтернативами |
| [`RESEARCH.md`](RESEARCH.md) | короткое исследование, аудит, неизвестный API или выбор на основе подтверждений |

Не создавать все документы заранее. Каждый файл должен иметь владельца вопроса и реальную функцию.

Шаблон не определяет публичность результата. Внутренний или личный документ размещается в принятом локальном либо закрытом пространстве проекта и не добавляется в Git только из-за наличия шаблона в хабе.

## Низкоуровневое использование

Для отладки или интеграции initializer можно вызвать напрямую:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File scripts/init-project-sync.ps1 `
  -ProjectRoot C:\path\to\project `
  -Profiles standard-product `
  -SeedProjectFiles
```

Manifest также можно создать вручную по [`../sync/project-manifest.example.json`](../sync/project-manifest.example.json). После этого применяются низкоуровневые `Plan`/`Apply` из [`../sync/README.md`](../sync/README.md). Этот путь не заменяет пользовательский CLI и требует самостоятельной проверки revision и файлов проекта.
