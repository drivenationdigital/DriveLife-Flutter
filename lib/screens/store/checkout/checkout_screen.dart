import 'package:drivelife/api/drivelife_api_service.dart';
import 'package:drivelife/providers/cart_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _address2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _postcodeController = TextEditingController();
  final _phoneController = TextEditingController();

  // State
  bool _isProcessing = false;
  bool _saveAddress = false;
  bool _orderSummaryExpanded = false;
  String _selectedCountry = 'United Kingdom';
  String _selectedShipping = 'standard';
  String _selectedPaymentMethod = 'card';

  final List<Map<String, dynamic>> _countries = [
    {'name': 'United Kingdom', 'code': 'GB'},
    {'name': 'United States', 'code': 'US'},
    {'name': 'Ireland', 'code': 'IE'},
    // Add more countries as needed
  ];

  final List<Map<String, dynamic>> _shippingOptions = [
    {'id': 'standard', 'name': 'Shipping: 5-10 days', 'price': 5.40},
    {'id': 'express', 'name': 'Express Shipping: 2-3 days', 'price': 12.99},
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _address2Controller.dispose();
    _cityController.dispose();
    _postcodeController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    final userProvider = context.read<UserProvider>();

    // Pre-fill form with user data
    if (userProvider.user != null) {
      _emailController.text = userProvider.user!.email ?? '';
      _firstNameController.text = userProvider.user!.firstName ?? '';
      _lastNameController.text = userProvider.user!.lastName ?? '';
      _phoneController.text = userProvider.user!.billingInfo?.phone ?? '';

      // Pre-fill address if available
      if (userProvider.user!.billingInfo != null) {
        final address = userProvider.user!.billingInfo!;
        _addressController.text = address.address1;
        _address2Controller.text = address.address2;
        _cityController.text = address.city;
        _postcodeController.text = address.postcode;
        _selectedCountry = address.country;
      }
    }
  }

  Future<void> _processPayment() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackbar('Please fill in all required fields', isError: true);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final cartProvider = context.read<CartProvider>();

      // Calculate total
      final subtotal = cartProvider.subtotal;
      final shipping =
          _shippingOptions.firstWhere(
                (option) => option['id'] == _selectedShipping,
              )['price']
              as double;
      final total = subtotal + shipping;

      if (_selectedPaymentMethod == 'card') {
        await _processStripePayment(total, cartProvider);
      } else if (_selectedPaymentMethod == 'klarna') {
        // TODO: Implement Klarna
        _showSnackbar('Klarna payment coming soon', isError: true);
      } else if (_selectedPaymentMethod == 'paypal') {
        // TODO: Implement PayPal
        _showSnackbar('PayPal payment coming soon', isError: true);
      }
    } catch (e) {
      _showSnackbar('Payment failed: $e', isError: true);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _processStripePayment(
    double total,
    CartProvider cartProvider,
  ) async {
    // try {
    //   // Step 1: Create payment intent on backend
    //   final paymentIntentData = await DriveLifeApiService.createPaymentIntent(
    //     amount: (total * 100).toInt(), // Convert to cents
    //     currency: 'gbp',
    //     customerEmail: _emailController.text,
    //     shippingAddress: {
    //       'name': '${_firstNameController.text} ${_lastNameController.text}',
    //       'address1': _addressController.text,
    //       'address2': _address2Controller.text,
    //       'city': _cityController.text,
    //       'postcode': _postcodeController.text,
    //       'country': _selectedCountry,
    //       'phone': _phoneController.text,
    //     },
    //     items: cartProvider.cart
    //         .map(
    //           (item) => {
    //             'name': item.name,
    //             'quantity': item.quantity,
    //             'price': item.price,
    //           },
    //         )
    //         .toList(),
    //   );

    //   // Step 2: Initialize payment sheet
    //   await Stripe.instance.initPaymentSheet(
    //     paymentSheetParameters: SetupPaymentSheetParameters(
    //       paymentIntentClientSecret: paymentIntentData['clientSecret'],
    //       merchantDisplayName: 'DriveLife',
    //       customerEphemeralKeySecret: paymentIntentData['ephemeralKey'],
    //       customerId: paymentIntentData['customer'],
    //       style: ThemeMode.light,
    //       appearance: const PaymentSheetAppearance(
    //         colors: PaymentSheetAppearanceColors(primary: Color(0xFFAE9159)),
    //       ),
    //     ),
    //   );

    //   // Step 3: Present payment sheet
    //   await Stripe.instance.presentPaymentSheet();

    //   // Step 4: Payment successful
    //   await _createOrder(paymentIntentData['paymentIntentId'], cartProvider);

    //   // Clear cart
    //   cartProvider.clearCart();

    //   // Navigate to success page
    //   if (mounted) {
    //     Navigator.of(context).pushReplacementNamed(
    //       '/order-success',
    //       arguments: paymentIntentData['paymentIntentId'],
    //     );
    //   }
    // } on StripeException catch (e) {
    //   if (e.error.code == FailureCode.Canceled) {
    //     _showSnackbar('Payment cancelled', isError: true);
    //   } else {
    //     _showSnackbar('Payment failed: ${e.error.message}', isError: true);
    //   }
    // }
  }

  Future<void> _createOrder(
    String paymentIntentId,
    CartProvider cartProvider,
  ) async {
    // // Create order in your backend
    // await DriveLifeApiService.createOrder(
    //   paymentIntentId: paymentIntentId,
    //   customerEmail: _emailController.text,
    //   shippingAddress: {
    //     'firstName': _firstNameController.text,
    //     'lastName': _lastNameController.text,
    //     'address1': _addressController.text,
    //     'address2': _address2Controller.text,
    //     'city': _cityController.text,
    //     'postcode': _postcodeController.text,
    //     'country': _selectedCountry,
    //     'phone': _phoneController.text,
    //   },
    //   items: cartProvider.cart
    //       .map(
    //         (item) => {
    //           'productId': item.productId,
    //           'name': item.name,
    //           'quantity': item.quantity,
    //           'price': item.price,
    //           'image': item.image,
    //           'selectedColorHex': item.selectedColorHex,
    //           'selectedColorName': item.selectedColorName,
    //           'selectedSize': item.selectedSize,
    //           'supplierSku': item.supplierSku,
    //         },
    //       )
    //       .toList(),
    //   shippingMethod: _selectedShipping,
    // );
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFFAE9159),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Checkout',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order Summary (Collapsible)
                _buildOrderSummary(),

                const SizedBox(height: 24),

                // Express Checkout
                _buildExpressCheckout(),

                const SizedBox(height: 24),

                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Or continue below',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Contact Information
                _buildContactInformation(),

                const SizedBox(height: 24),

                // Shipping Address
                _buildShippingAddress(),

                const SizedBox(height: 24),

                // Shipping Options
                _buildShippingOptions(),

                const SizedBox(height: 24),

                // Payment Options
                _buildPaymentOptions(),

                const SizedBox(height: 24),

                // Terms
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'By proceeding with your purchase you agree to our Terms and Conditions and Privacy Policy.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),

          // Bottom bar with Place Order button
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),

          // Loading overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFFAE9159)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Consumer<CartProvider>(
      builder: (context, cartProvider, child) {
        final shipping =
            _shippingOptions.firstWhere(
                  (option) => option['id'] == _selectedShipping,
                )['price']
                as double;
        final total = cartProvider.subtotal + shipping;

        return Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              ListTile(
                title: Text(
                  'Order Summary',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '£${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _orderSummaryExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ],
                ),
                onTap: () => setState(
                  () => _orderSummaryExpanded = !_orderSummaryExpanded,
                ),
              ),
              if (_orderSummaryExpanded) ...[
                Divider(height: 1, color: Colors.grey.shade200),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  itemCount: cartProvider.cart.length,
                  itemBuilder: (context, index) {
                    final item = cartProvider.cart[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          // Product image
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    item.image,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: CircleAvatar(
                                    radius: 12,
                                    backgroundColor: Colors.grey.shade600,
                                    child: Text(
                                      '${item.quantity}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Product details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.selectedSize != null ||
                                    item.selectedColorName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      [
                                        if (item.selectedSize != null)
                                          'Size: ${item.selectedSize}',
                                        if (item.selectedColorName != null)
                                          'Color: ${item.selectedColorName}',
                                      ].join(' • '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Price
                          Text(
                            '£${(item.price * item.quantity).toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Divider(color: Colors.grey.shade200),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Sub Total:'),
                          Text('£${cartProvider.subtotal.toStringAsFixed(2)}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Shipping:'),
                          Text('£${shipping.toStringAsFixed(2)}'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildExpressCheckout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Express checkout',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Apple Pay button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => _processApplePay(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.apple, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'Pay',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Google Pay button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => _processGooglePay(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'G',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Pay',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processApplePay() async {
    // TODO: Implement Apple Pay
    _showSnackbar('Apple Pay coming soon');
  }

  Future<void> _processGooglePay() async {
    // TODO: Implement Google Pay
    _showSnackbar('Google Pay coming soon');
  }

  Widget _buildContactInformation() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Contact Information',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  // TODO: Navigate to login
                },
                child: const Text('Login'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Email address',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Email is required';
              }
              if (!value.contains('@')) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          Text(
            'You are currently checking out as guest.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildShippingAddress() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shipping Address',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Country dropdown
            // DropdownButtonFormField<String>(
            //   value: _selectedCountry,
            //   decoration: InputDecoration(
            //     border: OutlineInputBorder(
            //       borderRadius: BorderRadius.circular(8),
            //       borderSide: BorderSide(color: Colors.grey.shade300),
            //     ),
            //     enabledBorder: OutlineInputBorder(
            //       borderRadius: BorderRadius.circular(8),
            //       borderSide: BorderSide(color: Colors.grey.shade300),
            //     ),
            //     contentPadding: const EdgeInsets.symmetric(
            //       horizontal: 16,
            //       vertical: 14,
            //     ),
            //   ),
            //   items: _countries
            //       .map(
            //         (country) => DropdownMenuItem<String>(
            //           value: country['name'],
            //           child: Text(country['name']),
            //         ),
            //       )
            //       .toList(),
            //   onChanged: (value) {
            //     setState(() => _selectedCountry = value!);
            //   },
            // ),
            const SizedBox(height: 12),

            // First name
            TextFormField(
              controller: _firstNameController,
              decoration: InputDecoration(
                hintText: 'First Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Last name
            TextFormField(
              controller: _lastNameController,
              decoration: InputDecoration(
                hintText: 'Last Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Address
            TextFormField(
              controller: _addressController,
              decoration: InputDecoration(
                hintText: 'Address',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Address 2 (optional)
            TextFormField(
              controller: _address2Controller,
              decoration: InputDecoration(
                hintText: 'Add flat, suite, etc. (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // City
            TextFormField(
              controller: _cityController,
              decoration: InputDecoration(
                hintText: 'City',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Postcode
            TextFormField(
              controller: _postcodeController,
              decoration: InputDecoration(
                hintText: 'Postcode',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Phone
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: 'Phone (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Save address checkbox
            CheckboxListTile(
              value: _saveAddress,
              onChanged: (value) {
                setState(() => _saveAddress = value ?? false);
              },
              title: const Text(
                'Use same address for billing',
                style: TextStyle(fontSize: 14),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFFAE9159),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShippingOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shipping Options',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          ..._shippingOptions.map((option) {
            final isSelected = _selectedShipping == option['id'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedShipping = option['id']),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFAE9159)
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Radio<String>(
                        value: option['id'],
                        groupValue: _selectedShipping,
                        onChanged: (value) {
                          setState(() => _selectedShipping = value!);
                        },
                        activeColor: const Color(0xFFAE9159),
                      ),
                      Expanded(
                        child: Text(
                          option['name'],
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        '£${(option['price'] as double).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildPaymentOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Options',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Card payment
          _buildPaymentOption(
            id: 'card',
            title: 'Card',
            icon: Icons.credit_card,
          ),

          const SizedBox(height: 8),

          // Klarna
          _buildPaymentOption(
            id: 'klarna',
            title: 'Klarna',
            subtitle: 'Buy now, pay later',
          ),

          const SizedBox(height: 8),

          // PayPal
          _buildPaymentOption(id: 'paypal', title: 'PayPal'),
        ],
      ),
    );
  }

  Widget _buildPaymentOption({
    required String id,
    required String title,
    String? subtitle,
    IconData? icon,
  }) {
    final isSelected = _selectedPaymentMethod == id;
    return InkWell(
      onTap: () => setState(() => _selectedPaymentMethod = id),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? const Color(0xFFAE9159) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: id,
              groupValue: _selectedPaymentMethod,
              onChanged: (value) {
                setState(() => _selectedPaymentMethod = value!);
              },
              activeColor: const Color(0xFFAE9159),
            ),
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Consumer<CartProvider>(
      builder: (context, cartProvider, child) {
        final shipping =
            _shippingOptions.firstWhere(
                  (option) => option['id'] == _selectedShipping,
                )['price']
                as double;
        final total = cartProvider.subtotal + shipping;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Place Order • £${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
