-- ═══════════════════════════════════════════════════════════════════════════════
-- PUBLIC DOMAIN ENGLISH BIBLE VERSIONS
-- All approved, freely distributable translations (1911 or earlier,
-- or explicitly placed in public domain by the translator/publisher).
-- NOTE: The Message (MSG), ESV, NIV, NASB, AMP, CSB are COPYRIGHTED
-- and NOT included here.
-- ═══════════════════════════════════════════════════════════════════════════════

INSERT INTO public.bible_translations (code, name, full_name, language_code, is_public_domain, copyright_info)
VALUES
  ('web',  'World English Bible',        'World English Bible',            'en', true, 'Public domain — freely distributable (WEB translation by Michael Paul Johnson)'),
  ('asv',  'American Standard Version',  'American Standard Version 1901', 'en', true, 'Public domain — copyright expired 1901'),
  ('darby','Darby Translation',          'Darby Bible — J.N. Darby',       'en', true, 'Public domain — J.N. Darby 1890'),
  ('ylt',  'Young''s Literal Translation','Young''s Literal Translation',  'en', true, 'Public domain — Robert Young 1898'),
  ('bbe',  'Bible in Basic English',     'Bible in Basic English',         'en', true, 'Public domain — Prof. S.H. Hooke 1949, UC Crown copyright expired'),
  ('drb',  'Douay-Rheims Bible',         'Douay-Rheims Challoner 1752',    'en', true, 'Public domain — 1582/1609/1752')
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  full_name = EXCLUDED.full_name,
  is_public_domain = EXCLUDED.is_public_domain,
  copyright_info = EXCLUDED.copyright_info;

-- Add translations for non-public-domain but commonly approved by church bodies
-- These are marked is_public_domain=false and rely on the API's fair-use provisions.
INSERT INTO public.bible_translations (code, name, full_name, language_code, is_public_domain, copyright_info)
VALUES
  ('ESV',  'English Standard Version',   'English Standard Version (ESV)', 'en', false, '© Crossway — API fair-use for reading/study'),
  ('NIV',  'New International Version',  'New International Version',      'en', false, '© Zondervan/Biblica — API fair-use for reading'),
  ('NASB', 'New American Standard Bible', 'New American Standard Bible',   'en', false, '© Lockman Foundation — API fair-use')
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  full_name = EXCLUDED.full_name,
  is_public_domain = EXCLUDED.is_public_domain,
  copyright_info = EXCLUDED.copyright_info;
