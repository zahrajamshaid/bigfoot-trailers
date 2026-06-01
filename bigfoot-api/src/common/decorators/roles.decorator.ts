import { SetMetadata } from '@nestjs/common';

/**
 * Matches the user_role_enum from bigfoot_schema_final.sql.
 */
export enum UserRole {
  OWNER = 'owner',
  PRODUCTION_MANAGER = 'production_manager',
  TRANSPORT_MANAGER = 'transport_manager',
  QC_INSPECTOR = 'qc_inspector',
  WORKER = 'worker',
  SALES = 'sales',
  DRIVER = 'driver',
  OFFICE = 'office',
  PURCHASING = 'purchasing',
  PARTS = 'parts',
}

export const ROLES_KEY = 'roles';

/**
 * Restrict endpoint access to specific roles.
 * Usage: @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
 */
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES_KEY, roles);
