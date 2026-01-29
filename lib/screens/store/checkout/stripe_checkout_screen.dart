import 'dart:io' show Platform;
import 'package:drivelife/api/stripe_api_service.dart';
import 'package:drivelife/providers/cart_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/widgets/shared_header_actions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class HybridCheckoutScreen extends StatefulWidget {
  const HybridCheckoutScreen({super.key});

  @override
  State<HybridCheckoutScreen> createState() => _HybridCheckoutScreenState();
}

class _HybridCheckoutScreenState extends State<HybridCheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isProcessing = false;

  // Form controllers
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _address2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _postcodeController = TextEditingController();
  String _selectedCountry = 'GB';

  String _selectedShipping = 'standard';
  final List<Map<String, dynamic>> _shippingOptions = [
    {'id': 'standard', 'name': 'Standard (5-10 days)', 'price': 5.40},
    {'id': 'express', 'name': 'Express (2-3 days)', 'price': 12.99},
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
    _phoneController.dispose();
    _addressController.dispose();
    _address2Controller.dispose();
    _cityController.dispose();
    _postcodeController.dispose();
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
        _selectedCountry = address.country.isNotEmpty ? address.country : 'GB';
      }
    }
  }

  Future<void> _proceedToPayment() async {
    // Validate form first
    if (!_formKey.currentState!.validate()) {
      _showSnackbar('Please fill in all required fields', isError: true);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final cartProvider = context.read<CartProvider>();
      final userProvider = context.read<UserProvider>();
      final user = userProvider.user;

      if (user == null) {
        _showSnackbar('Please log in to continue', isError: true);
        setState(() => _isProcessing = false);
        return;
      }

      // Calculate total
      final subtotal = cartProvider.subtotal;
      final shipping =
          _shippingOptions.firstWhere(
                (option) => option['id'] == _selectedShipping,
              )['price']
              as double;
      final total = subtotal + shipping;

      // Create Payment Intent
      final paymentIntentData = await StripeApiService.createPaymentIntentV2(
        userId: user.id,
        amount: (total * 100).toInt(),
        currency: 'gbp',
        customerEmail: _emailController.text,
        customerName:
            '${_firstNameController.text} ${_lastNameController.text}',
        shippingMethod: _selectedShipping,
        items: cartProvider.cart
            .map(
              (item) => {
                'product_id': item.productId,
                'name': item.name,
                'quantity': item.quantity,
                'price': item.price,
                'image': item.image,
                'selected_color': item.selectedColorName,
                'selected_size': item.selectedSize,
              },
            )
            .toList(),
      );

      // Initialize Payment Sheet with billing details
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          // Merchant info
          merchantDisplayName: 'DriveLife',

          // Payment intent
          paymentIntentClientSecret: paymentIntentData['clientSecret'],

          // Customer info (enables saved cards)
          customerEphemeralKeySecret: paymentIntentData['ephemeralKey'],
          customerId: paymentIntentData['customer'],

          // ✅ Pre-fill billing details from your form
          billingDetailsCollectionConfiguration:
              const BillingDetailsCollectionConfiguration(
                name: CollectionMode.never, // We already have it
                email: CollectionMode.never, // We already have it
                phone: CollectionMode.never, // We already have it
                address: AddressCollectionMode.never, // We already have it
              ),

          // ✅ Pass billing details we collected
          billingDetails: BillingDetails(
            email: _emailController.text,
            name: '${_firstNameController.text} ${_lastNameController.text}',
            phone: _phoneController.text,
            address: Address(
              line1: _addressController.text,
              line2: _address2Controller.text.isNotEmpty
                  ? _address2Controller.text
                  : null,
              city: _cityController.text,
              postalCode: _postcodeController.text,
              country: _selectedCountry,
              state: null,
            ),
          ),

          // Apple Pay (iOS only)
          // applePay: Platform.isIOS
          //     ? const PaymentSheetApplePay(merchantCountryCode: 'GB')
          //     : null,

          // Google Pay (Android only)
          googlePay: Platform.isAndroid
              ? const PaymentSheetGooglePay(
                  merchantCountryCode: 'GB',
                  currencyCode: 'GBP',
                  testEnv: true, // Set to false in production
                )
              : null,

          // Appearance
          style: ThemeMode.light,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(primary: Color(0xFFAE9159)),
            shapes: PaymentSheetShape(borderRadius: 12, borderWidth: 1),
          ),

          // Enable all payment features
          allowsDelayedPaymentMethods: true,
        ),
      );

      // Present the payment sheet
      await Stripe.instance.presentPaymentSheet();

      // Payment successful! Create order
      await _handlePaymentSuccess(
        paymentIntentData['paymentIntentId'],
        cartProvider,
        user.id,
      );
    } on StripeException catch (e) {
      setState(() => _isProcessing = false);

      if (e.error.code == FailureCode.Canceled) {
        // User cancelled - stay on screen
        print('Payment cancelled by user');
      } else {
        _showSnackbar(
          'Payment failed: ${e.error.localizedMessage ?? e.error.message}',
          isError: true,
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      _showSnackbar('Error: $e', isError: true);
    }
  }

  Future<void> _handlePaymentSuccess(
    String paymentIntentId,
    CartProvider cartProvider,
    int userId,
  ) async {
    try {
      final orderData = await StripeApiService.createOrderV2(
        userId: userId,
        paymentIntentId: paymentIntentId,
        shippingMethod: _selectedShipping,
      );

      print('Order created: $orderData');
      cartProvider.clearCart();

      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacementNamed('/order-success', arguments: orderData);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      _showSnackbar('Order creation failed: $e', isError: true);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFFAE9159),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 5 : 2),
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
        centerTitle: true,
        leadingWidth: 96,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.search);
            },
          ),
          // ✅ Using the actionIcons helper for multiple icons at once
          ...SharedHeaderIcons.actionIcons(
            iconColor: Colors.black,
            showQr: false, // Already shown in leading
            showNotifications: true,
          ),
        ],
      ),
      body: Consumer<CartProvider>(
        builder: (context, cartProvider, child) {
          final subtotal = cartProvider.subtotal;
          final shipping =
              _shippingOptions.firstWhere(
                    (option) => option['id'] == _selectedShipping,
                  )['price']
                  as double;
          final total = subtotal + shipping;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Checkout',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Order Summary',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '£${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Form
                Form(
                  key: _formKey,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Contact Information
                        const Text(
                          'Contact Information',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email address',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Email is required';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 24),

                        // Shipping Address
                        const Text(
                          'Shipping Address',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _firstNameController,
                                decoration: InputDecoration(
                                  labelText: 'First Name',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _lastNameController,
                                decoration: InputDecoration(
                                  labelText: 'Last Name',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _addressController,
                          decoration: InputDecoration(
                            labelText: 'Address',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Address is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _address2Controller,
                          decoration: InputDecoration(
                            labelText: 'Apt, suite, etc. (optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _cityController,
                          decoration: InputDecoration(
                            labelText: 'City',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'City is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedCountry,
                                decoration: InputDecoration(
                                  labelText: 'Country',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'GB',
                                    child: Text('United Kingdom'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'US',
                                    child: Text('United States'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'CA',
                                    child: Text('Canada'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'AU',
                                    child: Text('Australia'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() => _selectedCountry = value!);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _postcodeController,
                                decoration: InputDecoration(
                                  labelText: 'Postcode',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Phone (optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Shipping Options
                        const Text(
                          'Shipping Options',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._shippingOptions.map((option) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _selectedShipping == option['id']
                                    ? const Color(0xFFAE9159)
                                    : Colors.grey.shade300,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: RadioListTile<String>(
                              value: option['id'],
                              groupValue: _selectedShipping,
                              onChanged: (value) {
                                setState(() => _selectedShipping = value!);
                              },
                              title: Text(
                                option['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '£${option['price'].toStringAsFixed(2)}',
                              ),
                              activeColor: const Color(0xFFAE9159),
                            ),
                          );
                        }),

                        const SizedBox(height: 24),

                        // Order Summary
                        const Text(
                          'Order Summary',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Cart Items
                        ...cartProvider.cart.map((item) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 60,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: item.image.isNotEmpty
                                        ? Image.network(
                                            item.image,
                                            fit: BoxFit.cover,
                                          )
                                        : const Icon(
                                            Icons.image,
                                            color: Colors.grey,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                      ),
                                      if (item.selectedColorName!.isNotEmpty ||
                                          item.selectedSize!.isNotEmpty)
                                        Text(
                                          [
                                            if (item
                                                .selectedColorName!
                                                .isNotEmpty)
                                              item.selectedColorName,
                                            if (item.selectedSize!.isNotEmpty)
                                              item.selectedSize,
                                          ].join(' · '),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Qty: ${item.quantity}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '£${(item.price * item.quantity).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 16),
                        Divider(color: Colors.grey.shade300),
                        const SizedBox(height: 16),

                        // Pricing breakdown
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Sub Total',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            Text('£${subtotal.toStringAsFixed(2)}'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Shipping',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            Text('£${shipping.toStringAsFixed(2)}'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Divider(color: Colors.grey.shade300, thickness: 2),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '£${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Place Order Button - Opens Payment Sheet
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isProcessing ? null : _proceedToPayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: _isProcessing
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Place Order',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
