import { readFileSync } from 'node:fs';
import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    const connectionString = process.env.DATABASE_URL;
    // DO Managed PG signs its cert with a private CA. We validate it
    // strictly against that CA — no rejectUnauthorized=false shortcuts.
    // Path to the CA cert file is read from DATABASE_SSL_CA_PATH and the
    // file is mounted into the container (see docker-compose.prod.yml).
    const caPath = process.env.DATABASE_SSL_CA_PATH;
    const ssl = caPath
      ? { ca: readFileSync(caPath, 'utf8'), rejectUnauthorized: true }
      : undefined;
    const adapter = new PrismaPg({
      connectionString,
      ...(ssl && { ssl }),
    });
    super({ adapter, log: ['query', 'info', 'warn', 'error'] });
  }

  async onModuleInit(): Promise<void> {
    await this.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
