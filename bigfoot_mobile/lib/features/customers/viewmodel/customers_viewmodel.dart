import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/customer.dart';
import '../../../domain/repositories/customer_repository.dart';

// Re-export for screens
export '../../../domain/repositories/customer_repository.dart' show CustomersListResult;

class CustomersViewModel extends Cubit<int> {
  final CustomerRepository _repository;

  CustomersViewModel({required CustomerRepository repository})
      : _repository = repository,
        super(0);

  Future<CustomersListResult> getCustomers({
    String? query,
    String? customerType,
    bool excludeStockLocations = false,
    int page = 1,
    int limit = 20,
  }) => _repository.getCustomers(
    query: query,
    customerType: customerType,
    excludeStockLocations: excludeStockLocations,
    page: page,
    limit: limit,
  );

  Future<Customer> createCustomer(Customer customer) =>
      _repository.createCustomer(customer);

  Future<CustomerDetail> getCustomerDetail(int customerId) =>
      _repository.getCustomerDetail(customerId);

  Future<Customer> updateCustomer(Customer customer) =>
      _repository.updateCustomer(customer);

  Future<void> deleteCustomer(int customerId, {bool cascadeTrailers = false}) =>
      _repository.deleteCustomer(customerId, cascadeTrailers: cascadeTrailers);
}
