import { Global, Module } from '@nestjs/common';
import { FeatureFlagsService } from './feature-flags.service';

/**
 * Global so any feature module can inject FeatureFlagsService without
 * re-importing it. ConfigModule is already global (app.module), so the
 * service's ConfigService dependency resolves everywhere.
 */
@Global()
@Module({
  providers: [FeatureFlagsService],
  exports: [FeatureFlagsService],
})
export class FeatureFlagsModule {}
