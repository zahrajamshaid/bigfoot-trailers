import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * QuickBooks Online OAuth2 (authorization-code flow) — backend only.
 *
 * The Flutter app never touches QBO credentials. This service:
 *   - builds the Intuit consent URL (owner opens it in a browser),
 *   - exchanges the returned auth code for an access + refresh token pair,
 *   - persists the pair in `qbo_auth_tokens` (single realm),
 *   - hands out a always-fresh access token, refreshing it a few minutes
 *     before expiry so callers never hit a 401 for a predictably-expired
 *     token.
 *
 * Intuit endpoints (constant across sandbox + prod — only the API *base*
 * differs, which lives in QboApiClient):
 *   authorize: https://appcenter.intuit.com/connect/oauth2
 *   token:     https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer
 *   revoke:    https://developer.api.intuit.com/v2/oauth2/tokens/revoke
 */
@Injectable()
export class QboAuthService {
  private readonly logger = new Logger('QboAuth');

  private static readonly AUTHORIZE_URL =
    'https://appcenter.intuit.com/connect/oauth2';
  private static readonly TOKEN_URL =
    'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer';
  private static readonly REVOKE_URL =
    'https://developer.api.intuit.com/v2/oauth2/tokens/revoke';
  /** Refresh the access token when it has <5 min left. */
  private static readonly REFRESH_SKEW_MS = 5 * 60 * 1000;
  /** The accounting scope is all Phase 2 needs. */
  private static readonly SCOPE = 'com.intuit.quickbooks.accounting';

  /**
   * A single in-flight refresh, shared by all callers. Intuit ROTATES the
   * refresh token on every refresh (the old one dies), so two concurrent
   * refreshes would race: the second reuses a now-dead token and fails,
   * breaking the whole connection. A sync fires many QBO calls at once, so this
   * race is the real cause of the "401 / token expired" failures. Sharing one
   * refresh makes it impossible.
   */
  private refreshInFlight: Promise<{
    accessToken: string;
    realmId: string;
  }> | null = null;

  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  private clientId(): string {
    const id = this.config.get<string>('QBO_CLIENT_ID');
    if (!id) throw new AppError(ErrorCode.SERVICE_UNAVAILABLE, 'QBO_CLIENT_ID not configured');
    return id;
  }

  private clientSecret(): string {
    const secret = this.config.get<string>('QBO_CLIENT_SECRET');
    if (!secret)
      throw new AppError(ErrorCode.SERVICE_UNAVAILABLE, 'QBO_CLIENT_SECRET not configured');
    return secret;
  }

  private redirectUri(): string {
    const uri = this.config.get<string>('QBO_REDIRECT_URI');
    if (!uri)
      throw new AppError(ErrorCode.SERVICE_UNAVAILABLE, 'QBO_REDIRECT_URI not configured');
    return uri;
  }

  environment(): 'sandbox' | 'production' {
    return this.config.get<string>('QBO_ENVIRONMENT') === 'production'
      ? 'production'
      : 'sandbox';
  }

  /** Basic-auth header for the token endpoint (client_id:client_secret). */
  private basicAuthHeader(): string {
    const raw = `${this.clientId()}:${this.clientSecret()}`;
    return `Basic ${Buffer.from(raw).toString('base64')}`;
  }

  /**
   * The Intuit consent URL. `state` is an opaque anti-CSRF value the caller
   * generates and later verifies in the callback.
   */
  getAuthorizationUrl(state: string): string {
    const params = new URLSearchParams({
      client_id: this.clientId(),
      response_type: 'code',
      scope: QboAuthService.SCOPE,
      redirect_uri: this.redirectUri(),
      state,
    });
    return `${QboAuthService.AUTHORIZE_URL}?${params.toString()}`;
  }

  /**
   * Exchange the auth code from Intuit's redirect for tokens and persist
   * them against the realm (company). Upserts so re-connecting the same
   * company overwrites cleanly.
   */
  async handleCallback(code: string, realmId: string): Promise<void> {
    const body = new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: this.redirectUri(),
    });
    const tokens = await this.postToken(body);
    await this.persist(realmId, tokens);
    this.logger.log(`Connected QBO realm ${realmId} (${this.environment()})`);
  }

  /**
   * Return a valid access token for the connected realm, refreshing first if
   * it's within the skew window of expiry. Throws SERVICE_UNAVAILABLE if no
   * realm is connected yet.
   */
  async getValidAccessToken(opts?: {
    forceRefresh?: boolean;
  }): Promise<{ accessToken: string; realmId: string }> {
    const row = await this.currentToken();
    const expiringSoon =
      Date.now() >= row.accessExpiresAt.getTime() - QboAuthService.REFRESH_SKEW_MS;

    // forceRefresh comes from a 401: the stored token our clock thinks is still
    // valid was rejected by Intuit, so refresh regardless of the recorded expiry.
    if (!opts?.forceRefresh && !expiringSoon) {
      return { accessToken: row.accessToken, realmId: row.realmId };
    }

    // Serialize: ride the in-flight refresh if one is already running.
    if (!this.refreshInFlight) {
      this.refreshInFlight = this.refreshNow(row.realmId).finally(() => {
        this.refreshInFlight = null;
      });
    }
    return this.refreshInFlight;
  }

  /** Do one refresh using the LATEST stored refresh token (re-read to avoid a
   *  stale one), and hand back the new access token. */
  private async refreshNow(
    realmId: string,
  ): Promise<{ accessToken: string; realmId: string }> {
    // Re-read immediately before use: another path may have just rotated it.
    const row = await this.currentToken();
    try {
      const refreshed = await this.refresh(realmId, row.refreshToken);
      return { accessToken: refreshed.accessToken, realmId };
    } catch (e) {
      // A refresh failure means the refresh token is dead/expired — the only
      // fix is a fresh OAuth connect. Surface that clearly rather than a bare
      // 401 the caller can't act on.
      this.logger.error(
        `QBO token refresh failed (${e instanceof Error ? e.message : e}) — reconnect required`,
      );
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'QuickBooks needs to be reconnected — open Settings → Connect QuickBooks.',
      );
    }
  }

  /**
   * Keep-alive. Intuit refresh tokens rotate on every use and lapse only after
   * ~100 days UNUSED; refreshing on a schedule keeps the connection alive
   * indefinitely, so the token is always warm before anyone needs it. Runs
   * every 6 hours; a failure just logs (the next real call / next tick retries).
   */
  @Cron(CronExpression.EVERY_6_HOURS, { name: 'qbo-token-keepalive' })
  async keepTokenFresh(): Promise<void> {
    const row = await this.prisma.qboAuthToken.findFirst({
      orderBy: { updatedAt: 'desc' },
    });
    if (!row) return; // not connected — nothing to keep alive
    try {
      await this.getValidAccessToken({ forceRefresh: true });
      this.logger.log('QBO token keep-alive refresh OK');
    } catch {
      this.logger.warn('QBO token keep-alive refresh failed — reconnect may be needed');
    }
  }

  /** The connected realm's token row, or a typed 503 if not connected. */
  async currentToken() {
    const row = await this.prisma.qboAuthToken.findFirst({
      orderBy: { updatedAt: 'desc' },
    });
    if (!row) {
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'QuickBooks is not connected — run the OAuth connect flow first',
      );
    }
    return row;
  }

  /** Connection status for the health endpoint (no throw). */
  async status(): Promise<{
    connected: boolean;
    realmId?: string;
    environment: 'sandbox' | 'production';
    accessExpiresAt?: Date;
    refreshExpiresAt?: Date;
  }> {
    const row = await this.prisma.qboAuthToken.findFirst({
      orderBy: { updatedAt: 'desc' },
    });
    if (!row) return { connected: false, environment: this.environment() };
    return {
      connected: true,
      realmId: row.realmId,
      environment: this.environment(),
      accessExpiresAt: row.accessExpiresAt,
      refreshExpiresAt: row.refreshExpiresAt,
    };
  }

  private async refresh(realmId: string, refreshToken: string) {
    const body = new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
    });
    const tokens = await this.postToken(body);
    return this.persist(realmId, tokens);
  }

  private async persist(realmId: string, t: TokenResponse) {
    const now = Date.now();
    const accessExpiresAt = new Date(now + t.expires_in * 1000);
    // Intuit refresh tokens last ~100 days; store the horizon so we can warn
    // before it lapses (a lapsed refresh token needs a fresh OAuth connect).
    const refreshExpiresAt = new Date(
      now + (t.x_refresh_token_expires_in ?? 100 * 24 * 3600) * 1000,
    );
    return this.prisma.qboAuthToken.upsert({
      where: { realmId },
      create: {
        realmId,
        accessToken: t.access_token,
        refreshToken: t.refresh_token,
        accessExpiresAt,
        refreshExpiresAt,
        environment: this.environment(),
      },
      update: {
        accessToken: t.access_token,
        refreshToken: t.refresh_token,
        accessExpiresAt,
        refreshExpiresAt,
        environment: this.environment(),
      },
    });
  }

  private async postToken(body: URLSearchParams): Promise<TokenResponse> {
    const res = await fetch(QboAuthService.TOKEN_URL, {
      method: 'POST',
      headers: {
        Authorization: this.basicAuthHeader(),
        'Content-Type': 'application/x-www-form-urlencoded',
        Accept: 'application/json',
      },
      body: body.toString(),
    });
    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      // Never log the body verbatim — it can echo the code/secret. Log status.
      this.logger.error(`QBO token endpoint returned ${res.status}`);
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        `QuickBooks token exchange failed (${res.status})${detail ? `: ${detail.slice(0, 120)}` : ''}`,
      );
    }
    return (await res.json()) as TokenResponse;
  }

  /** Best-effort revoke on disconnect; clears the local row regardless. */
  async disconnect(): Promise<void> {
    const row = await this.prisma.qboAuthToken.findFirst({
      orderBy: { updatedAt: 'desc' },
    });
    if (!row) return;
    try {
      await fetch(QboAuthService.REVOKE_URL, {
        method: 'POST',
        headers: {
          Authorization: this.basicAuthHeader(),
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({ token: row.refreshToken }),
      });
    } catch {
      // Revoke is best-effort — we still drop the local token below.
    }
    await this.prisma.qboAuthToken.delete({ where: { realmId: row.realmId } });
    this.logger.log(`Disconnected QBO realm ${row.realmId}`);
  }
}

interface TokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  x_refresh_token_expires_in?: number;
  token_type: string;
}
