import '../../data/models/customer.dart';

class CustomersListResult {
  final List<Customer> items;
  final int total;
  final int page;
  final int limit;

  const CustomersListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });
}

/// Abstract contract for customer operations.
abstract class CustomerRepository {
  Future<CustomersListResult> getCustomers({
    String? query,
    String? customerType,
    bool excludeStockLocations,
    int page,
    int limit,
  });

  Future<Customer> createCustomer(Customer customer);

  Future<CustomerDetail> getCustomerDetail(int customerId);

  Future<Customer> updateCustomer(Customer customer);

  /// Delete a customer. If [cascadeTrailers] is true, also delete every
  /// trailer that references this customer (and their full history).
  /// If false and trailers exist, the backend returns a 400.
  Future<void> deleteCustomer(int customerId, {bool cascadeTrailers = false});
}
