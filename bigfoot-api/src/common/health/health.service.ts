import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
import Redis from 'ioredis';

export interface HealthCheckResult {
  status: 'ok' | 'degraded' | 'down';
  uptime: number;
  timestamp: string;
  checks: {
    database: { status: 'ok' | 'down'; latencyMs: number };
    redis: { status: 'ok' | 'down'; latencyMs: number };
  };
}

@Injectable()
export class HealthService {
  private readonly logger = new Logger(HealthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async check(): Promise<HealthCheckResult> {
    const [db, redis] = await Promise.all([
      this.checkDatabase(),
      this.checkRedis(),
    ]);

    const allOk = db.status === 'ok' && redis.status === 'ok';
    const allDown = db.status === 'down' && redis.status === 'down';

    return {
      status: allOk ? 'ok' : allDown ? 'down' : 'degraded',
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
      checks: { database: db, redis },
    };
  }

  private async checkDatabase(): Promise<{ status: 'ok' | 'down'; latencyMs: number }> {
    const start = Date.now();
    try {
      await this.prisma.$queryRaw`SELECT 1`;
      return { status: 'ok', latencyMs: Date.now() - start };
    } catch (err) {
      this.logger.error('Database health check failed', (err as Error).message);
      return { status: 'down', latencyMs: Date.now() - start };
    }
  }

  private async checkRedis(): Promise<{ status: 'ok' | 'down'; latencyMs: number }> {
    const start = Date.now();
    let client: Redis | null = null;
    try {
      const host = this.config.get<string>('REDIS_HOST', 'localhost');
      const port = this.config.get<number>('REDIS_PORT', 6379);
      client = new Redis({ host, port, connectTimeout: 3000, lazyConnect: true });
      await client.connect();
      await client.ping();
      return { status: 'ok', latencyMs: Date.now() - start };
    } catch (err) {
      this.logger.error('Redis health check failed', (err as Error).message);
      return { status: 'down', latencyMs: Date.now() - start };
    } finally {
      if (client) {
        try { client.disconnect(); } catch { /* ignore */ }
      }
    }
  }
}
