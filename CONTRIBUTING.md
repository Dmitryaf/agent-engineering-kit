# Участие в развитии Agent Engineering Kit

Agent Engineering Kit развивается под управлением владельца: внешние задачи и запросы на слияние приветствуются как предложения, но окончательное решение о направлениях развития и составе правил принимает владелец.

Перед предложением изменения прочитайте подробное руководство [`hub/CONTRIBUTING.md`](hub/CONTRIBUTING.md). Не публикуйте секреты, личный или внутренний контекст и материалы без подтверждённого права распространения.

## Локальная проверка

Требуются Git и Windows PowerShell 5.1 или PowerShell 7+ на Windows. Из корня чистого clone выполните:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/check-hub.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test-tooling.ps1
git diff --check
git status --short
```

Участвуя в проекте, учитывайте условия [MIT License](LICENSE): copyright и license notice должны сохраняться в копиях и существенных частях материалов.
