import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { QueryUsersDto } from './dto/query-users.dto';
import { Prisma, UserRole } from '@prisma/client';

const BCRYPT_ROUNDS = 12;

/** Fields returned for every user query — password_hash is NEVER included. */
const USER_SELECT = {
  id: true,
  email: true,
  fullName: true,
  phone: true,
  role: true,
  primaryDepartmentId: true,
  extraDepartmentIds: true,
  primaryLocationId: true,
  pushToken: true,
  isActive: true,
  createdAt: true,
  deactivatedAt: true,
  primaryDepartment: {
    select: { id: true, code: true, displayName: true },
  },
  primaryLocation: {
    select: { id: true, code: true, name: true },
  },
} satisfies Prisma.UserSelect;

export type SafeUser = Prisma.UserGetPayload<{ select: typeof USER_SELECT }>;

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  // ---------------------------------------------------------------------------
  // GET /users — list with pagination + filters (owner, production_manager)
  // ---------------------------------------------------------------------------
  async findAll(
    query: QueryUsersDto,
  ): Promise<{ users: SafeUser[]; total: number; page: number; limit: number }> {
    const page = query.page ?? 1;
    const limit = query.limit ?? 25;
    const skip = (page - 1) * limit;

    const where: Prisma.UserWhereInput = {};
    if (query.role) where.role = query.role as UserRole;
    if (query.isActive !== undefined) where.isActive = query.isActive;
    if (query.departmentId) where.primaryDepartmentId = query.departmentId;

    const [users, total] = await this.prisma.$transaction([
      this.prisma.user.findMany({
        where,
        select: USER_SELECT,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.user.count({ where }),
    ]);

    return { users, total, page, limit };
  }

  // ---------------------------------------------------------------------------
  // GET /users/drivers — active drivers, for delivery assignment
  // ---------------------------------------------------------------------------
  async findDrivers(): Promise<SafeUser[]> {
    return this.prisma.user.findMany({
      where: { role: UserRole.driver, isActive: true },
      select: USER_SELECT,
      orderBy: { fullName: 'asc' },
    });
  }

  // ---------------------------------------------------------------------------
  // GET /users/:id
  // ---------------------------------------------------------------------------
  async findOne(id: bigint): Promise<SafeUser> {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: USER_SELECT,
    });

    if (!user) {
      throw new AppError(ErrorCode.NOT_FOUND, `User with id ${id} not found`);
    }

    return user;
  }

  // ---------------------------------------------------------------------------
  // POST /users — create (owner only)
  // ---------------------------------------------------------------------------
  async create(dto: CreateUserDto): Promise<SafeUser> {
    // Check email uniqueness
    const existing = await this.prisma.user.findUnique({
      where: { email: dto.email },
      select: { id: true },
    });

    if (existing) {
      throw new AppError(
        ErrorCode.SO_NUMBER_EXISTS,
        `A user with email "${dto.email}" already exists`,
      );
    }

    // Validate FK references if provided
    if (dto.primaryDepartmentId) {
      const dept = await this.prisma.department.findUnique({
        where: { id: dto.primaryDepartmentId },
        select: { id: true },
      });
      if (!dept) {
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          `Department with id ${dto.primaryDepartmentId} not found`,
        );
      }
    }

    if (dto.primaryLocationId) {
      const loc = await this.prisma.location.findUnique({
        where: { id: dto.primaryLocationId },
        select: { id: true },
      });
      if (!loc) {
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          `Location with id ${dto.primaryLocationId} not found`,
        );
      }
    }

    // Hash password
    const passwordHash = await bcrypt.hash(dto.password, BCRYPT_ROUNDS);

    const user = await this.prisma.user.create({
      data: {
        email: dto.email,
        fullName: dto.fullName,
        phone: dto.phone ?? null,
        passwordHash,
        role: dto.role as UserRole,
        primaryDepartmentId: dto.primaryDepartmentId ?? null,
        primaryLocationId: dto.primaryLocationId ?? null,
      },
      select: USER_SELECT,
    });

    return user;
  }

  // ---------------------------------------------------------------------------
  // PATCH /users/:id — update
  // Owner + production_manager: can change ANY field on ANY user (role,
  //   department, location, etc.) since workers can have multiple roles
  //   and need to be reassigned across departments.
  // Other roles: can only update their own profile (name, phone, password).
  // ---------------------------------------------------------------------------
  async update(
    id: bigint,
    dto: UpdateUserDto,
    requesterId: bigint,
    requesterRole: string,
  ): Promise<SafeUser> {
    const existing = await this.prisma.user.findUnique({
      where: { id },
      select: { id: true, email: true, role: true, isActive: true },
    });

    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `User with id ${id} not found`);
    }

    const isSelf = requesterId === id;
    const isOwner = requesterRole === 'owner';
    const isProductionManager = requesterRole === 'production_manager';
    const isManager = isOwner || isProductionManager;

    // Non-manager can only update themselves
    if (!isManager && !isSelf) {
      throw new AppError(ErrorCode.FORBIDDEN, 'You can only update your own profile');
    }

    // Self-update for non-managers: only allow limited fields (name, phone, password)
    if (isSelf && !isManager) {
      if (
        dto.role ||
        dto.primaryDepartmentId !== undefined ||
        dto.primaryLocationId !== undefined
      ) {
        throw new AppError(
          ErrorCode.FORBIDDEN,
          'Only an owner or production manager can change role, department, or location assignments',
        );
      }
    }

    // Only owner can promote someone to owner role
    if (dto.role === 'owner' && !isOwner) {
      throw new AppError(ErrorCode.FORBIDDEN, 'Only an owner can assign the owner role');
    }

    // If changing email, check uniqueness
    if (dto.email && dto.email !== existing.email) {
      const emailTaken = await this.prisma.user.findUnique({
        where: { email: dto.email },
        select: { id: true },
      });
      if (emailTaken) {
        throw new AppError(
          ErrorCode.SO_NUMBER_EXISTS,
          `A user with email "${dto.email}" already exists`,
        );
      }
    }

    // Build update data — only set fields that are provided
    const data: Prisma.UserUpdateInput = {};
    if (dto.email !== undefined) data.email = dto.email;
    if (dto.fullName !== undefined) data.fullName = dto.fullName;
    if (dto.phone !== undefined) data.phone = dto.phone;
    if (dto.role !== undefined) data.role = dto.role as UserRole;
    if (dto.primaryDepartmentId !== undefined) {
      data.primaryDepartment =
        dto.primaryDepartmentId === null
          ? { disconnect: true }
          : { connect: { id: dto.primaryDepartmentId } };
    }
    if (dto.primaryLocationId !== undefined) {
      data.primaryLocation =
        dto.primaryLocationId === null
          ? { disconnect: true }
          : { connect: { id: dto.primaryLocationId } };
    }

    // Hash new password if provided
    if (dto.password) {
      data.passwordHash = await bcrypt.hash(dto.password, BCRYPT_ROUNDS);
    }

    const updated = await this.prisma.user.update({
      where: { id },
      data,
      select: USER_SELECT,
    });

    return updated;
  }

  // ---------------------------------------------------------------------------
  // DELETE /users/:id — soft-delete (owner only)
  // ---------------------------------------------------------------------------
  async softDelete(id: bigint, requesterId: bigint): Promise<SafeUser> {
    const existing = await this.prisma.user.findUnique({
      where: { id },
      select: { id: true, role: true, isActive: true },
    });

    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `User with id ${id} not found`);
    }

    if (!existing.isActive) {
      throw new AppError(ErrorCode.BAD_REQUEST, 'User is already deactivated');
    }

    // Prevent self-deletion
    if (requesterId === id) {
      throw new AppError(ErrorCode.FORBIDDEN, 'You cannot deactivate your own account');
    }

    // Prevent deleting the last owner
    if (existing.role === 'owner') {
      const ownerCount = await this.prisma.user.count({
        where: { role: 'owner', isActive: true },
      });
      if (ownerCount <= 1) {
        throw new AppError(
          ErrorCode.FORBIDDEN,
          'Cannot deactivate the last active owner account',
        );
      }
    }

    const deactivated = await this.prisma.user.update({
      where: { id },
      data: {
        isActive: false,
        deactivatedAt: new Date(),
      },
      select: USER_SELECT,
    });

    return deactivated;
  }

  // ---------------------------------------------------------------------------
  // POST /users/:id/reactivate — undo a soft-delete (owner only)
  // ---------------------------------------------------------------------------
  async reactivate(id: bigint): Promise<SafeUser> {
    const existing = await this.prisma.user.findUnique({
      where: { id },
      select: { id: true, isActive: true },
    });

    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `User with id ${id} not found`);
    }

    if (existing.isActive) {
      throw new AppError(ErrorCode.BAD_REQUEST, 'User is already active');
    }

    return this.prisma.user.update({
      where: { id },
      data: {
        isActive: true,
        deactivatedAt: null,
      },
      select: USER_SELECT,
    });
  }

  // ---------------------------------------------------------------------------
  // DELETE /users/:id/permanent — hard-delete (owner only)
  //
  // Refuses if the user has historical activity (completed steps, QC
  // inspections, deliveries, ...) since most of those FKs are non-cascading
  // and the records must remain for audit purposes. Audit-log rows cascade
  // automatically — those WILL be removed with the user.
  // ---------------------------------------------------------------------------
  async hardDelete(id: bigint, requesterId: bigint): Promise<{ deleted: true }> {
    const existing = await this.prisma.user.findUnique({
      where: { id },
      select: { id: true, role: true, isActive: true },
    });

    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `User with id ${id} not found`);
    }

    if (existing.isActive) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'Deactivate the user first — only inactive users can be permanently deleted.',
      );
    }

    if (requesterId === id) {
      throw new AppError(
        ErrorCode.FORBIDDEN,
        'You cannot permanently delete your own account',
      );
    }

    if (existing.role === 'owner') {
      const ownerCount = await this.prisma.user.count({
        where: { role: 'owner', isActive: true },
      });
      if (ownerCount <= 0) {
        throw new AppError(
          ErrorCode.FORBIDDEN,
          'Cannot delete the last owner account — promote another user to owner first.',
        );
      }
    }

    try {
      await this.prisma.user.delete({ where: { id } });
      return { deleted: true };
    } catch (e) {
      // P2003 = FK constraint violation. The user still has records in
      // tables whose FKs don't cascade (trailers they created, QC
      // inspections they ran, deliveries, messages, etc.). Translate to
      // an actionable error so the admin knows why.
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2003') {
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          'This user has historical activity (completed steps, inspections, deliveries, or messages) and cannot be permanently deleted. Keep them deactivated to preserve the audit trail.',
        );
      }
      throw e;
    }
  }
}
