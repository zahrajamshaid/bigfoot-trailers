import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { SupportService } from '../support/support.service';
import { YardAuditService } from './yard-audit.service';

const mockPrisma = {
  location: { findUnique: jest.fn() },
  trailer: { findMany: jest.fn() },
  user: { findUnique: jest.fn() },
  auditLog: { create: jest.fn() },
};

const mockSupport = {
  createTicket: jest.fn(),
};

describe('YardAuditService', () => {
  let service: YardAuditService;
  let ticketSeq = 0;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        YardAuditService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: SupportService, useValue: mockSupport },
      ],
    }).compile();

    service = module.get<YardAuditService>(YardAuditService);
    jest.clearAllMocks();
    ticketSeq = 0;
    mockSupport.createTicket.mockImplementation(async () => ({
      id: String(++ticketSeq),
    }));
    mockPrisma.user.findUnique.mockResolvedValue({ fullName: 'Jane Sales' });
    mockPrisma.auditLog.create.mockResolvedValue({});
  });

  it('throws NOT_FOUND for an unknown location', async () => {
    mockPrisma.location.findUnique.mockResolvedValue(null);

    await expect(
      service.submitAudit(BigInt(9), { locationId: 999 }),
    ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
  });

  it('opens one ticket per missing trailer and per extra, and logs the audit', async () => {
    mockPrisma.location.findUnique.mockResolvedValue({ id: 3, name: 'Mulberry' });
    mockPrisma.trailer.findMany.mockResolvedValue([
      { id: BigInt(101), soNumber: '7031', trailerModel: { displayName: '10K Dump' } },
      { id: BigInt(102), soNumber: '7044', trailerModel: { displayName: 'XP 20' } },
    ]);

    const res = await service.submitAudit(BigInt(9), {
      locationId: 3,
      missingTrailerIds: [101, 102],
      extras: [{ soNumber: '6998', note: 'gray gooseneck by the fence' }],
    });

    expect(mockSupport.createTicket).toHaveBeenCalledTimes(3);
    // Missing ticket mentions the SO + yard.
    const firstBody = mockSupport.createTicket.mock.calls[0][1];
    expect(firstBody.subject).toContain('7031');
    expect(firstBody.subject).toContain('Mulberry');
    // Extra ticket mentions the found SO.
    const extraBody = mockSupport.createTicket.mock.calls[2][1];
    expect(extraBody.subject).toContain('unexpected');
    expect(extraBody.body).toContain('6998');

    expect(res).toMatchObject({
      locationName: 'Mulberry',
      missingReported: 2,
      extrasReported: 1,
      totalReported: 3,
    });
    expect(mockPrisma.auditLog.create).toHaveBeenCalledTimes(1);
    expect(mockPrisma.auditLog.create.mock.calls[0][0].data.action).toBe(
      'yard_audit.submitted',
    );
  });

  it('de-dupes missing ids and drops empty extras', async () => {
    mockPrisma.location.findUnique.mockResolvedValue({ id: 3, name: 'Jax' });
    mockPrisma.trailer.findMany.mockResolvedValue([
      { id: BigInt(101), soNumber: '7031', trailerModel: { displayName: '10K' } },
    ]);

    const res = await service.submitAudit(BigInt(9), {
      locationId: 3,
      missingTrailerIds: [101, 101, 101],
      extras: [{ soNumber: '  ', note: '   ' }, {}],
    });

    expect(res.missingReported).toBe(1);
    expect(res.extrasReported).toBe(0);
    expect(mockSupport.createTicket).toHaveBeenCalledTimes(1);
  });

  it('falls back to #id when a missing trailer id is not found', async () => {
    mockPrisma.location.findUnique.mockResolvedValue({ id: 3, name: 'Mulberry' });
    mockPrisma.trailer.findMany.mockResolvedValue([]); // none resolve

    await service.submitAudit(BigInt(9), {
      locationId: 3,
      missingTrailerIds: [555],
    });

    expect(mockSupport.createTicket.mock.calls[0][1].subject).toContain('#555');
  });

  it('rejects an audit that would open more than the cap', async () => {
    mockPrisma.location.findUnique.mockResolvedValue({ id: 3, name: 'Mulberry' });
    const tooMany = Array.from({ length: 301 }, (_, i) => i + 1);

    await expect(
      service.submitAudit(BigInt(9), { locationId: 3, missingTrailerIds: tooMany }),
    ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
    expect(mockSupport.createTicket).not.toHaveBeenCalled();
  });
});
