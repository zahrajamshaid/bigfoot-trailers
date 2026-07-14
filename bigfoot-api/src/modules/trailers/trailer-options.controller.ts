import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Post,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsArray, IsInt, IsOptional, IsString, MaxLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { CurrentUser, JwtPayload, Roles, UserRole } from '../../common/decorators';
import { TrailerOptionsService } from './trailer-options.service';

export class AddOptionDto {
  @ApiProperty({ description: 'Option / add-on name, e.g. "Extra D-rings (x2)"' })
  @IsString()
  @MaxLength(150)
  addonName!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiPropertyOptional({
    description:
      'EVERY department that has to fit part of this option — an option can ' +
      'need more than one (D-rings welded at JIG, touched up at PAINT). Each ' +
      'must acknowledge its own part before it can complete its step. Omit to ' +
      'leave unassigned: the option is then visible to all and blocks nobody.',
    type: [Number],
  })
  @IsOptional()
  @IsArray()
  @IsInt({ each: true })
  installDepartmentIds?: number[];
}

@ApiTags('Trailer Options')
@ApiBearerAuth('JWT')
@Controller()
export class TrailerOptionsController {
  constructor(private readonly options: TrailerOptionsService) {}

  // ── The shop floor ────────────────────────────────────────────────────────

  /** Options a worker sees at their step, flagged with what they must ack. */
  @Get('production/steps/:stepId/options')
  @Roles(
    UserRole.OWNER,
    UserRole.PRODUCTION_MANAGER,
    UserRole.QC_INSPECTOR,
    UserRole.WORKER,
    UserRole.PARTS,
    UserRole.OFFICE,
  )
  @ApiOperation({
    summary: 'Options for a step — which this department must acknowledge',
  })
  listForStep(@Param('stepId', ParseIntPipe) stepId: number) {
    return this.options.listForStep(BigInt(stepId));
  }

  /** "Yes, I fitted this." Required before this department can complete. */
  @Post('trailers/options/:addonId/acknowledge')
  @Roles(
    UserRole.OWNER,
    UserRole.PRODUCTION_MANAGER,
    UserRole.QC_INSPECTOR,
    UserRole.WORKER,
  )
  @ApiOperation({
    summary:
      'Acknowledge that THIS department fitted its part of the option. The id ' +
      'is the option-department assignment (each department acknowledges ' +
      'independently).',
  })
  acknowledge(
    @Param('addonId', ParseIntPipe) addonId: number,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.options.acknowledge(BigInt(addonId), BigInt(user.sub));
  }

  // ── Sales / office adding an option ───────────────────────────────────────

  @Post('trailers/:id/options')
  @Roles(UserRole.OWNER, UserRole.OFFICE, UserRole.SALES, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({
    summary:
      'Add an option. If the build has already started it is flagged for the ' +
      'production manager instead of silently disappearing into the build.',
  })
  addOption(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: AddOptionDto,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.options.addOption(BigInt(id), dto, BigInt(user.sub));
  }

  @Get('trailers/:id/options')
  @Roles(
    UserRole.OWNER,
    UserRole.OFFICE,
    UserRole.SALES,
    UserRole.PRODUCTION_MANAGER,
    UserRole.QC_INSPECTOR,
    UserRole.WORKER,
    UserRole.PARTS,
  )
  @ApiOperation({ summary: 'All options on a trailer + acknowledgement state' })
  listForTrailer(@Param('id', ParseIntPipe) id: number) {
    return this.options.listForTrailer(BigInt(id));
  }

  // ── The dashboard box (admin + production manager) ────────────────────────

  /**
   * Options added AFTER the build started that the production manager hasn't
   * reviewed. Each row says where the build is now vs. where the option needs
   * fitting, so `needsRollback` tells the PM which trailers are about to be
   * built wrong.
   */
  @Get('trailers/options/pending-review')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({
    summary: 'Dashboard: options added mid-build, awaiting production-manager review',
  })
  pendingReview() {
    return this.options.listPendingProductionManagerReview();
  }

  /** PM has seen it → clears the trailer off the dashboard box. */
  @Post('trailers/options/:addonId/review')
  @Roles(UserRole.OWNER, UserRole.PRODUCTION_MANAGER)
  @ApiOperation({ summary: 'Production manager acknowledges a mid-build option' })
  review(
    @Param('addonId', ParseIntPipe) addonId: number,
    @CurrentUser() user: JwtPayload,
  ) {
    return this.options.productionManagerAcknowledge(
      BigInt(addonId),
      BigInt(user.sub),
    );
  }
}
