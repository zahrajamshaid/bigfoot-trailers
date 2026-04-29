#!/bin/sh
set -e

echo "→ Running Prisma migrations..."
npx prisma migrate deploy

echo "→ Starting Bigfoot API..."
exec node dist/main
