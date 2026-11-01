import { SetMetadata } from '@nestjs/common';
import type { UserRole } from '../users/domain/user';

export const ROLES_KEY = 'roles';

/**
 * Declares which roles may reach a handler. The decorator only records the
 * requirement — RolesGuard makes the decision. Several roles mean "any of".
 */
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES_KEY, roles);
