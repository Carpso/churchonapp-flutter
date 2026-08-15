#!/usr/bin/env bash
# Secret Scanner — fails CI when a live credential is committed.
# Scans only git-tracked files (google-services.json, .env, keystores are
# gitignored and never reach the checkout). Allowlisted: web/index.html
# carries the PUBLIC Firebase web config (apiKey is client-side by design).
set -uo pipefail

PATTERNS=(
  'AKIA[0-9A-Z]{16}'                          # AWS access key
  'ghp_[A-Za-z0-9]{36}'                       # GitHub PAT
  'github_pat_[A-Za-z0-9_]{20,}'              # GitHub fine-grained PAT
  'sk_live_[A-Za-z0-9]{20,}'                  # Stripe live key
  'sk-[A-Za-z0-9]{20,}'                       # OpenAI key
  'sk-ant-[A-Za-z0-9_-]{20,}'                 # Anthropic key
  'sbp_[A-Za-z0-9]{40,}'                      # Supabase mgmt PAT
  'sb_secret_[A-Za-z0-9]{40,}'                # Supabase function secret
  'lsk_[A-Za-z0-9]{20,}'                      # Lipila key
  'xox[baprs]-[A-Za-z0-9-]{10,}'              # Slack token
  'xoxc-[A-Za-z0-9-]{10,}'                    # Slack cookie token
  'hf_[A-Za-z0-9]{20,}'                       # HuggingFace token
  're_[A-Za-z0-9]{20,}'                       # Resend key
  'SG\.[A-Za-z0-9_-]{20,}'                    # SendGrid key
  'cfut_[A-Za-z0-9]{20,}'                     # Cloudflare upload token
  'BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY' # Private keys
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' # JWT (hardcoded)
)

FAILED=0
while IFS= read -r file; do
  [ -z "$file" ] && continue
  case "$file" in
    web/index.html|*.md) continue ;; # public Firebase web config / docs
  esac
  for pattern in "${PATTERNS[@]}"; do
    if grep -qE -- "$pattern" "$file" 2>/dev/null; then
      echo "::error::Potential secret matched '$pattern' in $file"
      FAILED=1
    fi
  done
done < <(git ls-files)

if [ "$FAILED" -ne 0 ]; then
  echo "::error::Secret scan failed — remove the flagged values (use Edge Function env / GitHub secrets instead)."
  exit 1
fi

echo "✅ Secret scan clean ($(git ls-files | wc -l) tracked files)"