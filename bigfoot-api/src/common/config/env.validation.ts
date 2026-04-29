import { Logger } from '@nestjs/common';

/**
 * Validates required environment variables at startup.
 * Called from ConfigModule.forRoot({ validate }) — fails fast
 * if any critical variable is missing.
 */

interface ValidatedEnv {
  NODE_ENV: string;
  PORT: number;
  DATABASE_URL: string;
  REDIS_HOST: string;
  REDIS_PORT: number;
  JWT_SECRET: string;
  JWT_ACCESS_EXPIRY: string;
  JWT_REFRESH_EXPIRY: string;
  CORS_ORIGINS: string;
  DO_SPACES_ENDPOINT: string;
  DO_SPACES_REGION: string;
  DO_SPACES_BUCKET: string;
  DO_SPACES_ACCESS_KEY: string;
  DO_SPACES_SECRET_KEY: string;
  TWILIO_ACCOUNT_SID: string;
  TWILIO_AUTH_TOKEN: string;
  TWILIO_PHONE_NUMBER: string;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_CLIENT_EMAIL: string;
  THROTTLE_TTL: number;
  THROTTLE_LIMIT: number;
}

const REQUIRED_VARS = [
  'DATABASE_URL',
  'JWT_SECRET',
  'REDIS_HOST',
] as const;

const REQUIRED_IN_PRODUCTION = [
  'DO_SPACES_ENDPOINT',
  'DO_SPACES_REGION',
  'DO_SPACES_BUCKET',
  'DO_SPACES_ACCESS_KEY',
  'DO_SPACES_SECRET_KEY',
  'TWILIO_ACCOUNT_SID',
  'TWILIO_AUTH_TOKEN',
  'TWILIO_PHONE_NUMBER',
  'FIREBASE_PROJECT_ID',
  'FIREBASE_CLIENT_EMAIL',
  'CORS_ORIGINS',
] as const;

export function validateEnv(
  config: Record<string, unknown>,
): ValidatedEnv {
  const logger = new Logger('EnvValidation');
  const errors: string[] = [];

  // Always required
  for (const key of REQUIRED_VARS) {
    if (!config[key]) {
      errors.push(`Missing required env var: ${key}`);
    }
  }

  // JWT_SECRET strength check
  const jwtSecret = config['JWT_SECRET'] as string | undefined;
  if (jwtSecret && jwtSecret.length < 32) {
    errors.push('JWT_SECRET must be at least 32 characters');
  }
  if (jwtSecret === 'CHANGE_ME_TO_A_64_CHAR_RANDOM_STRING') {
    errors.push('JWT_SECRET is still set to the default placeholder — generate a real secret');
  }

  // Production-only requirements
  const nodeEnv = (config['NODE_ENV'] as string) || 'development';
  if (nodeEnv === 'production') {
    for (const key of REQUIRED_IN_PRODUCTION) {
      if (!config[key]) {
        errors.push(`Missing env var required in production: ${key}`);
      }
    }
  }

  if (errors.length > 0) {
    for (const err of errors) {
      logger.error(err);
    }
    throw new Error(
      `Environment validation failed:\n${errors.map((e) => `  - ${e}`).join('\n')}`,
    );
  }

  return {
    NODE_ENV: nodeEnv,
    PORT: parseInt(config['PORT'] as string, 10) || 3000,
    DATABASE_URL: config['DATABASE_URL'] as string,
    REDIS_HOST: (config['REDIS_HOST'] as string) || 'localhost',
    REDIS_PORT: parseInt(config['REDIS_PORT'] as string, 10) || 6379,
    JWT_SECRET: config['JWT_SECRET'] as string,
    JWT_ACCESS_EXPIRY: (config['JWT_ACCESS_EXPIRY'] as string) || '15m',
    JWT_REFRESH_EXPIRY: (config['JWT_REFRESH_EXPIRY'] as string) || '7d',
    CORS_ORIGINS: (config['CORS_ORIGINS'] as string) || '',
    DO_SPACES_ENDPOINT: (config['DO_SPACES_ENDPOINT'] as string) || '',
    DO_SPACES_REGION: (config['DO_SPACES_REGION'] as string) || '',
    DO_SPACES_BUCKET: (config['DO_SPACES_BUCKET'] as string) || '',
    DO_SPACES_ACCESS_KEY: (config['DO_SPACES_ACCESS_KEY'] as string) || '',
    DO_SPACES_SECRET_KEY: (config['DO_SPACES_SECRET_KEY'] as string) || '',
    TWILIO_ACCOUNT_SID: (config['TWILIO_ACCOUNT_SID'] as string) || '',
    TWILIO_AUTH_TOKEN: (config['TWILIO_AUTH_TOKEN'] as string) || '',
    TWILIO_PHONE_NUMBER: (config['TWILIO_PHONE_NUMBER'] as string) || '',
    FIREBASE_PROJECT_ID: (config['FIREBASE_PROJECT_ID'] as string) || '',
    FIREBASE_CLIENT_EMAIL: (config['FIREBASE_CLIENT_EMAIL'] as string) || '',
    THROTTLE_TTL: parseInt(config['THROTTLE_TTL'] as string, 10) || 60000,
    THROTTLE_LIMIT: parseInt(config['THROTTLE_LIMIT'] as string, 10) || 100,
  };
}
