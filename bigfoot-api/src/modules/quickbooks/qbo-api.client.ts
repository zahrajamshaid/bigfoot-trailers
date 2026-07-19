import { Injectable, Logger } from '@nestjs/common';
import { AppError, ErrorCode } from '../../common/errors';
import { QboAuthService } from './qbo-auth.service';

/**
 * Thin typed HTTP client over the QuickBooks Online REST API.
 *
 * Every call injects a fresh bearer token (via QboAuthService), targets the
 * correct realm's base URL, sets the required `Version` + JSON headers, and
 * transparently retries once on a 401 (token rotated underneath us). Higher-
 * level mapping/sync logic lives in later slices — this is just the wire.
 *
 * Base URLs differ by environment; the OAuth endpoints do not (those are in
 * QboAuthService).
 */
@Injectable()
export class QboApiClient {
  private readonly logger = new Logger('QboApiClient');
  /** Intuit pins a minor-version date header on the Accounting API. */
  private static readonly MINOR_VERSION_HEADER = '2021-07-28';

  constructor(private readonly auth: QboAuthService) {}

  private baseUrl(): string {
    return this.auth.environment() === 'production'
      ? 'https://quickbooks.api.intuit.com'
      : 'https://sandbox-quickbooks.api.intuit.com';
  }

  /**
   * Make a request against `/v3/company/{realmId}{path}`. `path` should start
   * with `/` (e.g. `/companyinfo/{realmId}`). Returns parsed JSON.
   */
  async request<T = unknown>(
    method: 'GET' | 'POST',
    path: string,
    body?: unknown,
    retryOn401 = true,
  ): Promise<T> {
    const { accessToken, realmId } = await this.auth.getValidAccessToken();
    const url = `${this.baseUrl()}/v3/company/${realmId}${path}`;
    const res = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: 'application/json',
        'Content-Type': 'application/json',
        // Intuit reads the minor version from the query string on some
        // endpoints and the header on others; the header form is universal.
        'intuit-minor-version': QboApiClient.MINOR_VERSION_HEADER,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    if (res.status === 401 && retryOn401) {
      // A 401 means the token Intuit gave us was rejected even though our clock
      // thought it was valid. FORCE a refresh (not the passive expiry check),
      // then retry once with the fresh token now in the DB.
      this.logger.warn('QBO returned 401 — forcing a token refresh and retrying once');
      await this.auth.getValidAccessToken({ forceRefresh: true });
      return this.request<T>(method, path, body, false);
    }

    if (res.status === 429) {
      throw new AppError(
        ErrorCode.TOO_MANY_REQUESTS,
        'QuickBooks rate limit hit — the sync worker will back off and retry',
      );
    }

    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      this.logger.error(`QBO ${method} ${path} → ${res.status}`);
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        `QuickBooks API error (${res.status})${detail ? `: ${detail.slice(0, 200)}` : ''}`,
      );
    }

    return (await res.json()) as T;
  }

  /** Smoke-test call used by the health endpoint — reads CompanyInfo. */
  async getCompanyInfo(): Promise<{ companyName?: string }> {
    const { realmId } = await this.auth.getValidAccessToken();
    const data = await this.request<{
      CompanyInfo?: { CompanyName?: string };
    }>('GET', `/companyinfo/${realmId}`);
    return { companyName: data.CompanyInfo?.CompanyName };
  }

  /** Full company header (name + address + email) for document generation. */
  async getCompanyHeader(): Promise<QboCompanyHeader> {
    const { realmId } = await this.auth.getValidAccessToken();
    const data = await this.request<{ CompanyInfo?: QboCompanyInfo }>(
      'GET',
      `/companyinfo/${realmId}`,
    );
    const ci = data.CompanyInfo ?? {};
    const addr = ci.CompanyAddr ?? {};
    const cityStateZip = [
      [addr.City, addr.CountrySubDivisionCode].filter(Boolean).join(', '),
      addr.PostalCode,
    ]
      .filter(Boolean)
      .join(' ');
    return {
      name: ci.CompanyName ?? 'Bigfoot Trailers',
      addressLines: [addr.Line1, cityStateZip].filter(
        (l): l is string => !!l && l.length > 0,
      ),
      email: ci.Email?.Address,
    };
  }

  /**
   * Run a QBO query (their SQL-ish dialect) and return the named entity
   * array. E.g. query('Customer', 'SELECT * FROM Customer MAXRESULTS 100').
   * QBO wraps results as { QueryResponse: { Customer: [...] } }.
   */
  async query<T = unknown>(entity: string, sql: string): Promise<T[]> {
    const data = await this.request<{
      QueryResponse?: Record<string, T[]>;
    }>('GET', `/query?query=${encodeURIComponent(sql)}`);
    return data.QueryResponse?.[entity] ?? [];
  }

  /** All active customers (id, name, company, contact) for the catalog. */
  async listCustomers(): Promise<QboCustomer[]> {
    return this.query<QboCustomer>(
      'Customer',
      'SELECT * FROM Customer WHERE Active = true ORDERBY Metadata.LastUpdatedTime DESC MAXRESULTS 1000',
    );
  }

  /** All active products/services (the models + options + fees). */
  async listItems(): Promise<QboItem[]> {
    return this.query<QboItem>(
      'Item',
      'SELECT * FROM Item WHERE Active = true MAXRESULTS 1000',
    );
  }

  /**
   * Create an Estimate in QBO and return QBO's version — which includes the
   * QBO-computed tax (TxnTaxDetail) and total (TotalAmt). We never compute
   * tax in-app; we push the lines and read QBO's numbers back. This is the
   * core of the app-native Sales Order → QBO Estimate push.
   */
  async createEstimate(payload: QboEstimateCreate): Promise<QboEstimate> {
    const data = await this.request<{ Estimate: QboEstimate }>(
      'POST',
      '/estimate?minorversion=73',
      payload,
    );
    return data.Estimate;
  }

  /**
   * Record a customer payment in QuickBooks — used for a deposit taken on a
   * trailer. Created UNAPPLIED (no Line): with just a CustomerRef + TotalAmt it
   * posts as an available credit on the customer's account, which the eventual
   * invoice draws down. `paymentDate` is an ISO date (yyyy-mm-dd) supplied by
   * the caller (services stay deterministic — no Date.now() in here).
   */
  async createPayment(input: {
    customerRef: string;
    amount: number;
    paymentDate: string;
    memo?: string;
  }): Promise<{ Id: string }> {
    const data = await this.request<{ Payment: { Id: string } }>(
      'POST',
      '/payment',
      {
        CustomerRef: { value: input.customerRef },
        TotalAmt: input.amount,
        TxnDate: input.paymentDate,
        ...(input.memo ? { PrivateNote: input.memo } : {}),
      },
    );
    return data.Payment;
  }

  /** Read one estimate back (e.g. to refresh status / PDF link). */
  async getEstimate(id: string): Promise<QboEstimate> {
    const data = await this.request<{ Estimate: QboEstimate }>(
      'GET',
      `/estimate/${id}`,
    );
    return data.Estimate;
  }

  /**
   * Email the estimate to the customer via QuickBooks (the same "Send" action
   * in the QBO estimate menu). If `email` is omitted QBO uses the customer's
   * billing email. Sets EmailStatus=EmailSent on the estimate.
   *
   * QBO's send pipeline throws a NullPointerException when the estimate
   * transaction has no BillEmail — even when a `sendTo` is supplied — so when
   * we know the address we sparse-update BillEmail onto the estimate first.
   */
  async sendEstimate(id: string, email?: string): Promise<QboEstimate> {
    if (email) {
      const current = await this.getEstimate(id);
      await this.request('POST', '/estimate', {
        Id: id,
        SyncToken: current.SyncToken,
        sparse: true,
        BillEmail: { Address: email },
      });
    }
    const qs = email ? `?sendTo=${encodeURIComponent(email)}` : '';
    const data = await this.request<{ Estimate: QboEstimate }>(
      'POST',
      `/estimate/${id}/send${qs}`,
    );
    return data.Estimate;
  }

  /**
   * Mark an estimate Accepted (QBO's estimate status transition). QBO requires
   * a sparse update carrying the current SyncToken, so we read it first, then
   * PATCH just TxnStatus + AcceptedBy/AcceptedDate. `acceptedDate` must be an
   * ISO date (yyyy-mm-dd); the caller supplies it (no Date.now() in services
   * that need to stay deterministic — pass it in).
   */
  /**
   * Delete an estimate in QuickBooks. QBO's delete is a POST with
   * ?operation=delete carrying the current SyncToken (read it first). Used when
   * an estimate is removed in the app so the two stay in step.
   */
  async deleteEstimate(id: string): Promise<void> {
    const current = await this.getEstimate(id);
    await this.request('POST', '/estimate?operation=delete', {
      Id: id,
      SyncToken: current.SyncToken,
    });
  }

  async acceptEstimate(
    id: string,
    acceptedBy: string,
    acceptedDate: string,
  ): Promise<QboEstimate> {
    const current = await this.getEstimate(id);
    const data = await this.request<{ Estimate: QboEstimate }>(
      'POST',
      '/estimate',
      {
        Id: id,
        SyncToken: current.SyncToken,
        sparse: true,
        TxnStatus: 'Accepted',
        AcceptedBy: acceptedBy,
        AcceptedDate: acceptedDate,
      },
    );
    return data.Estimate;
  }

  /** Create a Customer in QBO. DisplayName must be unique. */
  async createCustomer(payload: Record<string, unknown>): Promise<QboCustomer> {
    const data = await this.request<{ Customer: QboCustomer }>(
      'POST',
      '/customer',
      payload,
    );
    return data.Customer;
  }

  /** Create a Product/Service Item in QBO (needs IncomeAccountRef). */
  async createItem(payload: Record<string, unknown>): Promise<QboItem> {
    const data = await this.request<{ Item: QboItem }>('POST', '/item', payload);
    return data.Item;
  }

  /**
   * Fetch the estimate's PDF (the same document QuickBooks lets you
   * download) as raw bytes. Uses a direct fetch with Accept: application/pdf
   * rather than the JSON request() path.
   */
  async getEstimatePdf(estimateId: string): Promise<Buffer> {
    const { accessToken, realmId } = await this.auth.getValidAccessToken();
    const url = `${this.baseUrl()}/v3/company/${realmId}/estimate/${estimateId}/pdf`;
    const res = await fetch(url, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: 'application/pdf',
      },
    });
    if (!res.ok) {
      this.logger.error(`QBO estimate PDF ${estimateId} → ${res.status}`);
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        `QuickBooks estimate PDF fetch failed (${res.status})`,
      );
    }
    return Buffer.from(await res.arrayBuffer());
  }

  /** First income account id — items must reference one. */
  async firstIncomeAccountId(): Promise<string | null> {
    const accts = await this.query<{ Id: string }>(
      'Account',
      "SELECT * FROM Account WHERE AccountType = 'Income' MAXRESULTS 5",
    );
    return accts[0]?.Id ?? null;
  }
}

/** Minimal Estimate create payload (one or more SalesItemLine rows). */
export interface QboEstimateCreate {
  CustomerRef: { value: string };
  BillEmail?: { Address: string };
  DocNumber?: string;
  PrivateNote?: string; // carries our idempotency key
  Line: Array<{
    DetailType: 'SalesItemLineDetail';
    Amount: number;
    Description?: string;
    SalesItemLineDetail: {
      ItemRef: { value: string };
      Qty?: number;
      UnitPrice?: number;
      TaxCodeRef?: { value: string };
    };
  }>;
}

/** Trimmed Estimate response — what we store + display. */
export interface QboEstimate {
  Id: string;
  SyncToken?: string;
  DocNumber?: string;
  TotalAmt?: number;
  TxnTaxDetail?: { TotalTax?: number };
  CustomerRef?: { value: string; name?: string };
  TxnStatus?: string;
  EmailStatus?: string;
  Line?: unknown[];
}

/** Trimmed QBO Customer shape — only the fields the catalog needs. */
export interface QboCustomer {
  Id: string;
  DisplayName?: string;
  CompanyName?: string;
  GivenName?: string;
  FamilyName?: string;
  PrimaryEmailAddr?: { Address?: string };
  PrimaryPhone?: { FreeFormNumber?: string };
  BillAddr?: { Line1?: string; City?: string; CountrySubDivisionCode?: string; PostalCode?: string };
  Taxable?: boolean;
  Active?: boolean;
}

/** Company header used when generating documents (packing slip). */
export interface QboCompanyHeader {
  name: string;
  addressLines: string[];
  email?: string;
}

/** Raw QBO CompanyInfo (subset we read). */
interface QboCompanyInfo {
  CompanyName?: string;
  CompanyAddr?: {
    Line1?: string;
    City?: string;
    CountrySubDivisionCode?: string;
    PostalCode?: string;
  };
  Email?: { Address?: string };
}

/** Trimmed QBO Item shape (Product/Service). */
export interface QboItem {
  Id: string;
  Name?: string;
  FullyQualifiedName?: string;
  Description?: string;
  Type?: string; // Inventory | NonInventory | Service
  UnitPrice?: number;
  Taxable?: boolean;
  Active?: boolean;
  Sku?: string;
}
