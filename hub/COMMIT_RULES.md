# Правила коммитов Agent Engineering Kit

## Формат

Каждый обычный коммит использует соглашение Conventional Commits с обязательной областью `scope`:

```text
<type>(<scope>): <summary>
```

Несовместимое изменение отмечается знаком `!`:

```text
feat(sync)!: change the lock-file format
```

## Допустимые type

- `feat` — новая возможность хаба или синхронизации;
- `fix` — исправление ошибочного поведения;
- `docs` — только документация;
- `test` — тесты без изменения production-поведения;
- `refactor` — изменение структуры без изменения поведения;
- `perf` — измеримое улучшение производительности;
- `build` — зависимости и сборочная инфраструктура;
- `ci` — automation CI/CD;
- `chore` — обслуживание без изменения продукта;
- `revert` — явный откат.

## Допустимые области `scope`

- `core`, `product`, `architecture`, `data`, `quality`, `security`;
- `docs`, `git`, `ai`, `research`;
- `profiles`, `templates`, `sync`, `hub`, `sources`, `tooling`.

`Scope` описывает логический результат, а не случайное имя файла. Если изменение затрагивает несколько файлов одного сценария синхронизации, используется `sync`, а не перечень каталогов.

## Summary и body

- Summary и body пишутся на английском.
- Header не длиннее 72 символов.
- Summary не заканчивается точкой и не содержит пробелы по краям.
- После header перед body находится пустая строка.
- Строка body/footer не длиннее 100 символов.
- Body объясняет причину, ограничение или migration impact, а не повторяет diff.

Примеры:

```text
docs(core): clarify evidence rules
feat(sync): add safe managed-file updates
test(tooling): verify local change conflicts
ci(hub): validate structure in pull requests
```

## Границы коммита

- Один коммит — один проверяемый результат.
- Тесты поведения входят в тот же коммит.
- Очистка публичной поверхности не смешивается с содержательным изменением нормативных правил без общей причины.
- Изменение инструментов коммита не смешивается с будущим продуктовым правилом.
- Перед staging составляется карта коммитов, затем проверяются staged stat, diff и `--check`.

Commit, staging и push по-прежнему выполняются только после отдельного разрешения владельца.

## Автоматическая проверка

Репозиторный hook вызывает [`../scripts/validate-commit-message.ps1`](../scripts/validate-commit-message.ps1). Установка для текущего clone:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/install-git-hooks.ps1
```

Hook разрешает служебные сообщения Git `Merge ...`, `Revert "..."`, а также `fixup!` и `squash!`, если вложенный header сам проходит правила.
