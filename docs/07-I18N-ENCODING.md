# I18N And Encoding

## Language Rules

- Default display language is Thai.
- English is secondary.
- New code identifiers, comments, and internal keys must be English.
- User-facing text should use `I18N.th` and `I18N.en` where practical.

## Current System

- `currentLang = localStorage.getItem("juristicLang") || "th"`
- `t(key, vars)` reads dictionary text.
- Static DOM should use `data-i18n`.
- Dynamic render text should call `t()` or use structured `{ th, en }` values.

## Encoding Rules

- All project text files must stay UTF-8.
- Avoid PowerShell rewrite pipelines for files containing Thai text.
- Watch for mojibake markers: `â`, `Ã`, `Â`, `à¸`, `à¹`, `�`.

## Technical Debt

Some dynamic strings in `app.js`, `profiles.js`, and SQL comments are still inline Thai/English ternaries. Future refactors should move them to `I18N`.
