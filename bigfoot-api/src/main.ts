// BigInt JSON serialization — Prisma returns BigInt for BIGSERIAL PKs
(BigInt.prototype as any).toJSON = function () {
  return Number(this);
};

import { NestFactory } from '@nestjs/core';
import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import * as express from 'express';
import { AppModule } from './app.module';
import { GlobalExceptionFilter } from './common/filters/http-exception.filter';
import { ResponseEnvelopeInterceptor } from './common/interceptors/response-envelope.interceptor';
import { LoggingInterceptor } from './common/interceptors/logging.interceptor';
import { globalValidationPipe } from './common/pipes/validation.pipe';
import { PrismaService } from './prisma/prisma.service';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  const config = app.get(ConfigService);
  const logger = new Logger('Bootstrap');

  // ── Global prefix ────────────────────────────────────────────────────────
  const apiPrefix = config.get<string>('API_PREFIX', 'v1');
  app.setGlobalPrefix(apiPrefix, {
    exclude: ['health'], // health check at /health (no prefix)
  });

  // ── Security headers (Helmet) ────────────────────────────────────────────
  app.use(
    helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          scriptSrc: ["'self'"],
          styleSrc: ["'self'", "'unsafe-inline'"], // Swagger needs inline styles
          imgSrc: ["'self'", 'data:'],
          connectSrc: ["'self'"],
        },
      },
      crossOriginEmbedderPolicy: false, // allow Swagger UI
      hsts: {
        maxAge: 31536000, // 1 year
        includeSubDomains: true,
        preload: true,
      },
      referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
    }),
  );

  // ── File upload size limits (10 MB JSON, 50 MB multipart) ────────────────
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));

  // ── CORS ─────────────────────────────────────────────────────────────────
  const corsOrigins = config.get<string>('CORS_ORIGINS', '');
  const allowedOrigins = corsOrigins
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
  app.enableCors({
    origin: (origin, callback) => {
      if (!origin) {
        callback(null, true);
        return;
      }

      try {
        const parsed = new URL(origin);
        const isLocalhost =
          parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1';
        if (isLocalhost || allowedOrigins.includes(origin)) {
          callback(null, true);
          return;
        }
      } catch (_) {
        // Fall through to the explicit allowlist.
      }

      if (allowedOrigins.includes(origin)) {
        callback(null, true);
        return;
      }

      callback(new Error(`CORS blocked origin: ${origin}`), false);
    },
    credentials: true,
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    maxAge: 86400, // preflight cache 24h
  });

  // ── Global pipes, filters, interceptors ──────────────────────────────────
  app.useGlobalPipes(globalValidationPipe);
  app.useGlobalFilters(new GlobalExceptionFilter());
  app.useGlobalInterceptors(
    new LoggingInterceptor(),
    new ResponseEnvelopeInterceptor(),
  );

  // ── Swagger / OpenAPI (disabled in production) ───────────────────────────
  const nodeEnv = config.get<string>('NODE_ENV', 'development');
  if (nodeEnv !== 'production') {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('Bigfoot Trailers API')
      .setDescription(
        'Production management system for Bigfoot Trailers. ' +
        'Covers trailer lifecycle, production workflows, QC inspections, ' +
        'payroll, delivery logistics, and real-time notifications.',
      )
      .setVersion('1.3')
      .addBearerAuth(
        {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT',
          description: 'Enter your JWT access token',
        },
        'JWT',
      )
      .addTag('Health', 'Health check')
      .addTag('Auth', 'Authentication & token management')
      .addTag('Users', 'User CRUD & role management')
      .addTag('Trailers', 'Trailer lifecycle & workflow generation')
      .addTag('Production', 'Department queues & step completion')
      .addTag('Quality Control', 'QC inspections & rework routing')
      .addTag('Payroll', 'Points-based compensation & weekly reports')
      .addTag('Deliveries', 'Delivery logistics & driver tracking')
      .addTag('Customers', 'Customer management')
      .addTag('Storage', 'File uploads & pre-signed URLs')
      .addTag('Admin', 'Workflow config, audit log & reports')
      .build();

    const document = SwaggerModule.createDocument(app, swaggerConfig);
    SwaggerModule.setup('docs', app, document, {
      swaggerOptions: {
        persistAuthorization: true,
      },
    });
  }

  // ── Graceful shutdown ────────────────────────────────────────────────────
  app.enableShutdownHooks();

  const prisma = app.get(PrismaService);

  const shutdown = async (signal: string) => {
    logger.log(`Received ${signal} — starting graceful shutdown`);
    await prisma.$disconnect();
    logger.log('Database connections closed');
    process.exit(0);
  };

  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));

  // ── Start ────────────────────────────────────────────────────────────────
  const port = config.get<number>('PORT', 3000);
  await app.listen(port);
  logger.log(`Bigfoot API running on http://localhost:${port}/${apiPrefix}`);
  logger.log(`Environment: ${nodeEnv}`);
  if (nodeEnv !== 'production') {
    logger.log(`Swagger docs at http://localhost:${port}/docs`);
  }
}

void bootstrap();
