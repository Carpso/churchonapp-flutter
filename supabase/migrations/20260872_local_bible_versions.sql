-- ═══════════════════════════════════════════════════════════════════════════════
-- ZAMBIAN & ZIMBABWEAN BIBLE VERSIONS
-- Adds local-language Bible translations. Verses are fetched on-demand
-- via getBible.net API (free, open-source text) when not available in the
-- local seed data. KJV/NKJV/NLT already seeded.
-- ═══════════════════════════════════════════════════════════════════════════════

INSERT INTO public.bible_translations (code, name, full_name, language_code, is_public_domain, copyright_info)
VALUES
  ('bem',   'Bemba Bible',       'Bemba Bible — Baibelo',                  'bem', true, 'Open source text via getBible.net'),
  ('nya',   'Nyanja / Chewa',    'Buku Loyera — Chichewa Bible',            'nya', true, 'Open source text via getBible.net'),
  ('sna',   'Shona Bible',       'Bhaibheri Dzvene — Shona Bible',         'sna', true, 'Open source text via getBible.net'),
  ('toi',   'Tonga Bible',       'Bbuku Lya Mizezo — Zambian Tonga Bible', 'toi', true, 'Open source text via getBible.net'),
  ('loz',   'Lozi Bible',        'Bibele — Lozi Bible',                    'loz', true, 'Open source text via getBible.net'),
  ('nde',   'Ndebele Bible',     'IBhayibhili — Ndebele Bible',            'nde', true, 'Open source text via getBible.net')
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  full_name = EXCLUDED.full_name,
  is_public_domain = EXCLUDED.is_public_domain,
  copyright_info = EXCLUDED.copyright_info;
