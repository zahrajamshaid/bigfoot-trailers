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
  //
  // Mobile sends the storage key URL-encoded so embedded slashes don't
  // collapse into path segments. Express decodes :key automatically, so
  // `qc/3/abc.jpg` on the wire as `qc%2F3%2Fabc.jpg` arrives here as the
  // original key. The previous `presign/*key` wildcard was Express-5-only
  // syntax and silently 404'd under Nest 10 / Express 4.
  // -------------------------------------------------------------------------
  @Get('presign/:key')
  async presignDownload(@Param('key') key: string) {
    return this.storageService.generateDownloadUrl(key);
  }
}
