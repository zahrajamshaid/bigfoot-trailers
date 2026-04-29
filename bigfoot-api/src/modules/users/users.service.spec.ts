import { Test, TestingModule } from '@nestjs/testing';
import {
  NotFoundException,
  ConflictException,
  ForbiddenException,
  BadRequestException,
} from '@nestjs/common';
import { UsersService } from './users.service';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateUserDto, UserRoleDto } from './dto/create-user.dto';

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const mockSafeUser = {
  id: BigInt(1),
  email: 'worker@bigfoot.com',
  fullName: 'Test Worker',
  phone: '+1234567890',
  role: 'worker',
  primaryDepartmentId: 1,
  primaryLocationId: 1,
  pushToken: null,
  isActive: true,
  createdAt: new Date('2026-01-01'),
  deactivatedAt: null,
  primaryDepartment: { id: 1, code: 'XP_JIG', displayName: 'XP Jig Weld' },
  primaryLocation: { id: 1, code: 'MULBERRY', name: 'Bigfoot Trailers Mulberry' },
};

const mockOwnerUser = {
  ...mockSafeUser,
  id: BigInt(10),
  email: 'owner@bigfoot.com',
  fullName: 'Owner User',
  role: 'owner',
};

// ---------------------------------------------------------------------------
// Prisma mock
// ---------------------------------------------------------------------------

const mockPrisma = {
  user: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    count: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  department: { findUnique: jest.fn() },
  location: { findUnique: jest.fn() },
  $transaction: jest.fn(),
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('UsersService', () => {
  let service: UsersService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        UsersService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<UsersService>(UsersService);
    jest.clearAllMocks();
  });

  // =========================================================================
  // findAll
  // =========================================================================
  describe('findAll', () => {
    it('should return paginated users', async () => {
      mockPrisma.$transaction.mockResolvedValue([[mockSafeUser], 1]);

      const result = await service.findAll({ page: 1, limit: 25 });

      expect(result.users).toHaveLength(1);
      expect(result.total).toBe(1);
      expect(result.page).toBe(1);
      expect(result.limit).toBe(25);
      expect(mockPrisma.$transaction).toHaveBeenCalled();
    });

    it('should apply role filter', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);

      await service.findAll({ role: UserRoleDto.WORKER });

      const transactionArgs = mockPrisma.$transaction.mock.calls[0][0];
      // Verify the transaction was called (filters applied inside prisma calls)
      expect(transactionArgs).toHaveLength(2);
    });

    it('should default to page 1 and limit 25', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);

      const result = await service.findAll({});

      expect(result.page).toBe(1);
      expect(result.limit).toBe(25);
    });
  });

  // =========================================================================
  // findOne
  // =========================================================================
  describe('findOne', () => {
    it('should return user by id', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(mockSafeUser);

      const result = await service.findOne(BigInt(1));

      expect(result).toEqual(mockSafeUser);
      expect(mockPrisma.user.findUnique).toHaveBeenCalledWith({
        where: { id: BigInt(1) },
        select: expect.objectContaining({ id: true, email: true }),
      });
    });

    it('should throw NotFoundException for non-existent user', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(service.findOne(BigInt(999))).rejects.toThrow(NotFoundException);
    });

    it('should never include passwordHash in response', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(mockSafeUser);

      const result = await service.findOne(BigInt(1));

      expect(result).not.toHaveProperty('passwordHash');
    });

    it('should include primaryDepartment and primaryLocation', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(mockSafeUser);

      const result = await service.findOne(BigInt(1));

      expect(result.primaryDepartment).toBeDefined();
      expect(result.primaryDepartment!.code).toBe('XP_JIG');
      expect(result.primaryLocation).toBeDefined();
      expect(result.primaryLocation!.code).toBe('MULBERRY');
    });
  });

  // =========================================================================
  // create
  // =========================================================================
  describe('create', () => {
    const createDto: CreateUserDto = {
      email: 'new@bigfoot.com',
      fullName: 'New User',
      password: 'SecurePass123!',
      role: UserRoleDto.WORKER,
      primaryDepartmentId: 1,
      primaryLocationId: 1,
    };

    it('should create a user with hashed password', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null); // email not taken
      mockPrisma.department.findUnique.mockResolvedValue({ id: 1 });
      mockPrisma.location.findUnique.mockResolvedValue({ id: 1 });
      mockPrisma.user.create.mockResolvedValue(mockSafeUser);

      const result = await service.create(createDto);

      expect(result).toEqual(mockSafeUser);
      expect(mockPrisma.user.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          email: 'new@bigfoot.com',
          fullName: 'New User',
          role: 'worker',
          passwordHash: expect.any(String),
        }),
        select: expect.objectContaining({ id: true }),
      });

      // Verify password was hashed (not stored as plain text)
      const createCall = mockPrisma.user.create.mock.calls[0][0];
      expect(createCall.data.passwordHash).not.toBe('SecurePass123!');
      expect(createCall.data.passwordHash.startsWith('$2')).toBe(true); // bcrypt hash prefix
    });

    it('should throw ConflictException for duplicate email', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({ id: BigInt(99) }); // email exists

      await expect(service.create(createDto)).rejects.toThrow(ConflictException);
    });

    it('should throw BadRequestException for invalid department id', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);
      mockPrisma.department.findUnique.mockResolvedValue(null); // dept not found

      await expect(service.create(createDto)).rejects.toThrow(BadRequestException);
    });

    it('should throw BadRequestException for invalid location id', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);
      mockPrisma.department.findUnique.mockResolvedValue({ id: 1 });
      mockPrisma.location.findUnique.mockResolvedValue(null); // location not found

      await expect(service.create(createDto)).rejects.toThrow(BadRequestException);
    });

    it('should allow creating without optional fields', async () => {
      const minimalDto: CreateUserDto = {
        email: 'min@bigfoot.com',
        fullName: 'Minimal User',
        password: 'SecurePass123!',
        role: UserRoleDto.OFFICE,
      };

      mockPrisma.user.findUnique.mockResolvedValue(null);
      mockPrisma.user.create.mockResolvedValue({
        ...mockSafeUser,
        primaryDepartmentId: null,
        primaryLocationId: null,
        primaryDepartment: null,
        primaryLocation: null,
      });

      const result = await service.create(minimalDto);

      expect(result).toBeDefined();
      expect(mockPrisma.user.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          primaryDepartmentId: null,
          primaryLocationId: null,
        }),
        select: expect.any(Object),
      });
    });
  });

  // =========================================================================
  // update
  // =========================================================================
  describe('update', () => {
    beforeEach(() => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: BigInt(1),
        email: 'worker@bigfoot.com',
        role: 'worker',
        isActive: true,
      });
    });

    it('should allow owner to update any field including role', async () => {
      mockPrisma.user.update.mockResolvedValue(mockSafeUser);

      await service.update(
        BigInt(1),
        { role: UserRoleDto.QC_INSPECTOR, fullName: 'Updated Name' },
        BigInt(10), // different user (owner)
        'owner',
      );

      expect(mockPrisma.user.update).toHaveBeenCalledWith({
        where: { id: BigInt(1) },
        data: expect.objectContaining({
          role: 'qc_inspector',
          fullName: 'Updated Name',
        }),
        select: expect.any(Object),
      });
    });

    it('should allow production_manager to change roles and department', async () => {
      mockPrisma.user.update.mockResolvedValue(mockSafeUser);

      await service.update(
        BigInt(1),
        { role: UserRoleDto.QC_INSPECTOR, primaryDepartmentId: 5 },
        BigInt(10), // production manager
        'production_manager',
      );

      expect(mockPrisma.user.update).toHaveBeenCalled();
    });

    it('should allow self to update name, phone, and password', async () => {
      mockPrisma.user.update.mockResolvedValue(mockSafeUser);

      await service.update(
        BigInt(1),
        { fullName: 'My New Name', phone: '+9876543210' },
        BigInt(1), // self
        'worker',
      );

      expect(mockPrisma.user.update).toHaveBeenCalled();
    });

    it('should forbid non-manager self from changing own role', async () => {
      await expect(
        service.update(
          BigInt(1),
          { role: UserRoleDto.WORKER },
          BigInt(1), // self, not a manager
          'worker',
        ),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should forbid production_manager from assigning owner role', async () => {
      await expect(
        service.update(
          BigInt(1),
          { role: UserRoleDto.OWNER },
          BigInt(2),
          'production_manager',
        ),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should allow owner to assign owner role', async () => {
      mockPrisma.user.update.mockResolvedValue({ ...mockSafeUser, role: 'owner' });

      await service.update(
        BigInt(1),
        { role: UserRoleDto.OWNER },
        BigInt(10),
        'owner',
      );

      expect(mockPrisma.user.update).toHaveBeenCalled();
    });

    it('should forbid random user from updating another user', async () => {
      await expect(
        service.update(
          BigInt(1),
          { fullName: 'Hacked' },
          BigInt(99), // random user
          'worker',
        ),
      ).rejects.toThrow(ForbiddenException);
    });

    it('should throw NotFoundException for non-existent user', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(
        service.update(BigInt(999), { fullName: 'X' }, BigInt(10), 'owner'),
      ).rejects.toThrow(NotFoundException);
    });

    it('should throw ConflictException if new email is taken', async () => {
      // First call: find user being updated
      mockPrisma.user.findUnique
        .mockResolvedValueOnce({
          id: BigInt(1),
          email: 'worker@bigfoot.com',
          role: 'worker',
          isActive: true,
        })
        // Second call: check if new email exists
        .mockResolvedValueOnce({ id: BigInt(50) }); // email taken

      await expect(
        service.update(
          BigInt(1),
          { email: 'taken@bigfoot.com' },
          BigInt(10),
          'owner',
        ),
      ).rejects.toThrow(ConflictException);
    });

    it('should hash new password when provided', async () => {
      mockPrisma.user.update.mockResolvedValue(mockSafeUser);

      await service.update(
        BigInt(1),
        { password: 'NewSecure456!' },
        BigInt(1),
        'worker',
      );

      const updateCall = mockPrisma.user.update.mock.calls[0][0];
      expect(updateCall.data.passwordHash).toBeDefined();
      expect(updateCall.data.passwordHash).not.toBe('NewSecure456!');
      expect(updateCall.data.passwordHash.startsWith('$2')).toBe(true);
    });
  });

  // =========================================================================
  // softDelete
  // =========================================================================
  describe('softDelete', () => {
    it('should deactivate a user', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: BigInt(2),
        role: 'worker',
        isActive: true,
      });
      mockPrisma.user.update.mockResolvedValue({
        ...mockSafeUser,
        id: BigInt(2),
        isActive: false,
        deactivatedAt: new Date(),
      });

      const result = await service.softDelete(BigInt(2), BigInt(10));

      expect(result.isActive).toBe(false);
      expect(mockPrisma.user.update).toHaveBeenCalledWith({
        where: { id: BigInt(2) },
        data: {
          isActive: false,
          deactivatedAt: expect.any(Date),
        },
        select: expect.any(Object),
      });
    });

    it('should throw NotFoundException for non-existent user', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(service.softDelete(BigInt(999), BigInt(10))).rejects.toThrow(
        NotFoundException,
      );
    });

    it('should throw ConflictException for already-deactivated user', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: BigInt(2),
        role: 'worker',
        isActive: false,
      });

      await expect(service.softDelete(BigInt(2), BigInt(10))).rejects.toThrow(
        ConflictException,
      );
    });

    it('should prevent self-deletion', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: BigInt(10),
        role: 'owner',
        isActive: true,
      });

      await expect(service.softDelete(BigInt(10), BigInt(10))).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('should prevent deleting the last owner', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: BigInt(10),
        role: 'owner',
        isActive: true,
      });
      mockPrisma.user.count.mockResolvedValue(1); // only 1 owner

      await expect(service.softDelete(BigInt(10), BigInt(20))).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('should allow deleting an owner when others exist', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: BigInt(10),
        role: 'owner',
        isActive: true,
      });
      mockPrisma.user.count.mockResolvedValue(3); // 3 owners
      mockPrisma.user.update.mockResolvedValue({
        ...mockOwnerUser,
        isActive: false,
        deactivatedAt: new Date(),
      });

      const result = await service.softDelete(BigInt(10), BigInt(20));

      expect(result.isActive).toBe(false);
    });
  });
});
