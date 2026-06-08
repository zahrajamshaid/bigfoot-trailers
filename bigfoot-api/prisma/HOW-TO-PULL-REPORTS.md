# How to pull a report from the production database

You have two ways to get data out of the prod DB without my involvement:

1. **Run an existing report script** — when the question is one you've
   asked before (or is close to one), trigger an existing TS script from
   the GitHub Actions UI. Logs appear in the run output.
2. **Run an ad-hoc read-only SQL query** — when the question is brand
   new, paste a `SELECT` statement into the `DB · Query (manual)`
   workflow. Same output channel; no commit needed.

Both go through the same secure pathway: GitHub Actions → SSH into the
droplet → `docker exec` into the prod API container → talk to Postgres
through the same Prisma client the app uses. You never touch the DB
URL or run anything on your own machine.

---

## Path A: Existing report scripts (fastest for recurring questions)

Every script in `bigfoot-api/prisma/` whose name starts with `qc-`,
`fix-`, `seed-`, `apply-`, or `stats-` is wired into the
`DB · Seed (manual)` workflow. To run one:

1. Open https://github.com/zahrajamshaid/bigfoot-trailers/actions
2. Click **DB · Seed (manual)** in the sidebar
3. Click **Run workflow** (top-right)
4. Pick the script from the dropdown
5. Click the green **Run workflow** button
6. Wait ~30 seconds; click into the run and read the `out:` lines

### Useful ones already in the dropdown

| Script | What it does |
|---|---|
| `qc-today-report` | Every QC inspection submitted today — SO, dept, pass/fail, inspector |
| `stats-trailers` | Trailer counts across lifecycle / stock yards / series |
| `fix-batches-back-to-building` | (Write) flip scheduled batches with no dispatched deliveries back to building |
| `fix-mulberry-open-stock-and-6567` | (Write) the Mulberry inventory cleanup |

The full list lives in
[`.github/workflows/db-seed.yml`](../../.github/workflows/db-seed.yml).

### Anatomy of a report script

Open [`qc-today-report.ts`](./qc-today-report.ts) — it's the cleanest
example. Every script follows the same shape:

```ts
// 1. Boilerplate — always the same.
import 'dotenv/config';
import { createPrismaClient } from './db-client';
const prisma = createPrismaClient();

async function main(): Promise<void> {
  // 2. Run a Prisma query. This is the only line that changes per report.
  const inspections = await prisma.qcInspection.findMany({
    where: { inspectedAt: { gte: startOfDay(new Date()) } },
    select: { trailer: { select: { soNumber: true } }, result: true },
  });

  // 3. Print results. The log shows whatever you console.log.
  for (const i of inspections) {
    console.log(`  ${i.trailer.soNumber}  ${i.result}`);
  }
}

main()
  .catch((e) => { console.error('❌ Report failed:', e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });
```

To write a new recurring report, copy `qc-today-report.ts`, rename, edit
the query in the middle, add the new filename (without `.ts`) to
the `options:` list at the bottom of
[`db-seed.yml`](../../.github/workflows/db-seed.yml), commit + push.

---

## Path B: Ad-hoc SELECT queries (fastest for one-off questions)

When you just want to answer a one-off question without committing a
script:

1. Open https://github.com/zahrajamshaid/bigfoot-trailers/actions
2. Click **DB · Query (manual)** in the sidebar
3. Click **Run workflow**
4. Paste your `SELECT` statement in the `sql` box
5. (Optional) set `limit` — defaults to 50 rows shown
6. Run; results appear as a table in the log

Safety: the runner refuses anything that isn't `SELECT` or `WITH`
(common table expressions). No `UPDATE`, `DELETE`, `DROP`, `INSERT`,
`ALTER`, `TRUNCATE` will execute — the workflow rejects them before
talking to Postgres. So you can paste with confidence; the worst you
can do is fail the run.

### Copy-paste recipes

Most useful queries answered by hand-rolled SQL. Tables match the
Prisma schema with snake_case column names.

#### Today's deliveries (any status)

```sql
SELECT d.id, t.so_number, d.delivery_type, d.status, d.scheduled_date,
       l.code AS destination, d.created_at
  FROM deliveries d
  JOIN trailers t ON t.id = d.trailer_id
  LEFT JOIN locations l ON l.id = d.destination_location_id
 WHERE d.created_at >= CURRENT_DATE
 ORDER BY d.created_at DESC;
```

#### Trailers currently at Mulberry that are NOT sold

```sql
SELECT t.so_number, tm.display_name AS model, t.is_stock_build,
       t.sale_status, t.sold_to_name, t.created_at
  FROM trailers t
  JOIN locations l ON l.id = t.current_location_id
  LEFT JOIN trailer_models tm ON tm.id = t.trailer_model_id
 WHERE l.code = 'MULBERRY'
   AND t.sale_status = 'available'
 ORDER BY t.created_at DESC;
```

#### How many trailers each user has created this month

```sql
SELECT u.full_name, COUNT(*) AS trailers_created
  FROM trailers t
  JOIN users u ON u.id = t.created_by_user_id
 WHERE t.created_at >= DATE_TRUNC('month', CURRENT_DATE)
 GROUP BY u.full_name
 ORDER BY trailers_created DESC;
```

#### QC pass / fail rate per inspector, last 30 days

```sql
SELECT u.full_name,
       COUNT(*) FILTER (WHERE result = 'pass') AS passes,
       COUNT(*) FILTER (WHERE result = 'fail') AS fails,
       ROUND(100.0 * COUNT(*) FILTER (WHERE result = 'pass') / COUNT(*), 1)
         AS pass_rate
  FROM qc_inspections q
  JOIN users u ON u.id = q.inspector_user_id
 WHERE q.inspected_at >= CURRENT_DATE - INTERVAL '30 days'
 GROUP BY u.full_name
 ORDER BY passes DESC;
```

#### Production-step backlog by department

```sql
SELECT d.code AS dept, COUNT(*) AS waiting
  FROM production_steps ps
  JOIN departments d ON d.id = ps.department_id
 WHERE ps.status = 'waiting'
 GROUP BY d.code
 ORDER BY waiting DESC;
```

#### Open delivery batches with their trailer counts

```sql
SELECT db.batch_number, db.status,
       COUNT(d.id) AS trailer_count, db.created_at
  FROM delivery_batches db
  LEFT JOIN deliveries d ON d.delivery_batch_id = db.id
 WHERE db.status IN ('building', 'scheduled')
 GROUP BY db.id
 ORDER BY db.created_at DESC;
```

#### Trailers stuck on a department for more than 3 days

```sql
SELECT t.so_number, dept.code AS dept,
       ps.became_active_at,
       AGE(NOW(), ps.became_active_at) AS stuck_for
  FROM production_steps ps
  JOIN trailers t ON t.id = ps.trailer_id
  JOIN departments dept ON dept.id = ps.department_id
 WHERE ps.status = 'active'
   AND ps.became_active_at < NOW() - INTERVAL '3 days'
 ORDER BY ps.became_active_at;
```

---

## Things to know

- **Time zone**: the prod container runs UTC. `CURRENT_DATE` and `NOW()`
  return UTC. If you need Florida time, write
  `CURRENT_DATE AT TIME ZONE 'America/New_York'`.
- **Snake case vs camel case**: SQL uses the *database* column names
  (snake_case: `so_number`, `is_stock_build`). Prisma scripts use the
  *Prisma model* field names (camelCase: `soNumber`, `isStockBuild`).
  The mapping is in [`schema.prisma`](./schema.prisma)'s `@map`
  annotations.
- **BigInts**: most IDs in this schema are `BigInt`. The runner stringifies
  them on the way out so the log stays readable — no `0n` suffix
  weirdness.
- **Logs are world-readable** to anyone with repo access. Don't paste
  customer PII / payment details into ad-hoc SQL unless you'd be
  comfortable with the rest of the team seeing them in the run log.
