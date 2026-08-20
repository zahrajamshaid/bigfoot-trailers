import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { Roles, UserRole } from '../../common/decorators/roles.decorator';
import { CurrentUser, JwtPayload } from '../../common/decorators/current-user.decorator';
import { YardAuditService } from './yard-audit.service';
import { SubmitAuditDto } from './dto';

@ApiTags('Yard Audit')
@ApiBearerAuth('JWT')
@Controller('yard-audit')
export class YardAuditController {
  constructor(private readonly service: YardAuditService) {}

  // ---------------------------------------------------------------------------
  // POST /yard-audit — sales + admin (owner/office) reconcile a yard's app
  // inventory against the physical lot; discrepancies become problem reports.
  // ---------------------------------------------------------------------------
  @Post()
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES)
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({
    summary:
      'Submit a yard audit. Opens one problem report per missing trailer and per unexpected extra.',
  })
  @ApiResponse({ status: 201, description: 'Audit recorded; reports opened' })
  @ApiResponse({ status: 404, description: 'Location not found' })
  async submit(@Body() dto: SubmitAuditDto, @CurrentUser() user: JwtPayload) {
    return this.service.submitAudit(BigInt(user.sub), dto);
  }
}
