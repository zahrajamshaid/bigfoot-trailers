import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { AppError, ErrorCode } from '../../common/errors';
import {
  CreateCustomerDto,
  UpdateCustomerDto,
  QueryCustomersDto,
} from './dto';

const CUSTOMER_SELECT = {
  id: true,
  name: true,
  company: true,
  smsPhone: true,
  email: true,
  billingAddress: true,
  deliveryAddress: true,
  customerType: true,
  smsOptOut: true,
  qbCustomerId: true,
  notes: true,
  createdAt: true,
  updatedAt: true,
} satisfies Prisma.CustomerSelect;

@Injectable()
export class CustomersService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(query: QueryCustomersDto) {
    const page = query.page ?? 1;
    const limit = query.limit ?? 50;

    const where: Prisma.CustomerWhereInput = {};
    if (query.customerType) where.customerType = query.customerType;
    if (query.search) {
      const s = query.search.trim();
      where.OR = [
        { name: { contains: s, mode: 'insensitive' } },
        { company: { contains: s, mode: 'insensitive' } },
        { email: { contains: s, mode: 'insensitive' } },
        { smsPhone: { contains: s } },
      ];
    }

    const [items, total] = await this.prisma.$transaction([
      this.prisma.customer.findMany({
        where,
        select: CUSTOMER_SELECT,
        orderBy: [{ name: 'asc' }],
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.customer.count({ where }),
    ]);

    return {
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  async findOne(id: bigint) {
    const customer = await this.prisma.customer.findUnique({
      where: { id },
      select: {
        ...CUSTOMER_SELECT,
        trailers: {
          select: { id: true, soNumber: true, status: true, createdAt: true },
          orderBy: { createdAt: 'desc' },
          take: 20,
        },
      },
    });
    if (!customer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Customer ${id} not found`);
    }
    return customer;
  }

  async create(dto: CreateCustomerDto) {
    return this.prisma.customer.create({
      data: dto,
      select: CUSTOMER_SELECT,
    });
  }

  async update(id: bigint, dto: UpdateCustomerDto) {
    await this.assertExists(id);
    return this.prisma.customer.update({
      where: { id },
      data: dto,
      select: CUSTOMER_SELECT,
    });
  }

  async remove(id: bigint) {
    await this.assertExists(id);
    const trailerCount = await this.prisma.trailer.count({
      where: { customerId: id },
    });
    if (trailerCount > 0) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Cannot delete customer ${id} — ${trailerCount} trailer(s) reference this customer`,
      );
    }
    await this.prisma.customer.delete({ where: { id } });
    return { success: true };
  }

  private async assertExists(id: bigint) {
    const exists = await this.prisma.customer.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!exists) {
      throw new AppError(ErrorCode.NOT_FOUND, `Customer ${id} not found`);
    }
  }
}
