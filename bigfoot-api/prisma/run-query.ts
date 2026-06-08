// =============================================================================
// BIGFOOT TRAILERS — Read-only ad-hoc SQL runner
//
// Reads a SELECT (or WITH … SELECT) statement from the BIGFOOT_SQL env
// var, executes it via Prisma's $queryRawUnsafe, and prints the result
// rows as a fixed-width table. Designed to be driven by the
// `DB · Query (manual)` GitHub Actions workflow so the operator can paste
// a one-off question into the workflow_dispatch UI and read the answer
// in the run log — no commit required.
//
// Strict safety guarantees:
//   • The SQL must start with `SELECT` or `WITH` (case-insensitive)
//     after stripping leading whitespace and SQL comments. Anything
//     beginning with INSERT, UPDATE, DELETE, DROP, TRUNCATE, ALTER, CREATE,
//     GRANT, REVOKE, COPY, CALL, REINDEX, VACUUM, COMMENT, SECURITY, etc.,
//     is rejected before talking to Postgres.
//   • Multiple statements separated by `;` are rejected (defends against
//     `SELECT 1; DELETE FROM foo;` style smuggling).
//   • Output is capped at BIGFOOT_LIMIT rows (default 50) — too-wide
//     queries don't blow up the workflow log.
//
// The runner uses Prisma's $queryRawUnsafe deliberately: the safety check
// runs *before* the SQL hits the database, and we want raw column names
// (not Prisma's camelCase remap) so the operator sees what's in the table.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DEFAULT_LIMIT = 50;
const MAX_COLUMN_WIDTH = 60;

/**
 * Strips leading whitespace and SQL `--` line comments + `/* … *​/`
 * block comments so the safety check sees the first real token.
 */
function stripLeadingNoise(sql: string): string {
  let s = sql.trimStart();
  // Strip leading block comments
  while (s.startsWith('/*')) {
    const end = s.indexOf('*/');
    if (end === -1) break;
    s = s.slice(end + 2).trimStart();
  }
  // Strip leading line comments
  while (s.startsWith('--')) {
    const nl = s.indexOf('\n');
    if (nl === -1) {
      s = '';
      break;
    }
    s = s.slice(nl + 1).trimStart();
  }
  return s;
}

/**
 * Throws if the SQL is anything other than a single read-only SELECT
 * or WITH … SELECT.
 */
function assertReadOnly(sql: string): void {
  const head = stripLeadingNoise(sql);
  if (!head) {
    throw new Error('SQL is empty.');
  }
  const firstWord = head.match(/^(\w+)/)?.[1]?.toUpperCase();
  if (firstWord !== 'SELECT' && firstWord !== 'WITH') {
    throw new Error(
      `Refusing to run: SQL must start with SELECT or WITH (got "${firstWord}"). ` +
        `This runner is read-only — use a TS script in prisma/ for writes.`,
    );
  }

  // Reject multi-statement SQL. A trailing semicolon is fine; anything
  // after it isn't.
  const withoutTrailing = sql.replace(/;\s*$/, '');
  if (withoutTrailing.includes(';')) {
    throw new Error(
      'Refusing to run: multiple statements detected. Run them one at a time.',
    );
  }
}

function formatCell(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (typeof value === 'bigint') return value.toString();
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function truncate(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max - 1) + '…';
}

/** Pretty-print rows as a fixed-width table with auto-sized columns. */
function printTable(rows: Record<string, unknown>[]): void {
  if (rows.length === 0) {
    console.log('  (no rows returned)');
    return;
  }
  const headers = Object.keys(rows[0]);
  const widths = headers.map((h) =>
    Math.max(
      h.length,
      ...rows.map((r) =>
        Math.min(MAX_COLUMN_WIDTH, formatCell(r[h]).length),
      ),
    ),
  );

  const headerLine = headers
    .map((h, i) => truncate(h, widths[i]).padEnd(widths[i]))
    .join('  ');
  const sepLine = widths.map((w) => '─'.repeat(w)).join('  ');

  console.log('  ' + headerLine);
  console.log('  ' + sepLine);
  for (const row of rows) {
    const line = headers
      .map((h, i) => truncate(formatCell(row[h]), widths[i]).padEnd(widths[i]))
      .join('  ');
    console.log('  ' + line);
  }
}

async function main(): Promise<void> {
  const sql = process.env['BIGFOOT_SQL'];
  if (!sql || !sql.trim()) {
    throw new Error(
      'BIGFOOT_SQL env var is empty. Pass the query through the workflow input.',
    );
  }
  const limitRaw = process.env['BIGFOOT_LIMIT'];
  const limit = limitRaw ? parseInt(limitRaw, 10) : DEFAULT_LIMIT;
  if (!Number.isFinite(limit) || limit < 1) {
    throw new Error(`BIGFOOT_LIMIT must be a positive integer (got "${limitRaw}").`);
  }

  assertReadOnly(sql);

  console.log('📥 Running query:');
  for (const line of sql.split('\n')) {
    console.log('    ' + line);
  }
  console.log('');

  const t0 = Date.now();
  const rows = (await prisma.$queryRawUnsafe(sql)) as Record<string, unknown>[];
  const elapsed = Date.now() - t0;

  console.log(`📊 ${rows.length} row(s) returned in ${elapsed}ms`);
  if (rows.length > limit) {
    console.log(`   (showing first ${limit}; raise BIGFOOT_LIMIT to see more)`);
  }
  console.log('');

  printTable(rows.slice(0, limit));
}

main()
  .catch((e) => {
    console.error('❌ Query failed:', e.message ?? e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
