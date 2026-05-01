#!/bin/sh
set -e

echo "→ Pushing Prisma schema to database..."
# The project uses prisma db push + raw SQL patches (no migration files).
# --accept-data-loss is required only when columns are dropped; safe on a
# fresh DB and on additive schema changes.
npx prisma db push --accept-data-loss

# Apply any one-off SQL patches that aren't in the Prisma schema (indexes,
# trigger functions, addon keys, etc.). Idempotent if patches use IF NOT EXISTS.
if [ -d /app/prisma/sql-patches ] && [ -n "$(ls -A /app/prisma/sql-patches 2>/dev/null)" ]; then
  echo "→ Applying SQL patches..."
  for patch in /app/prisma/sql-patches/*.sql; do
    [ -e "$patch" ] || continue
    echo "  - $(basename "$patch")"
    npx prisma db execute --file "$patch" || \
      echo "  ! patch $(basename "$patch") failed (may already be applied) — continuing"
  done
fi

echo "→ Starting Bigfoot API..."
exec node dist/src/main
