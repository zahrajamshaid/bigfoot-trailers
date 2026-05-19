import { Test, TestingModule } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { NotificationsGateway, WsEvent } from './notifications.gateway';
import { PrismaService } from '../../prisma/prisma.service';

describe('NotificationsGateway', () => {
  let gateway: NotificationsGateway;

  const mockJwtService = {
    verify: jest.fn(),
  };

  const mockConfigService = {
    get: jest.fn().mockReturnValue('test-secret'),
  };

  const mockPrisma = {};

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        NotificationsGateway,
        { provide: JwtService, useValue: mockJwtService },
        { provide: ConfigService, useValue: mockConfigService },
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    gateway = module.get<NotificationsGateway>(NotificationsGateway);

    // Mock the server
    gateway.server = {
      to: jest.fn().mockReturnThis(),
      emit: jest.fn(),
    } as any;

    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(gateway).toBeDefined();
  });

  // =========================================================================
  // handleConnection — JWT auth on handshake
  // =========================================================================
  describe('handleConnection', () => {
    it('should authenticate client and join rooms', async () => {
      mockJwtService.verify.mockReturnValue({
        sub: 10,
        role: 'production_manager',
        departmentId: 3,
      });

      const mockClient = {
        id: 'client-1',
        handshake: { auth: { token: 'valid-token' }, headers: {} },
        data: {} as any,
        join: jest.fn(),
        disconnect: jest.fn(),
      };

      await gateway.handleConnection(mockClient as any);

      expect(mockJwtService.verify).toHaveBeenCalledWith('valid-token', {
        secret: 'test-secret',
      });
      expect(mockClient.data.userId).toBe(10);
      expect(mockClient.data.role).toBe('production_manager');
      expect(mockClient.join).toHaveBeenCalledWith('user:10');
      expect(mockClient.join).toHaveBeenCalledWith('role:production_manager');
      expect(mockClient.join).toHaveBeenCalledWith('dept:3');
      expect(mockClient.join).toHaveBeenCalledWith('alerts');
    });

    it('should disconnect client with no token', async () => {
      const mockClient = {
        id: 'client-2',
        handshake: { auth: {}, headers: {} },
        data: {} as any,
        join: jest.fn(),
        disconnect: jest.fn(),
      };

      await gateway.handleConnection(mockClient as any);

      expect(mockClient.disconnect).toHaveBeenCalledWith(true);
      expect(mockClient.join).not.toHaveBeenCalled();
    });

    it('should disconnect client with invalid token', async () => {
      mockJwtService.verify.mockImplementation(() => {
        throw new Error('invalid');
      });

      const mockClient = {
        id: 'client-3',
        handshake: { auth: { token: 'bad-token' }, headers: {} },
        data: {} as any,
        join: jest.fn(),
        disconnect: jest.fn(),
      };

      await gateway.handleConnection(mockClient as any);

      expect(mockClient.disconnect).toHaveBeenCalledWith(true);
    });

    it('should extract token from authorization header', async () => {
      mockJwtService.verify.mockReturnValue({
        sub: 5,
        role: 'worker',
        departmentId: 1,
      });

      const mockClient = {
        id: 'client-4',
        handshake: { auth: {}, headers: { authorization: 'Bearer header-token' } },
        data: {} as any,
        join: jest.fn(),
        disconnect: jest.fn(),
      };

      await gateway.handleConnection(mockClient as any);

      expect(mockJwtService.verify).toHaveBeenCalledWith('header-token', {
        secret: 'test-secret',
      });
      expect(mockClient.data.userId).toBe(5);
    });

    it('should NOT join alerts room for worker role', async () => {
      mockJwtService.verify.mockReturnValue({
        sub: 7,
        role: 'worker',
        departmentId: 2,
      });

      const mockClient = {
        id: 'client-5',
        handshake: { auth: { token: 'valid' }, headers: {} },
        data: {} as any,
        join: jest.fn(),
        disconnect: jest.fn(),
      };

      await gateway.handleConnection(mockClient as any);

      const joinCalls = mockClient.join.mock.calls.map((c: any[]) => c[0]);
      expect(joinCalls).not.toContain('alerts');
    });

    it('should skip dept room if no departmentId', async () => {
      mockJwtService.verify.mockReturnValue({
        sub: 8,
        role: 'owner',
        departmentId: null,
      });

      const mockClient = {
        id: 'client-6',
        handshake: { auth: { token: 'valid' }, headers: {} },
        data: {} as any,
        join: jest.fn(),
        disconnect: jest.fn(),
      };

      await gateway.handleConnection(mockClient as any);

      const joinCalls = mockClient.join.mock.calls.map((c: any[]) => c[0]);
      expect(joinCalls).toContain('user:8');
      expect(joinCalls).toContain('role:owner');
      expect(joinCalls).toContain('alerts');
      expect(joinCalls.some((c: string) => c.startsWith('dept:'))).toBe(false);
    });
  });

  // =========================================================================
  // Heartbeat
  // =========================================================================
  describe('heartbeat', () => {
    it('should respond with heartbeat_ack', () => {
      const mockClient = { emit: jest.fn() };
      gateway.handleHeartbeat(mockClient as any);
      expect(mockClient.emit).toHaveBeenCalledWith(
        'heartbeat_ack',
        expect.objectContaining({ timestamp: expect.any(String) }),
      );
    });
  });

  // =========================================================================
  // Subscribe / Unsubscribe
  // =========================================================================
  describe('subscribe', () => {
    it('should join a dept room', async () => {
      const mockClient = { join: jest.fn(), emit: jest.fn() };
      await gateway.handleSubscribe(mockClient as any, { room: 'dept:5' });
      expect(mockClient.join).toHaveBeenCalledWith('dept:5');
      expect(mockClient.emit).toHaveBeenCalledWith('subscribed', { room: 'dept:5' });
    });

    it('should join the alerts room', async () => {
      const mockClient = { join: jest.fn(), emit: jest.fn() };
      await gateway.handleSubscribe(mockClient as any, { room: 'alerts' });
      expect(mockClient.join).toHaveBeenCalledWith('alerts');
    });

    it('should not join arbitrary rooms', async () => {
      const mockClient = { join: jest.fn(), emit: jest.fn() };
      await gateway.handleSubscribe(mockClient as any, { room: 'malicious:room' });
      expect(mockClient.join).not.toHaveBeenCalled();
    });
  });

  describe('unsubscribe', () => {
    it('should leave a room', async () => {
      const mockClient = { leave: jest.fn(), emit: jest.fn() };
      await gateway.handleUnsubscribe(mockClient as any, { room: 'dept:3' });
      expect(mockClient.leave).toHaveBeenCalledWith('dept:3');
      expect(mockClient.emit).toHaveBeenCalledWith('unsubscribed', { room: 'dept:3' });
    });
  });

  // =========================================================================
  // Emit helpers
  // =========================================================================
  describe('emitToDepartment', () => {
    it('should emit to the dept room', () => {
      const mockTo = jest.fn().mockReturnThis();
      const mockEmit = jest.fn();
      gateway.server = { to: mockTo, emit: mockEmit } as any;

      gateway.emitToDepartment(3, WsEvent.STEP_COMPLETED, { foo: 'bar' });

      expect(mockTo).toHaveBeenCalledWith('dept:3');
      expect(mockEmit).toHaveBeenCalledWith(
        WsEvent.STEP_COMPLETED,
        expect.objectContaining({
          event: WsEvent.STEP_COMPLETED,
          channel: 'dept:3',
          data: { foo: 'bar' },
        }),
      );
    });
  });

  describe('emitToAlerts', () => {
    it('should emit to the alerts room', () => {
      const mockTo = jest.fn().mockReturnThis();
      const mockEmit = jest.fn();
      gateway.server = { to: mockTo, emit: mockEmit } as any;

      gateway.emitToAlerts(WsEvent.QC_FAIL, { fail: true });

      expect(mockTo).toHaveBeenCalledWith('alerts');
      expect(mockEmit).toHaveBeenCalledWith(
        WsEvent.QC_FAIL,
        expect.objectContaining({
          event: WsEvent.QC_FAIL,
          channel: 'alerts',
        }),
      );
    });
  });

  describe('emitToUser', () => {
    it('should emit to the user room', () => {
      const mockTo = jest.fn().mockReturnThis();
      const mockEmit = jest.fn();
      gateway.server = { to: mockTo, emit: mockEmit } as any;

      gateway.emitToUser(10, WsEvent.POINTS_UPDATED, { points: 5 });

      expect(mockTo).toHaveBeenCalledWith('user:10');
      expect(mockEmit).toHaveBeenCalledWith(
        WsEvent.POINTS_UPDATED,
        expect.objectContaining({
          event: WsEvent.POINTS_UPDATED,
          channel: 'user:10',
        }),
      );
    });
  });

  describe('emitToRole', () => {
    it('should emit to a role room', () => {
      const mockTo = jest.fn().mockReturnThis();
      const mockEmit = jest.fn();
      gateway.server = { to: mockTo, emit: mockEmit } as any;

      gateway.emitToRole('production_manager', WsEvent.TRAILER_STALLED, {
        stalled: true,
      });

      expect(mockTo).toHaveBeenCalledWith('role:production_manager');
    });
  });
});
