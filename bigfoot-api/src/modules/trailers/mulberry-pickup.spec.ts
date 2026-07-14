import { TrailerSaleStatus, TrailerStatus } from '@prisma/client';
import { TrailersService } from './trailers.service';

/**
 * The dashboard tile "Customer Pickups @ Mulberry" and the list you get when
 * you tap it MUST be the same set. They used to be two hand-written filter
 * sets (the tile counted server-side; the client re-sent four query params to
 * rebuild the same query), so any drift — including an older app build —
 * produced a tile that disagreed with its own list.
 *
 * They now both go through mulberryCustomerPickupWhere(). This test pins the
 * definition so a change has to be deliberate.
 */
describe('Mulberry customer-pickup filter', () => {
  it('is a single canonical definition', () => {
    expect(TrailersService.mulberryCustomerPickupWhere()).toEqual({
      status: TrailerStatus.ready_for_delivery,
      isStockBuild: false,
      // A customer build that is not formally sold is in limbo, not a pickup.
      saleStatus: TrailerSaleStatus.sold,
      currentLocation: { code: 'MULBERRY' },
    });
  });
});
