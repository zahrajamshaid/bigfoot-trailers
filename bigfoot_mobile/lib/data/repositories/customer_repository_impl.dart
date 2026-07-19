import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/customer_repository.dart';
import '../models/customer.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  final DioClient _api;

  CustomerRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<CustomersListResult> getCustomers({
    String? query,
    String? customerType,
    bool excludeStockLocations = false,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.customers,
      queryParameters: {
        // Backend QueryCustomersDto uses `search` (not `q`) — sending `q`
        // silently no-ops, which made the picker's search box ignore input.
        if (query != null && query.isNotEmpty) 'search': query,
        if (customerType != null && customerType.isNotEmpty) 'customerType': customerType,
        if (excludeStockLocations) 'excludeStockLocations': true,
        'page': page,
        'limit': limit,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );

    final data = response.data ?? <String, dynamic>{};
    final items = ((data['customers'] as List<dynamic>?) ??
            (data['items'] as List<dynamic>?) ??
            (data['data'] as List<dynamic>?) ??
            const [])
        .whereType<Map<String, dynamic>>()
        .map(Customer.fromJson)
        .toList();

    return CustomersListResult(
      items: items,
      total: (data['total'] as num?)?.toInt() ?? items.length,
      page: (data['page'] as num?)?.toInt() ?? page,
      limit: (data['limit'] as num?)?.toInt() ?? limit,
    );
  }

  @override
  Future<Customer> createCustomer(Customer customer) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.customers,
      data: customer.toCreatePayload(),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return Customer.fromJson(response.data ?? <String, dynamic>{});
  }

  @override
  Future<CustomerDetail> getCustomerDetail(int customerId) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.customer(customerId),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return CustomerDetail.fromJson(response.data ?? <String, dynamic>{});
  }

  @override
  Future<Customer> updateCustomer(Customer customer) async {
    final response = await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.customer(customer.id),
      data: customer.toUpdatePayload(),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return Customer.fromJson(response.data ?? <String, dynamic>{});
  }

  @override
  Future<void> deleteCustomer(int customerId, {bool cascadeTrailers = false}) async {
    final path = cascadeTrailers
        ? '${ApiEndpoints.customer(customerId)}?cascadeTrailers=true'
        : ApiEndpoints.customer(customerId);
    await _api.delete<Map<String, dynamic>>(
      path,
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  @override
  Future<String> syncWithQuickBooks() async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.customersSync,
      data: const {},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final data = res.data ?? const {};
    final imported = (data['imported'] as Map?) ?? const {};
    final exported = (data['exported'] as Map?) ?? const {};
    final pulled = imported['total'] ?? 0;
    final pushed = exported['exported'] ?? 0;
    final failed = exported['failed'] ?? 0;
    final base = 'Synced with QuickBooks — pulled $pulled, pushed $pushed';
    return failed == 0 ? base : '$base ($failed failed to push)';
  }
}
