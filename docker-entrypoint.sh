#!/bin/sh
# ============================================================================
# Deadline Board — container start-up
#
# Writes /srv/public/config.js from the Railway environment variables, then
# hands control to Caddy.
#
# WHY THIS EXISTS
# Under GitHub Pages the Supabase settings had to be committed to the
# repository, because a static host cannot inject anything. Railway runs a real
# container, so the settings can come from environment variables instead and
# nothing sensitive needs to live in Git at all.
#
# The anon key is public by design and ends up readable in the browser either
# way. The point of this script is the safety check below: if someone pastes a
# service_role / secret key into the anon variable by mistake, the deploy fails
# loudly instead of publishing a key that bypasses every database rule.
# ============================================================================

set -eu

PUBLIC_DIR="${PUBLIC_DIR:-/srv/public}"
CONFIG_FILE="$PUBLIC_DIR/config.js"

URL="${SUPABASE_URL:-}"
KEY="${SUPABASE_ANON_KEY:-}"

say()  { printf '%s\n' "$*"; }
fail() {
  say ""
  say "============================================================"
  say " DEPLOY STOPPED — $1"
  say "============================================================"
  say ""
  shift
  for line in "$@"; do say "  $line"; done
  say ""
  exit 1
}

# ---------------------------------------------------------------------------
# Decode the payload of a JWT so we can read its "role" claim.
# JWTs are base64url: the alphabet uses - and _ , and padding is stripped.
# ---------------------------------------------------------------------------
jwt_payload() {
  p=$(printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+')
  case $(( ${#p} % 4 )) in
    2) p="${p}==" ;;
    3) p="${p}="  ;;
  esac
  printf '%s' "$p" | base64 -d 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 1. Refuse to publish a secret key. This is the whole reason for the script.
#
#    Supabase issues two kinds of key:
#      publishable / anon  -> safe in a browser, grants nothing by itself
#      secret / service_role -> bypasses ALL Row Level Security
#
#    Both are long opaque strings and they are easy to confuse in the
#    dashboard. Publishing the second one would hand every visitor full read
#    and write access to the database, so it must never reach config.js.
# ---------------------------------------------------------------------------
if [ -n "$KEY" ]; then
  case "$KEY" in
    sb_secret_*)
      fail "a SECRET Supabase key was supplied" \
        "SUPABASE_ANON_KEY starts with 'sb_secret_', which is the secret key." \
        "That key bypasses every database permission rule and must never be" \
        "sent to a browser." \
        "" \
        "Fix: Supabase dashboard -> Project Settings -> API Keys, and copy the" \
        "key labelled 'publishable' (or 'anon public' on older projects)." \
        "" \
        "If this key has already been exposed anywhere, rotate it on that page."
      ;;
  esac

  # Legacy JWT-style keys: check the role claim.
  case "$KEY" in
    eyJ*)
      PAYLOAD=$(jwt_payload "$KEY")
      case "$PAYLOAD" in
        *service_role*)
          fail "a SERVICE-ROLE Supabase key was supplied" \
            "SUPABASE_ANON_KEY decodes to a token with role \"service_role\"." \
            "That key bypasses every database permission rule and must never" \
            "be sent to a browser." \
            "" \
            "Fix: Supabase dashboard -> Project Settings -> API, and copy the" \
            "key labelled 'anon public' instead." \
            "" \
            "This key is now in your Railway variables, so rotate it in the" \
            "Supabase dashboard as a precaution."
          ;;
      esac
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# 2. Validate the shape of both values.
#
#    Rather than trying to escape arbitrary text into a JavaScript file, we
#    accept only the characters these values are actually made of. Anything
#    else is a typo (a trailing quote, a pasted shell command, a stray
#    newline) and is rejected rather than written out.
# ---------------------------------------------------------------------------
CONFIGURED="false"
PROBLEM=""

if [ -z "$URL" ] || [ -z "$KEY" ]; then
  PROBLEM="SUPABASE_URL and SUPABASE_ANON_KEY are not both set in Railway."
elif ! printf '%s' "$URL" | grep -Eq '^https://[A-Za-z0-9._-]+(:[0-9]+)?/?$'; then
  PROBLEM="SUPABASE_URL does not look like a project URL (expected https://xxxx.supabase.co)."
elif ! printf '%s' "$KEY" | grep -Eq '^[A-Za-z0-9._-]{20,}$'; then
  PROBLEM="SUPABASE_ANON_KEY contains unexpected characters or is too short."
else
  CONFIGURED="true"
  URL=$(printf '%s' "$URL" | sed 's:/*$::')   # drop any trailing slash
fi

# ---------------------------------------------------------------------------
# 3. Write config.js.
#
#    It is written on every start, so a redeploy always picks up the current
#    variables, and Caddy serves it with Cache-Control: no-store.
#
#    When the values are missing we still write the file and still start the
#    server, with configured:false. The application can then show a clear
#    message instead of the page failing with a console error nobody sees.
# ---------------------------------------------------------------------------
mkdir -p "$PUBLIC_DIR"

if [ "$CONFIGURED" = "true" ]; then
  cat > "$CONFIG_FILE" <<EOF
/* Generated at container start-up from Railway environment variables.
   Do not edit, and do not commit this file: it is overwritten on every deploy. */
window.DEADLINE_BOARD_CONFIG = {
  SUPABASE_URL: "$URL",
  SUPABASE_ANON_KEY: "$KEY",
  configured: true,
  generatedAt: "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
};
EOF
  say "[deadline-board] Supabase configured for $URL"
else
  cat > "$CONFIG_FILE" <<EOF
/* Generated at container start-up. Supabase is NOT configured. */
window.DEADLINE_BOARD_CONFIG = {
  SUPABASE_URL: null,
  SUPABASE_ANON_KEY: null,
  configured: false,
  problem: "$PROBLEM",
  generatedAt: "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
};
console.warn("[deadline-board] Supabase is not configured: $PROBLEM");
EOF
  say ""
  say "============================================================"
  say " Supabase is NOT configured — the board is running offline"
  say "============================================================"
  say "  $PROBLEM"
  say ""
  say "  The site is up and will serve normally, but sign-in and"
  say "  shared data are inactive until this is set."
  say ""
  say "  Fix: Railway -> your service -> Variables, and add"
  say "         SUPABASE_URL        https://<your-ref>.supabase.co"
  say "         SUPABASE_ANON_KEY   <the publishable / anon key>"
  say "       Railway redeploys automatically when you save."
  say "============================================================"
  say ""
fi

say "[deadline-board] serving $PUBLIC_DIR on port ${PORT:-8080}"

# exec so Caddy becomes PID 1 and receives Railway's shutdown signals directly.
exec "$@"
