# SpacePin Localization Coverage

SpacePin now ships with runtime UI localizations for the following locales:

| Locale | Language |
| --- | --- |
| `en` | English |
| `ja` | Japanese |
| `fr` | French |
| `de` | German |
| `es` | Spanish |
| `pt-BR` | Brazilian Portuguese |
| `ru` | Russian |
| `ar` | Arabic |
| `tr` | Turkish |
| `ko` | Korean |
| `zh-Hans` | Chinese (Simplified) |
| `zh-Hant` | Chinese (Traditional) |
| `hi` | Hindi |
| `id` | Indonesian |
| `th` | Thai |
| `vi` | Vietnamese |
| `uk` | Ukrainian |
| `ms` | Malay |

## Runtime Fallback Rules

1. Exact locale matches are preferred when available.
2. `zh-*` storefronts fall back to `zh-Hans` or `zh-Hant` depending on script or region.
3. `pt-*` storefronts fall back to `pt-BR`.
4. All other unsupported locales fall back to `en`.

## Distribution Coverage Note

The currently configured shipping countries span the Americas, Europe, the Middle East, Africa, Central Asia, and Asia-Pacific storefronts. The locale set above covers the largest storefront language groups directly, while unsupported storefront languages fall back to English instead of exposing raw keys or mixed-language UI.

## App Store Metadata

Localized App Store copy drafts for the same locale set live in [app-store-metadata-localizations.json](app-store-metadata-localizations.json).
