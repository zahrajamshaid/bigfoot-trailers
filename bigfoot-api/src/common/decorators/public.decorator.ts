import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';

/**
 * Mark an endpoint as public — bypasses JWT authentication.
 * Usage: @Public() on login, refresh, health check endpoints.
 */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
