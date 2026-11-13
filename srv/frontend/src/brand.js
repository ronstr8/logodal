// Brand ("skin") resolution.
//
// One deployment serves several brands from a single game pool; the brand only
// changes presentation (theme tokens in theme.css, logo, title, copy). It is
// resolved from the hostname *before* React renders, so even the login screen
// is skinned correctly without waiting for the WebSocket identity message.
//
// Resolution order:
//   1. ?brand=<name> query param (remembered for the tab; handy on localhost)
//   2. Exact host match in runtime config BRAND_HOSTS (ignoring a leading www.)
//   3. A known brand appearing as a DNS label (wordwank.localhost, ...)
//   4. DEFAULT_BRAND

export const BRANDS = {
    logodal: {
        name: 'Logodal',
        themeColor: '#0e0906',
        favicon: null, // index.html defaults are Logodal's
        fonts: null,   // index.html already loads Logodal's fonts
    },
    wordwank: {
        name: 'Wordwank',
        themeColor: '#2c3e50',
        favicon: '/brands/wordwank/favicon',
        manifest: '/brands/wordwank/site.webmanifest',
        fonts: 'https://fonts.googleapis.com/css2?family=Fredoka:wght@300..700&family=Luckiest+Guy&display=swap',
    },
};

const runtime = (typeof window !== 'undefined' && window.LOGODAL_CONFIG) || {};
const DEFAULT_BRAND = BRANDS[runtime.DEFAULT_BRAND] ? runtime.DEFAULT_BRAND : 'logodal';
const STORAGE_KEY = 'brand-override';

function fromQuery() {
    try {
        const q = new URLSearchParams(window.location.search).get('brand');
        if (q && BRANDS[q]) {
            sessionStorage.setItem(STORAGE_KEY, q);
            return q;
        }
        const saved = sessionStorage.getItem(STORAGE_KEY);
        return saved && BRANDS[saved] ? saved : null;
    } catch {
        return null; // storage blocked; query-only
    }
}

export function resolveBrand(hostname = window.location.hostname) {
    const override = fromQuery();
    if (override) return override;

    const host = (hostname || '').toLowerCase().replace(/^www\./, '');
    const mapped = (runtime.BRAND_HOSTS || {})[host];
    if (mapped && BRANDS[mapped]) return mapped;

    const labels = new Set(host.split('.'));
    const byLabel = Object.keys(BRANDS).find((b) => labels.has(b));
    return byLabel || DEFAULT_BRAND;
}

function setLink(rel, href, extra = {}) {
    let el = document.head.querySelector(`link[rel="${rel}"]${extra.type ? `[type="${extra.type}"]` : ''}`);
    if (!el) {
        el = document.createElement('link');
        el.rel = rel;
        Object.assign(el, extra);
        document.head.appendChild(el);
    }
    el.href = href;
}

// Apply document-level brand side effects: data-brand (drives theme.css),
// title, theme-color, favicon, and any brand-specific web fonts.
export function applyBrand(brand) {
    const b = BRANDS[brand] || BRANDS[DEFAULT_BRAND];
    const root = document.documentElement;
    root.dataset.brand = brand;
    document.title = b.name;

    const meta = document.head.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = b.themeColor;

    if (b.favicon) {
        setLink('icon', `${b.favicon}/favicon.svg`, { type: 'image/svg+xml' });
        setLink('icon', `${b.favicon}/favicon-96x96.png`, { type: 'image/png' });
        setLink('shortcut icon', `${b.favicon}/favicon.ico`);
        setLink('apple-touch-icon', `${b.favicon}/apple-touch-icon.png`);
    }
    if (b.manifest) setLink('manifest', b.manifest);
    if (b.fonts) {
        // Appended rather than replacing index.html's font sheet.
        const el = document.createElement('link');
        el.rel = 'stylesheet';
        el.href = b.fonts;
        document.head.appendChild(el);
    }
}

export const BRAND = resolveBrand();
export const BRAND_INFO = BRANDS[BRAND];
