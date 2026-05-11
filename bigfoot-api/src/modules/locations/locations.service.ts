import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

const LOCATION_SELECT = {
  id: true,
  code: true,
  name: true,
  city: true,
  state: true,
  shortLabel: true,
  isFactory: true,
  isActive: true,
} satisfies Prisma.LocationSelect;

@Injectable()
export class LocationsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * List locations. When `stockOnly` is true, only non-factory active rows
   * are returned — these are the destinations a stock build / delivery can
   * be sent to.
   */
  async findAll(opts: { stockOnly?: boolean; activeOnly?: boolean } = {}) {
    const where: Prisma.LocationWhereInput = {};
    if (opts.stockOnly) where.isFactory = false;
    if (opts.stockOnly || opts.activeOnly) where.isActive = true;

    return this.prisma.location.findMany({
      where,
      select: LOCATION_SELECT,
      orderBy: [{ isFactory: 'desc' }, { name: 'asc' }],
    });
  }
}
