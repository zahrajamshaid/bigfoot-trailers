/**
 * E2E Test Application Bootstrap
 *
 * Creates a fully configured NestJS test application that mirrors production
 * behavior (global prefix, validation pipe, exception filter, response envelope).
 *
 * Prerequisites:
 *   - DATABASE_URL must point to a dedicated test PostgreSQL database
 *   - Schema must be applied: `npx prisma db push`
 */
import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { AppModule } from '../../src/app.module';
import { PrismaService } from '../../src/prisma/prisma.service';
import { GlobalExceptionFilter } from '../../src/common/filters/http-exception.filter';
import { ResponseEnvelopeInterceptor } from '../../src/common/interceptors/response-envelope.interceptor';
import { globalValidationPipe } from '../../src/common/pipes/validation.pipe';

// Enable BigInt → Number serialisation in JSON responses
(BigInt.prototype as any).toJSON = function () {
  return Number(this);
};

export interface TestContext {
  app: INestApplication;
  prisma: PrismaService;
  httpServer: any;
}

export async function createTestApp(): Promise<TestContext> {
  // Relax rate limiting so rapid test requests are not throttled
  process.env.THROTTLE_TTL = '600000';
  process.env.THROTTLE_LIMIT = '10000';

  const moduleFixture: TestingModule = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();

  const app = moduleFixture.createNestApplication();

  // Mirror main.ts production configuration
  app.setGlobalPrefix('v1');
  app.useGlobalPipes(globalValidationPipe);
  app.useGlobalFilters(new GlobalExceptionFilter());
  app.useGlobalInterceptors(new ResponseEnvelopeInterceptor());

  await app.init();

  const prisma = app.get(PrismaService);

  return { app, prisma, httpServer: app.getHttpServer() };
}
