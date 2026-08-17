// Cloudflare Pages Function — server-rendered OG/social meta tags for public
// church & bookshop websites (WhatsApp/Telegram/Facebook link previews + SEO).
//
// Handles:
//   /church/<churchId>    -> church_websites.church_id = <churchId>
//   /site/<tenantId>      -> church_websites.tenant_id = <tenantId>
//   /c/<slug>             -> church_websites.slug = <slug>
//
// Requires project env vars (set once in the Cloudflare Pages dashboard or via
// `wrangler pages secret bulk`): SUPABASE_URL, SUPABASE_ANON_KEY.
// Without them the function still serves the page (no meta injection).

const META_KEYS = [
  'og:title',
  'og:description',
  'og:image',
  'og:type',
  'og:url',
  'og:site_name',
  'twitter:card',
  'twitter:title',
  'twitter:description',
  'twitter:image',
];

function injectMeta(html, tags) {
  let out = html;
  for (const [key, value] of tags) {
    const encoded = String(value)
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    const property = key.startsWith('og:') ? 'property' : 'name';
    const meta = `<meta ${property}="${key}" content="${encoded}">`;
    if (out.includes(`property="${key}"`)) {
      out = out.replace(new RegExp(`<meta[^>]*property="${key}"[^>]*>`), meta);
    } else if (out.includes(`name="${key}"`)) {
      out = out.replace(new RegExp(`<meta[^>]*name="${key}"[^>]*>`), meta);
    } else {
      out = out.replace('</head>', `${meta}\n</head>`);
    }
  }
  return out;
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

async function fetchWebsite(supabaseUrl, anonKey, pathname) {
  const path = pathname.replace(/\/+$/, '');
  let filter = '';
  if (path.startsWith('/church/')) {
    const id = path.slice('/church/'.length);
    if (!/^[0-9a-fA-F-]{20,}$/.test(id)) return null;
    filter = `church_id=eq.${id}`;
  } else if (path.startsWith('/site/')) {
    const id = path.slice('/site/'.length);
    filter = `tenant_id=eq.${id}`;
  } else if (path.startsWith('/c/')) {
    const slug = path.slice('/c/'.length);
    if (!/^[a-z0-9-]{2,120}$/.test(slug)) return null;
    filter = `slug=eq.${slug}`;
  } else {
    return null;
  }

  const url = `${supabaseUrl}/rest/v1/church_websites?select=title,subtitle,about_text,banner_url,logo_url,slug&${filter}&limit=1`;
  const res = await fetch(url, {
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
    },
  });
  if (!res.ok) return null;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

export async function onRequest(context) {
  const { request, env, next } = context;
  const url = new URL(request.url);
  const pathname = url.pathname;

  const isWebsitePath =
    pathname.startsWith('/church/') ||
    pathname.startsWith('/site/') ||
    pathname.startsWith('/c/');

  if (!isWebsitePath) {
    return next();
  }

  // Serve the SPA first; we inject meta by transforming its HTML.
  const response = await next();
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.includes('text/html')) {
    return response;
  }

  let website = null;
  if (env.SUPABASE_URL && env.SUPABASE_ANON_KEY) {
    try {
      website = await fetchWebsite(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, pathname);
    } catch (e) {
      website = null;
    }
  }

  const title = website ? escapeHtml(website.title) : 'Church On App';
  const description = website
    ? escapeHtml((website.about_text || website.subtitle || '').slice(0, 160))
    : 'Churches & bookshops on the Church On App platform — giving, events, sermons, radio & more.';
  const image = website ? website.banner_url || website.logo_url : '';
  const siteName = 'Church On App';

  const html = await response.text();
  const tags = [
    ['og:title', title],
    ['og:description', description],
    ['og:site_name', siteName],
    ['og:type', 'website'],
    ['og:url', url.origin + pathname],
    ['twitter:card', image ? 'summary_large_image' : 'summary'],
    ['twitter:title', title],
    ['twitter:description', description],
  ];
  if (image) {
    tags.push(['og:image', escapeHtml(image)]);
    tags.push(['twitter:image', escapeHtml(image)]);
  }

  const transformed = injectMeta(html, tags).replace(
    /<title>[^<]*<\/title>/,
    `<title>${title}</title>`,
  );

  return new Response(transformed, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      'content-type': 'text/html; charset=utf-8',
    },
  });
}