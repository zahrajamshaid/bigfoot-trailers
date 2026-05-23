import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    const connectionString = process.env.DATABASE_URL;
    // DO Managed PG presents a self-signed CA cert. node-pg validates strictly
    // by default; when this flag is on, skip chain validation while keeping
    // the connection encrypted. Safe because Managed DB lives on the private
    // VPC and traffic never leaves DO's network.
    const acceptInvalidCerts =
      process.env.DATABASE_SSL_ACCEPT_INVALID_CERTS === 'true';
    const adapter = new PrismaPg({
      connectionString,
      ...(acceptInvalidCerts && { ssl: { rejectUnauthorized: false } }),
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
