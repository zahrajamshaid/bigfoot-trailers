import { Module, MiddlewareConsumer, NestModule } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard } from '@nestjs/throttler';

// Configuration
import { validateEnv } from './common/config/env.validation';

// Infrastructure
import { PrismaModule } from './prisma/prisma.module';

// Health
import { HealthModule } from './common/health/health.module';

// Feature modules
import { AuthModule } from './modules/auth/auth.module';
import { UsersModule } from './modules/users/users.module';
import { TrailersModule } from './modules/trailers/trailers.module';
import { ProductionModule } from './modules/production/production.module';
import { QcModule } from './modules/qc/qc.module';
import { PayrollModule } from './modules/payroll/payroll.module';
import { DeliveriesModule } from './modules/deliveries/deliveries.module';
import { CustomersModule } from './modules/customers/customers.module';
import { LocationsModule } from './modules/locations/locations.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { StorageModule } from './modules/storage/storage.module';
import { AdminModule } from './modules/admin/admin.module';
import { JobsModule } from './modules/jobs/jobs.module';

// Guards
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { RolesGuard } from './common/guards/roles.guard';

// Middleware
import { RequestLoggerMiddleware } from './common/middleware/request-logger.middleware';
import { SanitizeMiddleware } from './common/middleware/sanitize.middleware';

@Module({
  imports: [
    // ---- Configuration (fail fast on missing vars) ----
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env',
      validate: validateEnv,
    }),

    // ---- Rate Limiting: 100 req/min general ----
    // Admin and payroll controllers override with stricter per-route limits
    // via @Throttle() (see each controller).
    ThrottlerModule.forRoot([
      {
        name: 'default',
        ttl: parseInt(process.env['THROTTLE_TTL'] || '60000', 10),
        limit: parseInt(process.env['THROTTLE_LIMIT'] || '100', 10),
      },
    ]),

    // ---- Infrastructure ----
    PrismaModule,

    // ---- Health Check ----
    HealthModule,

    // ---- Feature Modules (12 modules per architecture doc Section 3.2) ----
    AuthModule,
    UsersModule,
    TrailersModule,
    ProductionModule,
    QcModule,
    PayrollModule,
    DeliveriesModule,
    CustomersModule,
    LocationsModule,
    NotificationsModule,
    StorageModule,
    AdminModule,
    JobsModule,
  ],
  providers: [
    // Global guards — execution order: Throttler → JWT → Roles
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
    {
      provide: APP_GUARD,
      useClass: JwtAuthGuard,
    },
    {
      provide: APP_GUARD,
      useClass: RolesGuard,
    },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    consumer
      .apply(RequestLoggerMiddleware, SanitizeMiddleware)
      .forRoutes('*');
  }
}
