// =============================================================================
// Bigfoot Trailers — PrismaClient factory for standalone scripts (seeds,
// migrations, one-off jobs). Mirrors src/prisma/prisma.service.ts so DO
// Managed Postgres's private CA cert validation works identically.
// =============================================================================

import { readFileSync } from 'node:fs';
import { PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';

export function createPrismaClient(): PrismaClient {
  const connectionString = process.env['DATABASE_URL'];
  if (!connectionString) {
    throw new Error('DATABASE_URL is required');
  }
  // DO Managed PG presents a cert signed by a private CA. We validate it
  // strictly against that CA — no rejectUnauthorized=false shortcuts.
  // CA path is set via DATABASE_SSL_CA_PATH; the file is mounted into the
  // api container by docker-compose.prod.yml.
  const caPath = process.env['DATABASE_SSL_CA_PATH'];
  const ssl = caPath
    ? { ca: readFileSync(caPath, 'utf8'), rejectUnauthorized: true }
    : undefined;
  const adapter = new PrismaPg({
    connectionString,
    ...(ssl && { ssl }),
  });
  return new PrismaClient({ adapter });
}
