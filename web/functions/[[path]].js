// Cloudflare Pages Function — server-rendered OG/social meta tags for public
// church & bookshop websites AND shared content (WhatsApp/Telegram/Facebook
// link previews + SEO).
//
// Handles:
//   /church/<churchId>    -> church_websites.church_id = <churchId>
//   /site/<tenantId>      -> church_websites.tenant_id = <tenantId>
//   /c/<slug>             -> church_websites.slug = <slug>
//   /sermon/<id>          -> sermons
//   /events/<id>          -> events
//   /posts/<id>           -> social_posts
//   /jobs/<id>            -> jobs
//   /klips/<id>           -> klips
//
// Requires project env vars (set once in the Cloudflare Pages dashboard or via
// `wrangler pages secret bulk`): SUPABASE_URL, SUPABASE_ANON_KEY.
// Without them the function still serves the page (no meta injection).

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

async function supa(env, path) {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return null;
  try {
    const res = await fetch(`${env.SUPABASE_URL}/rest/v1/${path}`, {
      headers: {
        apikey: env.SUPABASE_ANON_KEY,
        Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      },
    });
    if (!res.ok) return null;
    const rows = await res.json();
    return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
  } catch {
    return null;
  }
}

async function fetchWebsite(env, pathname) {
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
  return supa(
    env,
    `church_websites?select=title,subtitle,about_text,banner_url,logo_url,slug&${filter}&limit=1`,
  );
}

// ── Shared-content previews ─────────────────────────────────────────────────
const ENTITY_TABLES = {
  sermon: { table: 'sermons', type: 'article', typeLabel: 'Sermon' },
  events: { table: 'events', type: 'article', typeLabel: 'Event' },
  posts: { table: 'social_posts', type: 'article', typeLabel: 'Post' },
  jobs: { table: 'jobs', type: 'website', typeLabel: 'Job' },
  klips: { table: 'klips', type: 'video.other', typeLabel: 'Klip' },
};

function entitySpec(pathname) {
  const path = pathname.replace(/\/+$/, '');
  const m = /^\/(sermon|events|posts|jobs|klips)\/([A-Za-z0-9_-]{6,64})$/.exec(path);
  if (!m) return null;
  return { ...ENTITY_TABLES[m[1]], id: m[2] };
}

function pickText(row, keys) {
  for (const k of keys) {
    const v = row?.[k];
    if (typeof v === 'string' && v.trim()) return v.trim();
  }
  return '';
}

async function fetchEntity(env, spec) {
  return supa(env, `${spec.table}?select=*&id=eq.${encodeURIComponent(spec.id)}&limit=1`);
}

async function resolveMeta(env, pathname, isWebsitePath, spec) {
  let title = 'Church On App';
  let description =
    'Churches & bookshops on the Church On App platform — giving, events, sermons, radio & more.';
  let image = '';
  let ogType = 'website';

  if (isWebsitePath) {
    const website = await fetchWebsite(env, pathname);
    if (website) {
      title = website.title || title;
      description = (website.about_text || website.subtitle || '').slice(0, 160) || description;
      image = website.banner_url || website.logo_url || '';
    }
    return { title, description, image, ogType };
  }

  if (spec) {
    const row = await fetchEntity(env, spec);
    if (row) {
      const t = pickText(row, ['title', 'name', 'headline']);
      const d = pickText(row, [
        'description', 'excerpt', 'body', 'content', 'summary', 'subtitle', 'preacher',
      ]);
      const img =
        pickText(row, [
          'image_url', 'thumbnail_url', 'media_url', 'banner_url', 'banner', 'image', 'logo_url',
        ]) || (Array.isArray(row.images) && typeof row.images[0] === 'string' ? row.images[0] : '');
      if (t) title = `${t} · ${spec.typeLabel}`;
      if (d) description = d.slice(0, 160);
      if (img) image = img;
      ogType = spec.type;
    }
  }

  return { title, description, image, ogType };
}

export async function onRequest(context) {
  const { request, env, next } = context;
  const url = new URL(request.url);
  const pathname = url.pathname;

  const isWebsitePath =
    pathname.startsWith('/church/') ||
    pathname.startsWith('/site/') ||
    pathname.startsWith('/c/');
  const spec = entitySpec(pathname);

  if (!isWebsitePath && !spec) {
    return next();
  }

  // Serve the SPA first; we inject meta by transforming its HTML.
  const response = await next();
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.includes('text/html')) {
    return response;
  }

  const { title, description, image, ogType } = await resolveMeta(
    env,
    pathname,
    isWebsitePath,
    spec,
  );

  const html = await response.text();
  const tags = [
    ['og:title', title],
    ['og:description', description],
    ['og:site_name', 'Church On App'],
    ['og:type', ogType],
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
    `<title>${escapeHtml(title)}</title>`,
  );

  return new Response(transformed, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      'content-type': 'text/html; charset=utf-8',
    },
  });
}
