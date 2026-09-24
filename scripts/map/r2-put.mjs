#!/usr/bin/env node
// r2-put.mjs — upload (or copy) an object to Cloudflare R2 over the S3 API
// using SigV4. Wrangler's `r2 object put` crashes on Windows for large files
// (libuv assertion) and the Cloudflare dashboard caps uploads at 300 MB, so
// anything over ~250 MB MUST go through this script.
//
//   node scripts/map/r2-put.mjs <local-file> <r2-key> [options]
//   node scripts/map/r2-put.mjs --head <r2-key>          # verify an object
//
// Options:
//   --bucket <name>       R2 bucket (default: church-on-app-maps)
//   --content-type <mime> Content-Type to store (default: application/octet-stream)
//   --env-file <path>     dotenv file with the R2 credentials
//   --quiet               no progress output
//
// Credentials (env-driven, NEVER hardcoded):
//   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY
// The sibling `churchonapp/.env` names are accepted too:
//   VITE_R2_ACCOUNT_ID, VITE_R2_ACCESS_KEY_ID, VITE_R2_SECRET_ACCESS_KEY
// If unset, the script looks for `--env-file`, then $R2_ENV_FILE, then the
// sibling churchonapp/.env relative to this repo.

import { createHash, createHmac } from 'node:crypto';
import { createReadStream, existsSync, readFileSync, statSync } from 'node:fs';
import https from 'node:https';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_BUCKET = 'church-on-app-maps';

// ---------------------------------------------------------------- arg parsing
function parseArgs(argv) {
  const out = { positional: [], options: {} };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--head' || a === '--quiet' || a === '--copy' || a === '--help' || a === '-h') {
      out.options[a.replace(/^--?/, '')] = true;
    } else if (a.startsWith('--')) {
      const key = a.slice(2);
      const eq = key.indexOf('=');
      if (eq >= 0) {
        out.options[key.slice(0, eq)] = key.slice(eq + 1);
      } else {
        out.options[key] = argv[++i];
      }
    } else {
      out.positional.push(a);
    }
  }
  return out;
}

function loadDotEnv(file) {
  if (!file || !existsSync(file)) return;
  const text = readFileSync(file, 'utf8');
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq <= 0) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

function resolveCredentials(opts) {
  const envFile =
    opts.envFile ||
    process.env.R2_ENV_FILE ||
    path.resolve(__dirname, '../../../churchonapp/.env');
  loadDotEnv(envFile);

  const accountId =
    process.env.R2_ACCOUNT_ID || process.env.VITE_R2_ACCOUNT_ID || '';
  const accessKeyId =
    process.env.R2_ACCESS_KEY_ID || process.env.VITE_R2_ACCESS_KEY_ID || '';
  const secretAccessKey =
    process.env.R2_SECRET_ACCESS_KEY ||
    process.env.VITE_R2_SECRET_ACCESS_KEY ||
    '';
  const bucket =
    opts.bucket ||
    process.env.R2_BUCKET ||
    process.env.VITE_R2_BUCKET_NAME ||
    DEFAULT_BUCKET;

  if (!accountId || !accessKeyId || !secretAccessKey) {
    console.error(
      '[r2-put] Missing credentials. Set R2_ACCOUNT_ID / R2_ACCESS_KEY_ID / ' +
        'R2_SECRET_ACCESS_KEY (or VITE_R2_*), or pass --env-file <path>.'
    );
    console.error(`[r2-put] Tried env file: ${envFile}`);
    process.exit(2);
  }
  return { accountId, accessKeyId, secretAccessKey, bucket };
}

// ------------------------------------------------------------------- SigV4
function sha256Hex(data) {
  return createHash('sha256').update(data).digest('hex');
}

function hmac(key, data) {
  return createHmac('sha256', key).update(data).digest();
}

function uriEncode(str, encodeSlash = true) {
  return encodeURIComponent(str)
    .replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase())
    .replace(/%2F/g, encodeSlash ? '%2F' : '/');
}

function signRequest({
  method,
  bucket,
  key,
  host,
  payloadHash,
  contentType,
  accessKeyId,
  secretAccessKey,
  region,
  extraHeaders = {},
}) {
  const now = new Date();
  const amzDate = now
    .toISOString()
    .replace(/[:-]|\.\d{3}/g, '')
    .replace('Z', 'Z');
  const dateStamp = amzDate.slice(0, 8);

  // Path-style addressing: /<bucket>/<key> on <accountid>.r2.cloudflarestorage.com
  const canonicalUri = `/${uriEncode(bucket)}/${uriEncode(key, false)}`;
  const headers = {
    'content-type': contentType,
    host,
    'x-amz-content-sha256': payloadHash,
    'x-amz-date': amzDate,
    ...extraHeaders,
  };
  const signedHeaderNames = Object.keys(headers).sort();
  const canonicalHeaders = signedHeaderNames
    .map((h) => `${h}:${String(headers[h]).trim()}\n`)
    .join('');
  const signedHeaders = signedHeaderNames.join(';');

  const canonicalRequest = [
    method,
    canonicalUri,
    '', // no query string
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  const scope = `${dateStamp}/${region}/s3/aws4_request`;
  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    sha256Hex(canonicalRequest),
  ].join('\n');

  const kDate = hmac(`AWS4${secretAccessKey}`, dateStamp);
  const kRegion = hmac(kDate, region);
  const kService = hmac(kRegion, 's3');
  const kSigning = hmac(kService, 'aws4_request');
  const signature = createHmac('sha256', kSigning)
    .update(stringToSign)
    .digest('hex');

  return {
    headers: {
      ...headers,
      authorization:
        `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${scope}, ` +
        `SignedHeaders=${signedHeaders}, Signature=${signature}`,
    },
    canonicalUri,
  };
}

// --------------------------------------------------------------- HTTP helpers
function request({ method, host, headers, bodyStream, contentLength, path: reqPath }) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        method,
        host,
        path: reqPath,
        headers: { ...headers, 'content-length': contentLength },
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          resolve({
            statusCode: res.statusCode,
            body: Buffer.concat(chunks).toString('utf8'),
          });
        });
      }
    );
    req.on('error', reject);
    if (bodyStream) {
      bodyStream.on('error', reject);
      bodyStream.pipe(req);
    } else {
      req.end();
    }
  });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// --------------------------------------------------------------------- main
async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (opts.help || (opts.positional.length === 0 && !opts.head)) {
    console.log(
      [
        'Usage:',
        '  node scripts/map/r2-put.mjs <local-file> <r2-key> [--bucket <b>] [--content-type <mime>] [--env-file <p>]',
        '  node scripts/map/r2-put.mjs --head <r2-key> [--bucket <b>]',
        '  node scripts/map/r2-put.mjs --copy <src-key> <dst-key> [--bucket <b>]',
        '',
        'Env: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY (or VITE_R2_*).',
      ].join('\n')
    );
    process.exit(opts.help || opts.head ? 0 : 2);
  }

  const creds = resolveCredentials(opts);
  const host = `${creds.accountId}.r2.cloudflarestorage.com`;
  const region = process.env.R2_REGION || 'auto';
  const quiet = !!opts.quiet;

  // -------------------------------------------------------------- head mode
  if (opts.head) {
    const key = opts.head === true ? opts.positional[0] : opts.head;
    if (!key) {
      console.error('[r2-put] --head requires an r2-key');
      process.exit(2);
    }
    const emptyHash = sha256Hex('');
    const signed = signRequest({
      method: 'HEAD',
      bucket: creds.bucket,
      key,
      host,
      payloadHash: emptyHash,
      contentType: 'application/octet-stream',
      accessKeyId: creds.accessKeyId,
      secretAccessKey: creds.secretAccessKey,
      region,
    });
    // HEAD needs content-length 0 with no body; content-type still signed.
    const res = await request({
      method: 'HEAD',
      host,
      headers: signed.headers,
      contentLength: 0,
      path: signed.canonicalUri,
    });
    if (res.statusCode === 200) {
      console.log(`[r2-put] OK  s3://${creds.bucket}/${key}`);
      process.exit(0);
    }
    console.error(`[r2-put] FAIL ${res.statusCode} s3://${creds.bucket}/${key}`);
    process.exit(1);
  }

  // ------------------------------------------------------------- copy mode
  // Server-side CopyObject: promote a dated snapshot onto the stable key
  // without pushing the bytes again from this machine.
  if (opts.copy) {
    const [srcKey, dstKey] = opts.positional;
    if (!srcKey || !dstKey) {
      console.error('[r2-put] Usage: r2-put.mjs --copy <srcKey> <dstKey>');
      process.exit(2);
    }
    const emptyHash = sha256Hex('');
    const signed = signRequest({
      method: 'PUT',
      bucket: creds.bucket,
      key: dstKey,
      host,
      payloadHash: emptyHash,
      contentType: 'application/octet-stream',
      accessKeyId: creds.accessKeyId,
      secretAccessKey: creds.secretAccessKey,
      region,
      extraHeaders: {
        'x-amz-copy-source': `/${creds.bucket}/${uriEncode(srcKey, false)}`,
      },
    });
    const res = await request({
      method: 'PUT',
      host,
      headers: signed.headers,
      contentLength: 0,
      path: signed.canonicalUri,
    });
    if (res.statusCode >= 200 && res.statusCode < 300) {
      console.log(
        `[r2-put] Copied s3://${creds.bucket}/${srcKey} -> s3://${creds.bucket}/${dstKey}`
      );
      process.exit(0);
    }
    console.error(`[r2-put] copy HTTP ${res.statusCode}: ${res.body.slice(0, 500)}`);
    process.exit(1);
  }

  // -------------------------------------------------------------- put mode
  const [file, key] = opts.positional;
  if (!file || !key) {
    console.error('[r2-put] Usage: r2-put.mjs <local-file> <r2-key>');
    process.exit(2);
  }
  if (!existsSync(file)) {
    console.error(`[r2-put] File not found: ${file}`);
    process.exit(2);
  }

  const stat = statSync(file);
  const contentType = opts['content-type'] || 'application/octet-stream';

  // Payload hash must be known before the body is sent, so hash the file in a
  // streaming pass first (no full read into memory).
  const payloadHash = await hashFile(file);
  if (!quiet) {
    console.log(
      `[r2-put] ${path.basename(file)} (${formatBytes(stat.size)}) -> ` +
        `s3://${creds.bucket}/${key}`
    );
  }

  const signed = signRequest({
    method: 'PUT',
    bucket: creds.bucket,
    key,
    host,
    payloadHash,
    contentType,
    accessKeyId: creds.accessKeyId,
    secretAccessKey: creds.secretAccessKey,
    region,
  });

  const maxAttempts = 4;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const started = Date.now();
      const res = await request({
        method: 'PUT',
        host,
        headers: signed.headers,
        bodyStream: createReadStream(file),
        contentLength: stat.size,
        path: signed.canonicalUri,
      });
      if (res.statusCode >= 200 && res.statusCode < 300) {
        const secs = ((Date.now() - started) / 1000).toFixed(1);
        const mbps = (
          stat.size /
          1024 /
          1024 /
          Math.max(Number(secs), 0.001)
        ).toFixed(1);
        if (!quiet) {
          console.log(
            `[r2-put] Uploaded ${formatBytes(stat.size)} in ${secs}s ` +
              `(${mbps} MB/s) -> https://maps.churchonapp.com/${key}`
          );
        }
        process.exit(0);
      }
      const detail = res.body.slice(0, 500);
      console.error(
        `[r2-put] HTTP ${res.statusCode} on attempt ${attempt}: ${detail}`
      );
      if (res.statusCode >= 400 && res.statusCode < 500 && res.statusCode !== 429) {
        process.exit(1); // client error — retrying will not help
      }
    } catch (err) {
      console.error(
        `[r2-put] network error on attempt ${attempt}: ${err.message}`
      );
    }
    if (attempt < maxAttempts) await sleep(1500 * attempt);
  }
  console.error('[r2-put] FAILED after all attempts');
  process.exit(1);
}

function hashFile(file) {
  return new Promise((resolve, reject) => {
    const hash = createHash('sha256');
    const stream = createReadStream(file);
    stream.on('error', reject);
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('end', () => resolve(hash.digest('hex')));
  });
}

function formatBytes(n) {
  if (n >= 1024 ** 3) return `${(n / 1024 ** 3).toFixed(2)} GB`;
  if (n >= 1024 ** 2) return `${(n / 1024 ** 2).toFixed(1)} MB`;
  if (n >= 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${n} B`;
}

main().catch((err) => {
  console.error(`[r2-put] ${err.stack || err.message}`);
  process.exit(1);
});
