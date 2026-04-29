import { AuditLogInterceptor } from './audit-log.interceptor';
import { AuditLogService } from './audit-log.service';
import { ExecutionContext, CallHandler } from '@nestjs/common';
import { of } from 'rxjs';

describe('AuditLogInterceptor', () => {
  let interceptor: AuditLogInterceptor;
  let mockAuditLogService: { create: jest.Mock };

  beforeEach(() => {
    mockAuditLogService = { create: jest.fn().mockResolvedValue(undefined) };
    interceptor = new AuditLogInterceptor(mockAuditLogService as any);
  });

  function createMockContext(
    method: string,
    path: string,
    user?: { sub: number },
  ): ExecutionContext {
    return {
      switchToHttp: () => ({
        getRequest: () => ({
          method,
          path,
          url: path,
          user: user ?? undefined,
          ip: '127.0.0.1',
          headers: {},
        }),
      }),
    } as unknown as ExecutionContext;
  }

  function createMockHandler(response: any): CallHandler {
    return { handle: () => of(response) };
  }

  it('should skip GET requests', (done) => {
    const ctx = createMockContext('GET', '/trailers/100');
    const handler = createMockHandler({ id: 100 });

    interceptor.intercept(ctx, handler).subscribe({
      next: (val) => {
        expect(val).toEqual({ id: 100 });
      },
      complete: () => {
        // Give time for any async side effects
        setTimeout(() => {
          expect(mockAuditLogService.create).not.toHaveBeenCalled();
          done();
        }, 10);
      },
    });
  });

  it('should log POST requests as CREATE', (done) => {
    const ctx = createMockContext('POST', '/trailers', { sub: 5 });
    const handler = createMockHandler({ id: 200, soNumber: 'SO-100' });

    interceptor.intercept(ctx, handler).subscribe({
      complete: () => {
        setTimeout(() => {
          expect(mockAuditLogService.create).toHaveBeenCalledWith(
            expect.objectContaining({
              userId: 5,
              entityType: 'trailer',
              action: 'CREATE',
              entityId: 200n,
            }),
          );
          done();
        }, 10);
      },
    });
  });

  it('should log PATCH requests as UPDATE with entity ID from path', (done) => {
    const ctx = createMockContext('PATCH', '/departments/3', { sub: 1 });
    const handler = createMockHandler({ id: 3, stallThresholdHours: 72 });

    interceptor.intercept(ctx, handler).subscribe({
      complete: () => {
        setTimeout(() => {
          expect(mockAuditLogService.create).toHaveBeenCalledWith(
            expect.objectContaining({
              entityType: 'department',
              entityId: 3n,
              action: 'UPDATE',
            }),
          );
          done();
        }, 10);
      },
    });
  });

  it('should log DELETE requests', (done) => {
    const ctx = createMockContext('DELETE', '/trailers/50', { sub: 1 });
    const handler = createMockHandler({ id: 50 });

    interceptor.intercept(ctx, handler).subscribe({
      complete: () => {
        setTimeout(() => {
          expect(mockAuditLogService.create).toHaveBeenCalledWith(
            expect.objectContaining({
              entityType: 'trailer',
              entityId: 50n,
              action: 'DELETE',
            }),
          );
          done();
        }, 10);
      },
    });
  });

  it('should handle nested resource paths', (done) => {
    const ctx = createMockContext('PATCH', '/deliveries/10/mark-complete', { sub: 1 });
    const handler = createMockHandler({ id: 10 });

    interceptor.intercept(ctx, handler).subscribe({
      complete: () => {
        setTimeout(() => {
          expect(mockAuditLogService.create).toHaveBeenCalledWith(
            expect.objectContaining({
              entityType: 'delivery',
              entityId: 10n,
            }),
          );
          done();
        }, 10);
      },
    });
  });

  it('should not fail if audit log service throws', (done) => {
    mockAuditLogService.create.mockRejectedValue(new Error('DB down'));
    const ctx = createMockContext('POST', '/trailers', { sub: 1 });
    const handler = createMockHandler({ id: 1 });

    interceptor.intercept(ctx, handler).subscribe({
      next: (val) => {
        expect(val).toEqual({ id: 1 });
      },
      complete: () => {
        done(); // Should complete without error
      },
    });
  });

  it('should use x-forwarded-for header for IP', (done) => {
    const ctx = {
      switchToHttp: () => ({
        getRequest: () => ({
          method: 'POST',
          path: '/trailers',
          url: '/trailers',
          user: { sub: 1 },
          ip: '127.0.0.1',
          headers: { 'x-forwarded-for': '203.0.113.50, 70.41.3.18' },
        }),
      }),
    } as unknown as ExecutionContext;
    const handler = createMockHandler({ id: 5 });

    interceptor.intercept(ctx, handler).subscribe({
      complete: () => {
        setTimeout(() => {
          expect(mockAuditLogService.create).toHaveBeenCalledWith(
            expect.objectContaining({
              ipAddress: '203.0.113.50',
            }),
          );
          done();
        }, 10);
      },
    });
  });
});
