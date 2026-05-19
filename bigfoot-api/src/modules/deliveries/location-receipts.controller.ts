import { Controller, Post, Body, HttpCode, HttpStatus } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { LocationReceiptsService } from './location-receipts.service';
import { CreateLocationReceiptDto } from './dto';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';

@ApiTags('Location Receipts')
@ApiBearerAuth('JWT')
@Controller('location-receipts')
export class LocationReceiptsController {
  constructor(private readonly locationReceiptsService: LocationReceiptsService) {}

  // ---------------------------------------------------------------------------
  // POST /location-receipts
  // ---------------------------------------------------------------------------
  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Remote location staff confirms trailer received' })
  @ApiResponse({ status: 201, description: 'Location receipt created' })
  @ApiResponse({ status: 400, description: 'LOCATION_RECEIPT_WRONG_LOCATION' })
  async create(
    @Body() dto: CreateLocationReceiptDto,
    @CurrentUser() requester: JwtPayload,
  ) {
    return this.locationReceiptsService.create(dto, BigInt(requester.sub));
  }
}
