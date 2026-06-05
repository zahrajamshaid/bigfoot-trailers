import { AuditLogInterceptor } from './audit-log.interceptor';
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

  // ===========================================================================
  // Multi-segment resource paths — locked because every dropdown filter on
  // the mobile audit-log screen queries by these exact strings.
  // ===========================================================================
  describe('multi-segment resource paths', () => {
    it('POST /qc/inspections logs as qc_inspection with id from response', (done) => {
      const ctx = createMockContext('POST', '/qc/inspections', { sub: 9 });
      const handler = createMockHandler({ id: 333, result: 'pass' });

      interceptor.intercept(ctx, handler).subscribe({
        complete: () => {
          setTimeout(() => {
            expect(mockAuditLogService.create).toHaveBeenCalledWith(
              expect.objectContaining({
                entityType: 'qc_inspection',
                entityId: 333n,
                action: 'CREATE',
              }),
            );
            done();
          }, 10);
        },
      });
    });

    it('POST /qc/inspections/45/send-customer-sms logs as qc_inspection action', (done) => {
      const ctx = createMockContext(
        'POST',
        '/qc/inspections/45/send-customer-sms',
        { sub: 1 },
      );
      const handler = createMockHandler({ smsLogId: 1 });

      interceptor.intercept(ctx, handler).subscribe({
        complete: () => {
          setTimeout(() => {
            expect(mockAuditLogService.create).toHaveBeenCalledWith(
              expect.objectContaining({
                entityType: 'qc_inspection',
                entityId: 45n,
              }),
            );
            done();
          }, 10);
        },
      });
    });

    it('PATCH /qc/checklist-items/7 logs as qc_checklist_item', (done) => {
      const ctx = createMockContext('PATCH', '/qc/checklist-items/7', { sub: 1 });
      const handler = createMockHandler({ id: 7 });

      interceptor.intercept(ctx, handler).subscribe({
        complete: () => {
          setTimeout(() => {
            expect(mockAuditLogService.create).toHaveBeenCalledWith(
              expect.objectContaining({
                entityType: 'qc_checklist_item',
                entityId: 7n,
              }),
            );
            done();
          }, 10);
        },
      });
    });

    it('PATCH /deliveries/batches/10/depart logs as delivery_batch', (done) => {
      const ctx = createMockContext('PATCH', '/deliveries/batches/10/depart', { sub: 1 });
      const handler = createMockHandler({ id: 10, status: 'in_transit' });

      interceptor.intercept(ctx, handler).subscribe({
        complete: () => {
          setTimeout(() => {
            expect(mockAuditLogService.create).toHaveBeenCalledWith(
              expect.objectContaining({
                entityType: 'delivery_batch',
                entityId: 10n,
              }),
            );
            done();
          }, 10);
        },
      });
    });

    it('POST /deliveries/batches logs as delivery_batch CREATE', (done) => {
      const ctx = createMockContext('POST', '/deliveries/batches', { sub: 1 });
      const handler = createMockHandler({ id: 88, batchNumber: 'B-1' });

      interceptor.intercept(ctx, handler).subscribe({
        complete: () => {
          setTimeout(() => {
            expect(mockAuditLogService.create).toHaveBeenCalledWith(
              expect.objectContaining({
                entityType: 'delivery_batch',
                entityId: 88n,
                action: 'CREATE',
              }),
            );
            done();
          }, 10);
        },
      });
    });

    it('POST /users/5/reactivate logs as user (action verb stays out of type)', (done) => {
      const ctx = createMockContext('POST', '/users/5/reactivate', { sub: 1 });
      const handler = createMockHandler({ id: 5 });

      interceptor.intercept(ctx, handler).subscribe({
        complete: () => {
          setTimeout(() => {
            expect(mockAuditLogService.create).toHaveBeenCalledWith(
              expect.objectContaining({
                entityType: 'user',
                entityId: 5n,
              }),
            );
            done();
          }, 10);
        },
      });
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
