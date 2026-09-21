// ─── transcribe-media ───────────────────────────────────────────────────────
//
// Whisper auto-transcription pipeline for sermons + live-stream recordings.
//
//   POST (auth, leadership)   { transcriptId? , sermonId?, liveStreamId?, force? }
//   POST ?sweep=1             cron / platform staff — resumes pending + stale
//                             `processing` rows (a single invocation can hit the
//                             wall-clock limit, so work is chunk-resumable).
//   GET  ?health=whisper      secret-free probe (booleans only).
//
// Whisper is called over the Workers AI REST API via `_shared/ai.ts` config:
//   POST https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/{MODEL}
//   Authorization: Bearer <CLOUDFLARE_AI_TOKEN | CLOUDFLARE_API_TOKEN>
//   body: { "audio": "<base64>", "task": "transcribe", "language"?: "en" }
//   → { result: { text, vtt?, words?: [{ word, start, end }] } }
//
// Model: `CF_WHISPER_MODEL` (default `@cf/openai/whisper-large-v3-turbo`; the
// cheaper `@cf/openai/whisper` may be set instead). When `CF_AI_GATEWAY_URL`
// is set it replaces the raw endpoint (AI Gateway / Worker proxy).
//
// Reality constraints handled here:
//   * Edge Functions have bounded memory + wall clock, so only AUDIO sources
//     are chunked. MP3 is split on frame sync, WAV on sample boundaries (each
//     chunk gets a rebuilt header); anything else (m4a/aac/ogg/video) is only
//     attempted when small enough for ONE request, otherwise the row is marked
//     `failed` with an actionable message instead of hanging.
//   * status is set to `processing` before work and always ends in `ready` or
//     `failed`; a crash leaves a stale `processing` row the sweep resumes.
//   * every chunk is committed to the DB, so resuming never redoes audio.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { callModel, getAiConfig } from "../_shared/ai.ts";

// ── Tuning (env-overridable) ────────────────────────────────────────────────
const DEFAULT_WHISPER_MODEL = "@cf/openai/whisper-large-v3-turbo";
const MAX_SOURCE_BYTES = 500 * 1024 * 1024; // hard reject above this
const CHUNK_BYTES = 16 * 1024 * 1024; // ~16 MB per Whisper request
const SINGLE_MAX_BYTES = 16 * 1024 * 1024; // non-splittable formats
const WHISPER_TIMEOUT_MS = 120_000;
const INVOCATION_BUDGET_MS = 125_000; // stop before the edge wall clock
const SWEEP_STALE_MS = 3 * 60 * 1000; // resume a `processing` row after 3 min

const LEADERSHIP_ROLES = [
  "superadmin", "super_admin", "coa_employee", "employee",
  "bishop", "apostle", "prophet", "general_secretary", "general_treasurer",
  "pastor", "admin", "leader", "department_leader", "treasurer",
];
const PLATFORM_ROLES = ["superadmin", "super_admin", "coa_employee", "employee"];

// ── Small helpers ───────────────────────────────────────────────────────────
const env = (k: string) => (Deno.env.get(k) ?? "").trim();

function json(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "Content-Type": "application/json" },
  });
}

function whisperConfig() {
  const accountId = env("CLOUDFLARE_ACCOUNT_ID");
  const token = env("CLOUDFLARE_AI_TOKEN") || env("CLOUDFLARE_API_TOKEN");
  const model = env("CF_WHISPER_MODEL") || DEFAULT_WHISPER_MODEL;
  const gateway = env("CF_AI_GATEWAY_URL") || null;
  return {
    accountId, token, model, gateway,
    configured: Boolean(accountId && token),
  };
}

function base64FromBytes(bytes: Uint8Array): string {
  let binary = "";
  const stride = 0x8000;
  for (let i = 0; i < bytes.length; i += stride) {
    binary += String.fromCharCode(...bytes.subarray(i, i + stride));
  }
  return btoa(binary);
}

type WhisperWord = { word?: string; start?: number; end?: number; text?: string };
type WhisperSegment = { start: number; end: number; text: string };

async function whisperTranscribe(
  bytes: Uint8Array,
  language: string | null,
): Promise<{ text: string; words: WhisperWord[]; model: string }> {
  const cfg = whisperConfig();
  if (!cfg.configured) throw new Error("whisper_not_configured");

  const endpoint = cfg.gateway
    ? `${cfg.gateway.replace(/\/+$/, "")}/${cfg.model}`
    : `https://api.cloudflare.com/client/v4/accounts/${cfg.accountId}/ai/run/${cfg.model}`;

  const payload: Record<string, unknown> = {
    audio: base64FromBytes(bytes),
    task: "transcribe",
    vad_filter: false,
  };
  if (language) payload.language = language;

  const res = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(WHISPER_TIMEOUT_MS),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`whisper_http_${res.status}: ${body.slice(0, 180)}`);
  }

  const data = await res.json().catch(() => null) as Record<string, any> | null;
  const result = (data?.result ?? data ?? {}) as Record<string, any>;
  const text = typeof result.text === "string" ? result.text : "";
  const words: WhisperWord[] = Array.isArray(result.words) ? result.words : [];
  return { text, words, model: cfg.model };
}

// ── Media probing + chunk planning ──────────────────────────────────────────

type MediaKind = "mp3" | "wav" | "other-audio" | "video" | "hls";

function classify(url: string, contentType: string): MediaKind {
  const u = url.split("?")[0].toLowerCase();
  const ct = contentType.toLowerCase();
  if (u.endsWith(".m3u8") || ct.includes("mpegurl")) return "hls";
  if (u.endsWith(".mp3") || ct.includes("mpeg")) return "mp3";
  if (u.endsWith(".wav") || ct.includes("wav") || ct.includes("x-wav")) return "wav";
  if (ct.startsWith("video/") || u.endsWith(".mp4") || u.endsWith(".webm")) return "video";
  return "other-audio";
}

async function probeMedia(url: string): Promise<{ bytes: number; contentType: string; kind: MediaKind; range: boolean }> {
  let length = 0;
  let contentType = "";
  let acceptRanges = false;
  try {
    const head = await fetch(url, { method: "HEAD", signal: AbortSignal.timeout(20_000) });
    length = Number(head.headers.get("content-length") ?? 0) || 0;
    contentType = head.headers.get("content-type") ?? "";
    acceptRanges = (head.headers.get("accept-ranges") ?? "").includes("bytes");
  } catch {
    // ignore — fall through to a ranged GET probe
  }
  if (!length) {
    const res = await fetch(url, {
      headers: { Range: "bytes=0-0" },
      signal: AbortSignal.timeout(20_000),
    });
    const cr = res.headers.get("content-range");
    length = Number(cr?.split("/")[1] ?? res.headers.get("content-length") ?? 0) || 0;
    contentType = contentType || (res.headers.get("content-type") ?? "");
    acceptRanges = (res.headers.get("accept-ranges") ?? "").includes("bytes");
    await res.body?.cancel().catch(() => {});
  }
  return { bytes: length, contentType, kind: classify(url, contentType), range: acceptRanges };
}

// A chunk is a half-open byte range. Non-splittable media resolves to a single
// range [0, bytes). Ranges are computed deterministically so a resumed job
// recomputes exactly the same boundaries.
function planChunks(bytes: number, kind: MediaKind): Array<[number, number]> {
  if (kind !== "mp3" && kind !== "wav") return [[0, bytes]];
  if (bytes <= CHUNK_BYTES) return [[0, bytes]];
  const chunks: Array<[number, number]> = [];
  for (let start = 0; start < bytes; start += CHUNK_BYTES) {
    chunks.push([start, Math.min(start + CHUNK_BYTES, bytes)]);
  }
  return chunks;
}

/** Fetch one deterministic chunk, trimming to a codec boundary when possible. */
async function fetchChunk(
  url: string,
  kind: MediaKind,
  start: number,
  end: number,
  totalBytes: number,
): Promise<Uint8Array> {
  // Fetch a small overlap so we can snap MP3 chunks to a frame sync.
  const pad = kind === "mp3" && end < totalBytes ? 2048 : 0;
  const from = Math.max(0, start - pad);
  const to = Math.min(totalBytes - 1, end + pad);
  const res = await fetch(url, {
    headers: { Range: `bytes=${from}-${to}` },
    signal: AbortSignal.timeout(45_000),
  });
  if (!res.ok && res.status !== 206) {
    throw new Error(`media_fetch_${res.status}`);
  }
  let buf = new Uint8Array(await res.arrayBuffer());

  if (kind === "mp3" && pad > 0) {
    // Snap to the first MPEG audio frame sync (0xFF Ex) at/after the chunk start.
    const searchFrom = Math.max(0, start - from);
    for (let i = searchFrom; i < buf.length - 1; i++) {
      if (buf[i] === 0xff && (buf[i + 1] & 0xe0) === 0xe0) {
        buf = buf.subarray(i, Math.min(buf.length, i + (end - start) + pad));
        break;
      }
    }
  }
  return buf;
}

function parseWavHeader(bytes: Uint8Array): { channelCount: number; sampleRate: number; bitsPerSample: number } | null {
  if (bytes.length < 44) return null;
  const tag = String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]);
  if (tag !== "RIFF") return null;
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const view = { channelCount: dv.getUint16(22, true), sampleRate: dv.getUint32(24, true), bitsPerSample: dv.getUint16(34, true) };
  return view.channelCount && view.sampleRate && view.bitsPerSample ? view : null;
}

/** Rebuilds a canonical 44-byte WAV header for a PCM data slice. */
function buildWavHeader(channelCount: number, sampleRate: number, bitsPerSample: number, dataLen: number): Uint8Array {
  const header = new Uint8Array(44);
  const dv = new DataView(header.buffer);
  const byteRate = (sampleRate * channelCount * bitsPerSample) / 8;
  const blockAlign = (channelCount * bitsPerSample) / 8;
  const writeStr = (off: number, s: string) => { for (let i = 0; i < s.length; i++) header[off + i] = s.charCodeAt(i); };
  writeStr(0, "RIFF");
  dv.setUint32(4, 36 + dataLen, true);
  writeStr(8, "WAVE");
  writeStr(12, "fmt ");
  dv.setUint32(16, 16, true);
  dv.setUint16(20, 1, true);
  dv.setUint16(22, channelCount, true);
  dv.setUint32(24, sampleRate, true);
  dv.setUint32(28, byteRate, true);
  dv.setUint16(32, blockAlign, true);
  dv.setUint16(34, bitsPerSample, true);
  writeStr(36, "data");
  dv.setUint32(40, dataLen, true);
  return header;
}

// ── Segments / VTT ──────────────────────────────────────────────────────────

function wordsToSegments(words: WhisperWord[], offsetSeconds: number): WhisperSegment[] {
  const segs: WhisperSegment[] = [];
  let bucket: WhisperWord[] = [];
  const flush = () => {
    if (!bucket.length) return;
    const start = Number(bucket[0].start ?? 0) + offsetSeconds;
    const end = Number(bucket[bucket.length - 1].end ?? bucket[bucket.length - 1].start ?? 0) + offsetSeconds;
    const text = bucket.map((w) => (w.word ?? w.text ?? "").trim()).filter(Boolean).join(" ");
    if (text) segs.push({ start, end, text });
    bucket = [];
  };
  for (const w of words) {
    bucket.push(w);
    if (bucket.length >= 8) flush();
  }
  flush();
  return segs;
}

function secondsToVttTime(s: number): string {
  const total = Math.max(0, s);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const sec = Math.floor(total % 60);
  const ms = Math.round((total - Math.floor(total)) * 1000);
  const p = (n: number, w = 2) => String(n).padStart(w, "0");
  return `${p(h)}:${p(m)}:${p(sec)}.${p(ms, 3)}`;
}

function buildVtt(segments: WhisperSegment[]): string {
  const lines = ["WEBVTT", ""];
  for (const s of segments) {
    lines.push(`${secondsToVttTime(s.start)} --> ${secondsToVttTime(s.end)}`);
    lines.push(s.text);
    lines.push("");
  }
  return lines.join("\n");
}

// ── Bible verse detection ───────────────────────────────────────────────────
// Canonical spellings match `bible_books.name` (NB: "Psalms" is plural).
const CANONICAL_BOOKS = [
  "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth",
  "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles", "Ezra",
  "Nehemiah", "Esther", "Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon",
  "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos",
  "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah",
  "Malachi", "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians",
  "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians",
  "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus", "Philemon",
  "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude",
  "Revelation",
];

const ALIASES: Record<string, string> = {
  "gen": "Genesis", "ex": "Exodus", "exod": "Exodus", "lev": "Leviticus", "num": "Numbers",
  "deut": "Deuteronomy", "josh": "Joshua", "judg": "Judges", "ps": "Psalms", "psalm": "Psalms",
  "psalms": "Psalms", "prov": "Proverbs", "eccl": "Ecclesiastes", "song": "Song of Solomon",
  "song of songs": "Song of Solomon", "isa": "Isaiah", "jer": "Jeremiah", "lam": "Lamentations",
  "ezek": "Ezekiel", "dan": "Daniel", "hos": "Hosea", "obad": "Obadiah", "mic": "Micah",
  "nah": "Nahum", "hab": "Habakkuk", "zeph": "Zephaniah", "hag": "Haggai", "zech": "Zechariah",
  "mal": "Malachi", "matt": "Matthew", "mt": "Matthew", "mk": "Mark", "lk": "Luke",
  "jn": "John", "rom": "Romans", "gal": "Galatians", "eph": "Ephesians", "phil": "Philippians",
  "col": "Colossians", "thess": "1 Thessalonians", "tim": "1 Timothy", "phlm": "Philemon",
  "heb": "Hebrews", "jas": "James", "pet": "1 Peter", "rev": "Revelation", "revelations": "Revelation",
};
for (const book of CANONICAL_BOOKS) {
  ALIASES[book.toLowerCase()] = book;
  ALIASES[book.toLowerCase().replace(/\s+/g, "")] = book;
}
const ALIAS_KEYS = Object.keys(ALIASES).sort((a, b) => b.length - a.length);
const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

export type VerseMarker = {
  reference: string; book: string; chapter: number; verse: number;
  verse_end: number | null; start_seconds: number | null; end_seconds: number | null;
  raw: string; confidence: number;
};

/** Maps a character offset in `text` to a word start/end time (if available). */
function timeAtOffset(text: string, words: WhisperWord[], charIndex: number, charEnd: number, offsetSeconds: number) {
  if (!words.length) return { start: null as number | null, end: null as number | null };
  const pos: Array<{ cs: number; ce: number; start: number; end: number }> = [];
  let cursor = 0;
  for (const w of words) {
    const raw = (w.word ?? w.text ?? "");
    const clean = raw.trim();
    if (!clean) continue;
    const at = text.indexOf(clean, cursor);
    if (at < 0) continue;
    const cs = at;
    const ce = at + clean.length;
    cursor = ce;
    pos.push({ cs, ce, start: Number(w.start ?? 0) + offsetSeconds, end: Number(w.end ?? w.start ?? 0) + offsetSeconds });
  }
  if (!pos.length) return { start: null, end: null };
  const startWord = pos.find((p) => p.ce >= charIndex) ?? pos[pos.length - 1];
  const endWord = [...pos].reverse().find((p) => p.cs <= charEnd) ?? pos[pos.length - 1];
  return { start: startWord.start, end: endWord.end };
}

export function detectVerseMarkers(
  text: string,
  words: WhisperWord[] = [],
  offsetSeconds = 0,
): VerseMarker[] {
  if (!text || text.trim().length < 3) return [];
  const found = new Map<string, VerseMarker>();
  const aliasPattern = ALIAS_KEYS.map(escapeRe).join("|");
  // book + chapter:verse(-verse) — a bare "3:16" can never match (book required)
  const re = new RegExp(`\\b(${aliasPattern})\\.?\\s+(\\d{1,3})\\s*[:.]\\s*(\\d{1,3})(?:\\s*[-–—]\\s*(\\d{1,3}))?`, "gi");

  for (const m of text.matchAll(re)) {
    const rawBook = m[1];
    // Short aliases (2–3 chars) are only trusted when capitalised, so ordinary
    // prose ("no 3:16", "is 3:16") never becomes a verse.
    if (rawBook.length <= 3 && rawBook[0] !== rawBook[0].toUpperCase()) continue;
    const key = rawBook.toLowerCase().replace(/\./g, "").trim();
    const book = ALIASES[key];
    if (!book) continue;
    const chapter = Number(m[2]);
    const verse = Number(m[3]);
    const verseEnd = m[4] ? Number(m[4]) : null;
    // Guard rails against false positives.
    if (chapter <= 0 || chapter > 150 || verse <= 0 || verse > 176) continue;
    const raw = m[0];
    if (found.has(raw.toLowerCase())) continue;
    const timing = timeAtOffset(text, words, m.index ?? 0, (m.index ?? 0) + raw.length, offsetSeconds);
    found.set(raw.toLowerCase(), {
      reference: `${book} ${chapter}:${verse}${verseEnd && verseEnd > verse ? `-${verseEnd}` : ""}`,
      book, chapter, verse, verse_end: verseEnd,
      start_seconds: timing.start, end_seconds: timing.end,
      raw,
      confidence: rawBook.toLowerCase() === book.toLowerCase() ? 1 : 0.85,
    });
  }
  return [...found.values()].sort((a, b) => (a.start_seconds ?? 1e9) - (b.start_seconds ?? 1e9));
}

/** Optionally asks Kael to drop ambiguous matches (fail-open). */
async function validateMarkersWithKael(markers: VerseMarker[]): Promise<VerseMarker[]> {
  const ambiguous = markers.filter((m) => m.confidence < 1);
  if (!ambiguous.length || markers.length > 15) return markers;
  try {
    const cfg = getAiConfig();
    if (!cfg.workersAi && !cfg.huggingface) return markers;
    const list = ambiguous.map((m) => m.reference).join(", ");
    const { text } = await callModel([
      { role: "system", content: "You validate Bible references. Reply with ONLY a JSON array of the references that are REAL Bible books, chapters and verses. No prose." },
      { role: "user", content: `Validate these: ${list}` },
    ], { maxTokens: 200, temperature: 0, label: "transcribe-media:verse-validate" });
    const json = text.slice(text.indexOf("["), text.lastIndexOf("]") + 1);
    const valid = new Set<string>(JSON.parse(json).map((v: unknown) => String(v).toLowerCase()));
    if (!valid.size) return markers;
    return markers.filter((m) => m.confidence === 1 || valid.has(m.reference.toLowerCase()));
  } catch (e) {
    console.warn("[transcribe-media] verse validation skipped:", e instanceof Error ? e.message : e);
    return markers;
  }
}

// ── Row processing ──────────────────────────────────────────────────────────

type TranscriptRow = {
  id: string; tenant_id: string | null; sermon_id: string | null; live_stream_id: string | null;
  source_url: string; language: string | null; status: string;
  transcript: string | null; segments: WhisperSegment[] | null; verse_markers: VerseMarker[];
  chunk_index: number; chunk_total: number; model: string | null;
};

function mergeSegments(existing: WhisperSegment[] | null, added: WhisperSegment[]): WhisperSegment[] {
  const out = Array.isArray(existing) ? [...existing] : [];
  const lastEnd = out.length ? out[out.length - 1].end : 0;
  for (const s of added) {
    if (s.end <= lastEnd + 0.05) continue;
    out.push({ ...s, start: Math.max(s.start, lastEnd) });
  }
  return out;
}

async function processRow(
  // Untyped service-role client (the generated DB types are not shipped to the
  // edge runtime, so callers use the untyped `any` shape, as elsewhere).
  // deno-lint-ignore no-explicit-any
  supabase: any,
  row: TranscriptRow,
  deadline: number,
): Promise<{ status: string; error?: string; chunksDone: number }> {
  if (row.status === "ready") return { status: "ready", chunksDone: 0 };

  const cfg = whisperConfig();
  if (!cfg.configured) {
    await supabase.from("media_transcripts")
      .update({ status: "failed", error: "Whisper is not configured on the server (CLOUDFLARE_ACCOUNT_ID / token)." })
      .eq("id", row.id);
    return { status: "failed", error: "whisper_not_configured", chunksDone: 0 };
  }
  if (row.source_url.startsWith("r2://")) {
    await supabase.from("media_transcripts")
      .update({ status: "failed", error: "Source is a private object (r2://). Set a public/archive URL and retry." })
      .eq("id", row.id);
    return { status: "failed", error: "private_source", chunksDone: 0 };
  }

  let probe;
  try {
    probe = await probeMedia(row.source_url);
  } catch (e) {
    const msg = `Could not read media: ${e instanceof Error ? e.message : "unknown"}`;
    await supabase.from("media_transcripts").update({ status: "failed", error: msg }).eq("id", row.id);
    return { status: "failed", error: msg, chunksDone: 0 };
  }

  if (probe.kind === "hls") {
    const msg = "This is an HLS stream. Transcribe the archived recording or upload an audio master instead.";
    await supabase.from("media_transcripts").update({ status: "failed", error: msg, bytes_total: probe.bytes }).eq("id", row.id);
    return { status: "failed", error: msg, chunksDone: 0 };
  }
  if (probe.bytes > MAX_SOURCE_BYTES) {
    const msg = `Media is too large (${Math.round(probe.bytes / 1048576)} MB). Upload an audio-only master (MP3/WAV) instead.`;
    await supabase.from("media_transcripts").update({ status: "failed", error: msg, bytes_total: probe.bytes }).eq("id", row.id);
    return { status: "failed", error: msg, chunksDone: 0 };
  }
  const splittable = probe.kind === "mp3" || probe.kind === "wav";
  if (!splittable && probe.bytes > SINGLE_MAX_BYTES) {
    const msg = "Video/compressed audio cannot be transcoded on the server. Upload an MP3/WAV master or a shorter clip.";
    await supabase.from("media_transcripts").update({ status: "failed", error: msg, bytes_total: probe.bytes }).eq("id", row.id);
    return { status: "failed", error: msg, chunksDone: 0 };
  }

  const chunks = planChunks(probe.bytes, probe.kind);
  const chunkTotal = chunks.length;

  // Mark processing up-front so an in-flight job is never sent back to `pending`.
  await supabase.from("media_transcripts")
    .update({ status: "processing", error: null, chunk_total: chunkTotal, bytes_total: probe.bytes, model: cfg.model })
    .eq("id", row.id);

  let segments: WhisperSegment[] = Array.isArray(row.segments) ? row.segments : [];
  let fullText = row.transcript ?? "";
  let nextChunk = Math.max(0, Math.min(row.chunk_index ?? 0, chunkTotal - 1));
  let chunksDone = 0;
  let wavHeader: { channelCount: number; sampleRate: number; bitsPerSample: number } | null = null;

  for (let i = nextChunk; i < chunkTotal; i++) {
    if (Date.now() > deadline) {
      // Out of time — leave `processing`; `?sweep=1` will resume at chunk_index.
      await supabase.from("media_transcripts")
        .update({ transcript: fullText, segments, chunk_index: i, updated_at: new Date().toISOString() })
        .eq("id", row.id);
      return { status: "processing", chunksDone };
    }
    const [start, end] = chunks[i];
    let chunkBytes: Uint8Array;
    try {
      chunkBytes = await fetchChunk(row.source_url, probe.kind, start, end, probe.bytes);
    } catch (e) {
      const msg = `Media download failed at chunk ${i + 1}: ${e instanceof Error ? e.message : "unknown"}`;
      await supabase.from("media_transcripts").update({ status: "failed", error: msg }).eq("id", row.id);
      return { status: "failed", error: msg, chunksDone };
    }

    // WAV: replace the source header with a header for this PCM slice.
    if (probe.kind === "wav") {
      if (!wavHeader) wavHeader = parseWavHeader(chunkBytes) ?? (chunkBytes.length > 44 ? { channelCount: 1, sampleRate: 16000, bitsPerSample: 16 } : null);
      if (wavHeader && chunkBytes.length > 44 && start > 0) {
        const data = chunkBytes.subarray(44);
        const header = buildWavHeader(wavHeader.channelCount, wavHeader.sampleRate, wavHeader.bitsPerSample, data.length);
        const rebuilt = new Uint8Array(header.length + data.length);
        rebuilt.set(header, 0);
        rebuilt.set(data, header.length);
        chunkBytes = rebuilt;
      }
    }

    let result;
    try {
      result = await whisperTranscribe(chunkBytes, row.language);
    } catch (e) {
      const msg = `Transcription failed at chunk ${i + 1}: ${e instanceof Error ? e.message : "unknown"}`;
      await supabase.from("media_transcripts")
        .update({ transcript: fullText, segments, chunk_index: i,
          status: e instanceof Error && e.name === "TimeoutError" ? "processing" : "failed",
          error: e instanceof Error && e.name === "TimeoutError" ? null : msg,
          bytes_total: probe.bytes,
        })
        .eq("id", row.id);
      return { status: e instanceof Error && e.name === "TimeoutError" ? "processing" : "failed", error: msg, chunksDone };
    }

    const offset = segments.length ? segments[segments.length - 1].end : 0;
    const newSegments = wordsToSegments(result.words, offset);
    segments = mergeSegments(segments, newSegments.length ? newSegments : [{ start: offset, end: offset + 1, text: result.text.trim() }]);
    fullText = [fullText.trim(), result.text.trim()].filter(Boolean).join(" ");
    chunksDone++;

    await supabase.from("media_transcripts")
      .update({
        transcript: fullText,
        segments,
        chunk_index: i + 1,
        word_count: fullText.split(/\s+/).filter(Boolean).length,
        duration_seconds: segments.length ? segments[segments.length - 1].end : null,
        model: cfg.model,
        updated_at: new Date().toISOString(),
      })
      .eq("id", row.id);
  }

  // All chunks done → verse detection, VTT, and finalise.
  let markers = detectVerseMarkers(fullText, [], 0);
  markers = await validateMarkersWithKael(markers);
  const vtt = buildVtt(segments);

  await supabase.from("media_transcripts")
    .update({
      status: "ready",
      error: null,
      transcript: fullText,
      vtt,
      segments,
      verse_markers: markers,
      chunk_index: chunkTotal,
      word_count: fullText.split(/\s+/).filter(Boolean).length,
      duration_seconds: segments.length ? segments[segments.length - 1].end : null,
      language: row.language,
      model: cfg.model,
      updated_at: new Date().toISOString(),
    })
    .eq("id", row.id);

  // Best-effort: mirror the text onto the sermon row so existing sermon search
  // and AI notes keep working unchanged.
  if (row.sermon_id && fullText.trim()) {
    await supabase.from("sermons").update({ transcript: fullText }).eq("id", row.sermon_id);
  }

  return { status: "ready", chunksDone };
}

// ── Server ──────────────────────────────────────────────────────────────────
serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const url = new URL(req.url);

  // Secret-free health probe.
  if (req.method === "GET" && url.searchParams.get("health") === "whisper") {
    const cfg = whisperConfig();
    const ai = getAiConfig();
    return json({
      status: cfg.configured ? "ok" : "unconfigured",
      whisper: {
        configured: cfg.configured,
        model: cfg.model,
        gateway: Boolean(cfg.gateway),
        max_source_bytes: MAX_SOURCE_BYTES,
        chunk_bytes: CHUNK_BYTES,
      },
      secrets: {
        CLOUDFLARE_ACCOUNT_ID: Boolean(env("CLOUDFLARE_ACCOUNT_ID")),
        CLOUDFLARE_AI_TOKEN: Boolean(env("CLOUDFLARE_AI_TOKEN")),
        CLOUDFLARE_API_TOKEN: Boolean(env("CLOUDFLARE_API_TOKEN")),
        CF_WHISPER_MODEL: Boolean(env("CF_WHISPER_MODEL")),
        CF_AI_GATEWAY_URL: Boolean(env("CF_AI_GATEWAY_URL")),
        CRON_SECRET: Boolean(env("CRON_SECRET")),
      },
      ai_provider: ai.workersAi ? "workers-ai" : ai.huggingface ? "huggingface" : "none",
    }, 200, corsHeaders);
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405, corsHeaders);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  const authHeader = req.headers.get("Authorization");
  const cronSecret = env("CRON_SECRET");
  const providedCron = req.headers.get("x-cron-secret");
  const isSweep = url.searchParams.get("sweep") === "1";

  // ── Sweep path ────────────────────────────────────────────────────────────
  if (isSweep) {
    let authorised = Boolean(cronSecret && providedCron === cronSecret);
    if (!authorised && authHeader) {
      const u = createClient(supabaseUrl, serviceKey);
      const token = authHeader.replace("Bearer ", "");
      const { data: { user } } = await u.auth.getUser(token);
      if (user) {
        const { data: prof } = await supabase.from("profiles").select("role").eq("id", user.id).maybeSingle();
        authorised = PLATFORM_ROLES.includes(prof?.role ?? "");
      }
    }
    if (!authorised) return json({ error: "Unauthorized" }, 401, corsHeaders);

    const staleIso = new Date(Date.now() - SWEEP_STALE_MS).toISOString();
    const { data: rows, error } = await supabase
      .from("media_transcripts")
      .select("*")
      .or(`status.eq.pending,and(status.eq.processing,updated_at.lt.${staleIso})`)
      .order("updated_at", { ascending: true })
      .limit(3);
    if (error) return json({ error: "sweep_query_failed", detail: error.message }, 500, corsHeaders);

    const deadline = Date.now() + INVOCATION_BUDGET_MS;
    const results: Array<Record<string, unknown>> = [];
    for (const row of (rows ?? []) as TranscriptRow[]) {
      if (Date.now() > deadline) break;
      const r = await processRow(supabase, row, deadline);
      results.push({ id: row.id, ...r });
    }
    return json({ swept: results.length, results }, 200, corsHeaders);
  }

  // ── Authenticated single-job path ─────────────────────────────────────────
  if (!authHeader) return json({ error: "Missing authorization header" }, 401, corsHeaders);
  const token = authHeader.replace("Bearer ", "");
  const authClient = createClient(supabaseUrl, serviceKey);
  const { data: { user }, error: authError } = await authClient.auth.getUser(token);
  if (authError || !user) return json({ error: "Unauthorized" }, 401, corsHeaders);

  const { data: profile } = await supabase
    .from("profiles").select("role, tenant_id").eq("id", user.id).maybeSingle();
  const role = profile?.role ?? "";
  const isPlatform = PLATFORM_ROLES.includes(role);

  let body: { transcriptId?: string; sermonId?: string; liveStreamId?: string; force?: boolean; language?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400, corsHeaders);
  }

  let row: TranscriptRow | null = null;

  if (body.transcriptId) {
    const { data } = await supabase.from("media_transcripts").select("*").eq("id", body.transcriptId).maybeSingle();
    row = (data as TranscriptRow) ?? null;
    if (!row) return json({ error: "transcript_not_found" }, 404, corsHeaders);
  } else if (body.sermonId || body.liveStreamId) {
    // Reuse the leadership-gated, idempotent RPC (runs as the calling user).
    const asUser = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data, error } = await asUser.rpc("request_transcription", {
      p_sermon_id: body.sermonId ?? null,
      p_live_stream_id: body.liveStreamId ?? null,
    });
    if (error) {
      const msg = /leadership_required/.test(error.message) ? "leadership_required" : error.message;
      const status = msg === "leadership_required" ? 403 : 400;
      return json({ error: msg }, status, corsHeaders);
    }
    row = (data?.transcript ?? null) as TranscriptRow;
    if (!row) return json({ error: "transcript_not_found" }, 404, corsHeaders);
  } else {
    return json({ error: "Provide transcriptId, sermonId or liveStreamId" }, 400, corsHeaders);
  }

  // Defence in depth: a non-platform caller may only touch their tenant's rows.
  if (!isPlatform && row.tenant_id && row.tenant_id !== profile?.tenant_id) {
    return json({ error: "forbidden" }, 403, corsHeaders);
  }
  if (!isPlatform && !LEADERSHIP_ROLES.includes(role)) {
    return json({ error: "leadership_required" }, 403, corsHeaders);
  }
  if (body.language && !row.language) {
    row.language = body.language;
  }

  if (row.status === "ready" && !body.force) {
    return json({ status: "ready", transcript: row, skipped: true }, 200, corsHeaders);
  }
  if (row.status === "processing" && !body.force) {
    return json({ status: "processing", transcript: row, skipped: true }, 200, corsHeaders);
  }

  const result = await processRow(supabase, row, Date.now() + INVOCATION_BUDGET_MS);

  const { data: fresh } = await supabase.from("media_transcripts").select("*").eq("id", row.id).maybeSingle();
  return json({ status: result.status, error: result.error ?? null, transcript: fresh }, 200, corsHeaders);
});
