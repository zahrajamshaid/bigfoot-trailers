import { Controller, Post, Get, Body, Param } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { StorageService } from './storage.service';
import { PresignUploadDto } from './dto';

@ApiTags('Storage')
@Controller('storage')
export class StorageController {
  constructor(private readonly storageService: StorageService) {}

  // -------------------------------------------------------------------------
  // POST /storage/presign — generate pre-signed upload URL
  // -------------------------------------------------------------------------
  @Post('presign')
  async presignUpload(@Body() dto: PresignUploadDto) {
    return this.storageService.generateUploadUrl({
      fileType: dto.fileType,
      trailerId: dto.trailerId,
      fileName: dto.fileName,
    });
  }

  // -------------------------------------------------------------------------
  // GET /storage/presign/:key — generate pre-signed download URL
  // -------------------------------------------------------------------------
  @Get('presign/*key')
  async presignDownload(@Param('key') key: string) {
    return this.storageService.generateDownloadUrl(key);
  }
}
