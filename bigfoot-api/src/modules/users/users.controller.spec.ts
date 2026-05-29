import { Test, TestingModule } from '@nestjs/testing';
import { UsersController } from './users.controller';
import { UsersService, SafeUser } from './users.service';
import { UserRoleDto } from './dto/create-user.dto';
import { JwtPayload } from '../../common/decorators/current-user.decorator';

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const mockUser: SafeUser = {
  id: BigInt(1),
  email: 'worker@bigfoot.com',
  fullName: 'Test Worker',
  phone: '+1234567890',
  role: 'worker',
  primaryDepartmentId: 1,
  extraDepartmentIds: [],
  primaryLocationId: 1,
  pushToken: null,
  isActive: true,
  createdAt: new Date('2026-01-01'),
  deactivatedAt: null,
  primaryDepartment: { id: 1, code: 'XP_JIG', displayName: 'XP Jig Weld' },
  primaryLocation: { id: 1, code: 'MULBERRY', name: 'Bigfoot Trailers Mulberry' },
};

const ownerPayload: JwtPayload = {
  sub: 10,
  email: 'owner@bigfoot.com',
  role: 'owner',
  departmentId: null,
  extraDepartmentIds: [],
  iat: 0,
  exp: 0,
};

const workerPayload: JwtPayload = {
  sub: 1,
  email: 'worker@bigfoot.com',
  role: 'worker',
  departmentId: 1,
  extraDepartmentIds: [],
  iat: 0,
  exp: 0,
};

// ---------------------------------------------------------------------------
// Service mock
// ---------------------------------------------------------------------------

const mockUsersService = {
  findAll: jest
    .fn()
    .mockResolvedValue({ users: [mockUser], total: 1, page: 1, limit: 25 }),
  findOne: jest.fn().mockResolvedValue(mockUser),
  create: jest.fn().mockResolvedValue(mockUser),
  update: jest.fn().mockResolvedValue(mockUser),
  softDelete: jest.fn().mockResolvedValue({ ...mockUser, isActive: false }),
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('UsersController', () => {
  let controller: UsersController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [UsersController],
      providers: [{ provide: UsersService, useValue: mockUsersService }],
    }).compile();

    controller = module.get<UsersController>(UsersController);
    jest.clearAllMocks();
  });

  describe('GET /users', () => {
    it('should return paginated user list', async () => {
      const result = await controller.findAll({ page: 1, limit: 25 });

      expect(mockUsersService.findAll).toHaveBeenCalledWith({ page: 1, limit: 25 });
      expect(result.users).toHaveLength(1);
      expect(result.total).toBe(1);
    });

    it('should forward filter parameters to service', async () => {
      await controller.findAll({ role: UserRoleDto.WORKER, isActive: true });

      expect(mockUsersService.findAll).toHaveBeenCalledWith(
        expect.objectContaining({ role: 'worker', isActive: true }),
      );
    });
  });

  describe('POST /users', () => {
    it('should create a user and return without passwordHash', async () => {
      const dto = {
        email: 'new@bigfoot.com',
        fullName: 'New User',
        password: 'SecurePass123!',
        role: UserRoleDto.WORKER,
      };

      const result = await controller.create(dto);

      expect(mockUsersService.create).toHaveBeenCalledWith(dto);
      expect(result).toEqual(mockUser);
      expect(result).not.toHaveProperty('passwordHash');
    });
  });

  describe('GET /users/:id', () => {
    it('should return a single user with department populated', async () => {
      const result = await controller.findOne(1);

      expect(mockUsersService.findOne).toHaveBeenCalledWith(BigInt(1));
      expect(result.primaryDepartment).toBeDefined();
      expect(result.primaryDepartment!.code).toBe('XP_JIG');
    });
  });

  describe('PATCH /users/:id', () => {
    it('should pass requester context to service', async () => {
      await controller.update(1, { fullName: 'Updated' }, ownerPayload);

      expect(mockUsersService.update).toHaveBeenCalledWith(
        BigInt(1),
        { fullName: 'Updated' },
        BigInt(10), // owner sub
        'owner',
      );
    });

    it('should allow self-update with worker token', async () => {
      await controller.update(1, { phone: '+9999999999' }, workerPayload);

      expect(mockUsersService.update).toHaveBeenCalledWith(
        BigInt(1),
        { phone: '+9999999999' },
        BigInt(1), // self
        'worker',
      );
    });
  });

  describe('DELETE /users/:id', () => {
    it('should pass requester id to softDelete', async () => {
      const result = await controller.softDelete(2, ownerPayload);

      expect(mockUsersService.softDelete).toHaveBeenCalledWith(BigInt(2), BigInt(10));
      expect(result.isActive).toBe(false);
    });
  });
});
