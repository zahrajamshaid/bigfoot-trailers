/**
 * DELIVERY FLOW E2E — Complete single_pull delivery lifecycle.
 *
 * Create trailer → complete all steps → create delivery → driver departs
 * → driver completes (with photo + payment) → verify status transitions + SMS.
 */
import * as request from 'supertest';
import { PrismaService } from '../../src/prisma/prisma.service';
import { createTestApp, TestContext } from '../helpers/test-app.helper';
import {
  seedReferenceData,
  seedTestChecklistItems,
  cleanupTransactionalData,
} from '../helpers/test-db.helper';
import { createAndLogin, TestUser } from '../helpers/auth.helper';
import { completeFullWorkflow } from '../helpers/workflow.helper';

describe('Delivery Flow (e2e)', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let httpServer: any;
  let owner: TestUser;
  let qcInspector: TestUser;
  let worker: TestUser;
  let driver: TestUser;
  let transportManager: TestUser;
  let checklistItemMap: Map<string, number>;
  let xpModelId: number;

  beforeAll(async () => {
    ctx = await createTestApp();
    prisma = ctx.prisma;
    httpServer = ctx.httpServer;

    await seedReferenceData(prisma);
    await cleanupTransactionalData(prisma);
    checklistItemMap = await seedTestChecklistItems(prisma);

    owner = await createAndLogin(prisma, httpServer, 'owner', {
      fullName: 'E2E Owner',
    });
    qcInspector = await createAndLogin(prisma, httpServer, 'qc_inspector', {
      fullName: 'E2E QC Inspector',
    });
    worker = await createAndLogin(prisma, httpServer, 'worker', {
      fullName: 'E2E Worker',
    });
    driver = await createAndLogin(prisma, httpServer, 'driver', {
      fullName: 'E2E Driver',
    });
    transportManager = await createAndLogin(prisma, httpServer, 'transport_manager', {
      fullName: 'E2E Transport Mgr',
    });

    const xpModel = await prisma.trailerModel.findFirst({
      where: { code: 'XP_14ET' },
      select: { id: true },
    });
    xpModelId = xpModel!.id;
  }, 60_000);

  afterAll(async () => {
    await cleanupTransactionalData(prisma);
    await ctx.app.close();
  });

  // ── Single-Pull Delivery Lifecycle ────────────────────────────────────────

  it('should complete single_pull delivery lifecycle: create → depart → complete', async () => {
    // ── 1. Create trailer and complete full production workflow ──────────
    const createRes = await request(httpServer)
      .post('/v1/trailers')
      .set('Authorization', `Bearer ${owner.token}`)
      .send({ soNumber: 'E2E-DELIVERY-1', trailerModelId: xpModelId })
      .expect(201);

    const trailerId = BigInt(createRes.body.data.trailer.id);

    await completeFullWorkflow(
      prisma, httpServer, trailerId, worker.id,
      qcInspector.token, checklistItemMap,
    );

    // Confirm trailer is ready_for_delivery
    const trailerBefore = await prisma.trailer.findUnique({
      where: { id: trailerId },
      select: { status: true },
    });
    expect(trailerBefore!.status).toBe('ready_for_delivery');

    // ── 2. Create single_pull delivery ──────────────────────────────────
    const deliveryRes = await request(httpServer)
      .post('/v1/deliveries')
      .set('Authorization', `Bearer ${transportManager.token}`)
      .send({
        trailerId: Number(trailerId),
        deliveryType: 'single_pull',
        driverUserId: Number(driver.id),
        customerDeliveryAddress: '123 Test St, Anytown, FL 33801',
        balanceDue: 5000,
      })
      .expect(201);

    const deliveryId = deliveryRes.body.data.id;
    expect(deliveryRes.body.data.status).toBe('scheduled');
    expect(deliveryRes.body.data.deliveryType).toBe('single_pull');
    expect(Number(deliveryRes.body.data.balanceDue)).toBe(5000);

    // ── 3. Driver departs ───────────────────────────────────────────────
    const departRes = await request(httpServer)
      .patch(`/v1/deliveries/${deliveryId}/depart`)
      .set('Authorization', `Bearer ${driver.token}`)
      .expect(200);

    expect(departRes.body.data.status).toBe('in_transit');
    expect(departRes.body.data.departedAt).toBeTruthy();

    // Trailer status should transition to in_transit
    const trailerAfterDepart = await prisma.trailer.findUnique({
      where: { id: trailerId },
      select: { status: true },
    });
    expect(trailerAfterDepart!.status).toBe('in_transit');

    // Verify driver_en_route SMS was queued (no customer on this trailer,
    // so SMS is only created if a customer with smsPhone exists — skip check)

    // ── 4. Driver completes delivery with payment + photo ───────────────
    const completeRes = await request(httpServer)
      .post(`/v1/deliveries/${deliveryId}/complete`)
      .set('Authorization', `Bearer ${driver.token}`)
      .send({
        paymentCollected: 5000,
        paymentMethod: 'cashiers_check',
        photoStorageKeys: ['e2e/delivery-proof-1.jpg'],
        tcAccepted: true,
        gpsLat: 27.7951,
        gpsLng: -82.4001,
      })
      .expect(200);

    expect(completeRes.body.data.status).toBe('delivered');
    expect(completeRes.body.data.deliveredAt).toBeTruthy();

    // Trailer status should transition to delivered
    const trailerAfterComplete = await prisma.trailer.findUnique({
      where: { id: trailerId },
      select: { status: true },
    });
    expect(trailerAfterComplete!.status).toBe('delivered');

    // ── 5. Verify delivery detail endpoint ──────────────────────────────
    const detailRes = await request(httpServer)
      .get(`/v1/deliveries/${deliveryId}`)
      .set('Authorization', `Bearer ${owner.token}`)
      .expect(200);

    const detail = detailRes.body.data;
    expect(detail.status).toBe('delivered');
    expect(Number(detail.paymentCollected)).toBe(5000);
    expect(detail.paymentMethod).toBe('cashiers_check');
    expect(detail.tcAccepted).toBe(true);
    expect(detail.gpsLat).toBeTruthy();
    expect(detail.gpsLng).toBeTruthy();
  });

  // ── Delivery with customer + SMS verification ─────────────────────────────

  it('should queue SMS notifications when customer has smsPhone', async () => {
    // Create a customer with an SMS-enabled phone
    const customer = await prisma.customer.create({
      data: {
        name: 'E2E Test Customer',
        smsPhone: '+15551234567',
        customerType: 'end_user' as any,
        smsOptOut: false,
      },
      select: { id: true },
    });

    // Create trailer with customer attached
    const createRes = await request(httpServer)
      .post('/v1/trailers')
      .set('Authorization', `Bearer ${owner.token}`)
      .send({
        soNumber: 'E2E-DELIVERY-SMS',
        trailerModelId: xpModelId,
        customerId: Number(customer.id),
      })
      .expect(201);

    const trailerId = BigInt(createRes.body.data.trailer.id);

    // Complete workflow
    await completeFullWorkflow(
      prisma, httpServer, trailerId, worker.id,
      qcInspector.token, checklistItemMap,
    );

    // Verify trailer_complete SMS was queued by FINAL_QC pass
    const trailerCompleteSms = await prisma.smsLog.findFirst({
      where: { trailerId, smsType: 'trailer_complete' as any },
      select: { id: true, recipientPhone: true, status: true },
    });
    expect(trailerCompleteSms).toBeTruthy();
    expect(trailerCompleteSms!.recipientPhone).toBe('+15551234567');
    expect(trailerCompleteSms!.status).toBe('queued');

    // Create delivery, depart, complete
    const deliveryRes = await request(httpServer)
      .post('/v1/deliveries')
      .set('Authorization', `Bearer ${transportManager.token}`)
      .send({
        trailerId: Number(trailerId),
        deliveryType: 'single_pull',
        driverUserId: Number(driver.id),
      })
      .expect(201);
    const deliveryId = deliveryRes.body.data.id;

    await request(httpServer)
      .patch(`/v1/deliveries/${deliveryId}/depart`)
      .set('Authorization', `Bearer ${driver.token}`)
      .expect(200);

    // Verify driver_en_route SMS was queued
    const enRouteSms = await prisma.smsLog.findFirst({
      where: { trailerId, smsType: 'driver_en_route' as any },
      select: { id: true, recipientPhone: true },
    });
    expect(enRouteSms).toBeTruthy();
    expect(enRouteSms!.recipientPhone).toBe('+15551234567');

    await request(httpServer)
      .post(`/v1/deliveries/${deliveryId}/complete`)
      .set('Authorization', `Bearer ${driver.token}`)
      .send({ paymentCollected: 0 })
      .expect(200);

    // Verify delivery_complete SMS was queued
    const completeSms = await prisma.smsLog.findFirst({
      where: { trailerId, smsType: 'delivery_complete' as any },
      select: { id: true, recipientPhone: true },
    });
    expect(completeSms).toBeTruthy();
    expect(completeSms!.recipientPhone).toBe('+15551234567');

    // Clean up test customer
    await prisma.customer.delete({ where: { id: customer.id } });
  });
});
