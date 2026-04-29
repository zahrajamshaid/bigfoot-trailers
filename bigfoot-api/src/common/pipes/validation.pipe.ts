import { ValidationPipe as NestValidationPipe } from '@nestjs/common';

/**
 * Global validation pipe configured for Bigfoot Trailers.
 * - whitelist: strips properties not in the DTO (prevents mass assignment)
 * - forbidNonWhitelisted: returns 400 if unknown properties are sent
 * - transform: auto-transforms payloads to DTO class instances
 */
export const globalValidationPipe = new NestValidationPipe({
  whitelist: true,
  forbidNonWhitelisted: true,
  transform: true,
  transformOptions: {
    enableImplicitConversion: true,
  },
});
