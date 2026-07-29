# Audio Bible Generation Guide

This guide covers generating audio Bible files for all 66 books using the Church On App tooling.

## Architecture Overview

```
┌─────────────────────┐     ┌──────────────────────┐     ┌──────────────────┐
│  Bible Text (Supabase)  │────▶│  AudioBibleGenerator   │────▶│  Audio Files     │
│  (bible_verses table)   │     │  (Dart desktop tool)   │     │  (Supabase/R2)   │
└─────────────────────┘     └──────────────────────┘     └──────────────────┘
                                  │
                                  ▼
                         ┌──────────────────────┐
                         │  TTS Engine          │
                         │  (flutter_tts - uses │
                         │   platform TTS)      │
                         └──────────────────────┘
```

## Prerequisites

1. **Supabase Project** with migrations applied:
   ```bash
   # Apply the Bible text storage migration
   supabase db push
   ```

2. **Bible Text Data** populated (run once):
   ```bash
   python tools/seed_bible_text.py \
     --supabase-url $SUPABASE_URL \
     --supabase-key $SERVICE_KEY \
     --translation web
   ```

3. **Desktop Environment** (Windows/Mac/Linux) for audio generation:
   - `flutter_tts` uses platform TTS (SAPI5 on Windows, NSSpeechSynthesizer on macOS, Speech Dispatcher on Linux)
   - Quality depends on installed system voices

4. **Storage Buckets** created in Supabase:
   ```sql
   -- In Supabase Dashboard > Storage > Create bucket
   -- Name: bible-audio, Public: true
   ```

## Step 1: Seed Bible Text

```bash
# Using Python seeder (fetches WEB from GitHub)
python tools/seed_bible_text.py \
  --supabase-url https://your-project.supabase.co \
  --supabase-key $SUPABASE_SERVICE_ROLE_KEY \
  --translation web

# Options:
#   --force          Re-fetch even if verses exist
#   --only-book "Genesis"  Seed single book
#   --dry-run        Preview without writing
```

## Step 2: Generate Audio Files

```bash
# Basic usage (all 66 books)
dart run tools/generate_audio_bible.dart \
  --supabase-url https://your-project.supabase.co \
  --supabase-key $SUPABASE_SERVICE_ROLE_KEY

# With R2 fallback for large files
dart run tools/generate_audio_bible.dart \
  --supabase-url https://your-project.supabase.co \
  --supabase-key $SUPABASE_SERVICE_ROLE_KEY \
  --use-r2-fallback \
  --r2-endpoint https://your-account.r2.cloudflarestorage.com \
  --r2-access-key $R2_ACCESS_KEY \
  --r2-secret-key $R2_SECRET_KEY \
  --r2-bucket churchonapp-bible-audio

# Single book for testing
dart run tools/generate_audio_bible.dart \
  --supabase-url https://your-project.supabase.co \
  --supabase-key $SUPABASE_SERVICE_ROLE_KEY \
  --book "Genesis" \
  --start-chapter 1 \
  --end-chapter 3

# Custom voice and speed
dart run tools/generate_audio_bible.dart \
  --supabase-url https://your-project.supabase.co \
  --supabase-key $SUPABASE_SERVICE_ROLE_KEY \
  --voice "en-GB-Wavenet-A" \
  --rate 0.4 \
  --format mp3
```

### Command Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--supabase-url` | `-u` | Supabase project URL | Required |
| `--supabase-key` | `-k` | Service role key | Required |
| `--translation` | `-t` | Bible translation (web, kjv) | `web` |
| `--voice` | `-v` | TTS voice name | `en-US-Standard-A` |
| `--rate` | `-r` | Speech rate (0.0-1.0) | `0.5` |
| `--format` | `-f` | Audio format (mp3, wav) | `mp3` |
| `--bucket` | `-b` | Supabase storage bucket | `bible-audio` |
| `--skip-existing` | `-s` | Skip already generated | `true` |
| `--book` | | Process single book | All 66 |
| `--start-chapter` | | Start chapter (with --book) | 1 |
| `--end-chapter` | | End chapter (with --book) | Last |
| `--use-r2-fallback` | | Enable R2 fallback | `false` |
| `--r2-endpoint` | | R2/S3 endpoint URL | - |
| `--r2-access-key` | | R2 access key ID | - |
| `--r2-secret-key` | | R2 secret access key | - |
| `--r2-bucket` | | R2 bucket name | - |
| `--r2-region` | | R2 region | `auto` |

## Step 3: Verify Generation

```bash
# Check database records
supabase db shell -c "
  SELECT b.name, COUNT(a.*) as chapters, SUM(a.file_size_bytes) as total_bytes
  FROM bible_audio_files a
  JOIN bible_books b ON a.book_id = b.id
  GROUP BY b.name
  ORDER BY b.book_order;
"

# List storage files
supabase storage ls bible-audio --recursive
```

## Storage Estimates

| Translation | Books | Chapters | Verses | Est. Duration | Est. Size (64kbps MP3) |
|-------------|-------|----------|--------|---------------|------------------------|
| WEB | 66 | 1,189 | 31,102 | ~75 hours | ~3.5 GB |
| KJV | 66 | 1,189 | 31,102 | ~78 hours | ~3.7 GB |

## TTS Voice Quality

| Platform | Best Voices |
|----------|-------------|
| Windows | Microsoft David/Zira (built-in), Azure Neural voices |
| macOS | Samantha, Alex, Siri voices (system) |
| Linux | eSpeak-NG, Festival, or Piper (install separately) |

**For production quality**, consider:
- **Google Cloud TTS** / **AWS Polly** / **Azure Speech** (cloud, paid, best quality)
- **Piper TTS** (local, free, good quality, supports many languages)
- **Coqui TTS** (local, free, multi-speaker)

## Database Schema Reference

```sql
-- Core tables (created by migration 20260711_bible_text_storage.sql)
bible_translations    -- 'web', 'kjv', 'asv'
bible_books          -- 66 books with metadata
bible_verses         -- verse-level text (translation_id, book_id, chapter, verse, text)
bible_audio_files    -- generated audio metadata (storage_provider, path, duration, etc.)
```

## App Integration (Flutter)

Use `AudioBibleService` in your Flutter app:

```dart
final audioService = ref.read(audioBibleServiceProvider);

// Stream audio directly from storage
final url = await audioService.getChapterAudioUrl('John', 3);

// Or use the player widget
AudioBiblePlayer(
  bookName: 'John',
  chapter: 3,
  translationCode: 'web',
)
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| TTS synthesis fails | Check platform TTS is working: `flutter_tts` test app |
| Supabase upload fails (413) | Enable R2 fallback or increase Supabase file limit |
| Missing verses | Re-run seeder with `--force` |
| Audio cuts off | Increase TTS timeout, check text length limits |
| Voice not found | List available voices: `await flutterTts.getVoices` |

## Cost Optimization

- **Supabase Storage**: ~$0.021/GB/month + bandwidth
- **Cloudflare R2**: $0.015/GB/month, **zero egress fees** (recommended for audio)
- **TTS**: Free with platform voices, ~$16/million chars for cloud neural voices

For 3.5 GB Bible audio:
- Supabase only: ~$0.07/month storage + egress
- With R2: ~$0.05/month storage, free egress