# Vendored page runtime

`support.js` loads these from unpkg. The Mac app has no network, so they are bundled and
handed to `support.js` through its own `window.__resources` hook (URL → local src). The
page files themselves stay byte-identical.

Each file matches the SRI hash pinned in `support.js` (`src/cdn.ts`), checked 2026-09-28:

| File | Source | SRI |
|---|---|---|
| `react.production.min.js` | `react@18.3.1/umd/` | `sha384-DGyLxAyjq0f9SPpVevD6IgztCFlnMF6oW/XQGmfe+IsZ8TqEiDrcHkMLKI6fiB/Z` |
| `react-dom.production.min.js` | `react-dom@18.3.1/umd/` | `sha384-gTGxhz21lVGYNMcdJOyq01Edg0jhn/c22nsx0kyqP0TxaV5WVdsSH1fSDUf5YJj1` |
| `babel.min.js` | `@babel/standalone@7.29.0/` | `sha384-m08KidiNqLdpJqLq95G/LEi8Qvjl/xUYll3QILypMoQ65QorJ9Lvtp2RXYGBFj1y` |

Re-check after any update:

```bash
for f in design/handoff/vendor/*.js; do echo "$f sha384-$(openssl dgst -sha384 -binary "$f" | base64)"; done
```
