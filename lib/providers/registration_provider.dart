import 'package:flutter/foundation.dart';

class RegistrationProvider extends ChangeNotifier {
  // Step 1 data
  String _firstName = '';
  String _lastName = '';
  String _email = '';
  String _password = '';
  String _confirmPassword = '';
  String _country = '';
  bool _agreeTerms = false;
  bool _agreePrivacy = false;

  // API response data
  int? _userId;
  String _suggestedUsername = '';

  // Step 2 data
  String _username = '';

  // Step 3 data (interests - multiple selection)
  List<int> _interestIds = []; // Changed from List<String> to List<int>

  // Step 4 data (profile type - single selection)
  int? _profileTypeId;

  // Step 5 data (images)
  String? _profileImagePath;
  String? _coverImagePath;

  // Current step
  int _currentStep = 1;

  // Loading state
  bool _isLoading = false;

  // Getters
  String get firstName => _firstName;
  String get lastName => _lastName;
  String get email => _email;
  String get password => _password;
  String get confirmPassword => _confirmPassword;
  String get country => _country;
  bool get agreeTerms => _agreeTerms;
  bool get agreePrivacy => _agreePrivacy;
  int get currentStep => _currentStep;
  bool get isLoading => _isLoading;

  // API response
  int? get userId => _userId;
  String get suggestedUsername => _suggestedUsername;

  // Step 2
  String get username => _username;

  // Step 3
  List<int> get interestIds => _interestIds;

  // Step 4
  int? get profileTypeId => _profileTypeId;

  // Step 5
  String? get profileImagePath => _profileImagePath;
  String? get coverImagePath => _coverImagePath;

  // Setters with notification
  void setFirstName(String value) {
    _firstName = value;
    notifyListeners();
  }

  void setLastName(String value) {
    _lastName = value;
    notifyListeners();
  }

  void setEmail(String value) {
    _email = value;
    notifyListeners();
  }

  void setPassword(String value) {
    _password = value;
    notifyListeners();
  }

  void setConfirmPassword(String value) {
    _confirmPassword = value;
    notifyListeners();
  }

  void setCountry(String value) {
    _country = value;
    notifyListeners();
  }

  void setAgreeTerms(bool value) {
    _agreeTerms = value;
    notifyListeners();
  }

  void setAgreePrivacy(bool value) {
    _agreePrivacy = value;
    notifyListeners();
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // API response setters
  void setUserId(int? id) {
    _userId = id;
    notifyListeners();
  }

  void setSuggestedUsername(String username) {
    _suggestedUsername = username;
    // Also set as the default username for step 2
    _username = username;
    notifyListeners();
  }

  // Step 2 setters
  void setUsername(String value) {
    _username = value;
    notifyListeners();
  }

  // Step 3 setters
  void toggleInterestId(int interestId) {
    if (_interestIds.contains(interestId)) {
      _interestIds.remove(interestId);
    } else {
      _interestIds.add(interestId);
    }
    notifyListeners();
  }

  void setInterestIds(List<int> ids) {
    _interestIds = ids;
    notifyListeners();
  }

  // Deprecated: kept for backwards compatibility
  void toggleInterest(String interest) {
    // This method is deprecated, use toggleInterestId instead
    notifyListeners();
  }

  void setInterests(List<String> interests) {
    // This method is deprecated, use setInterestIds instead
    notifyListeners();
  }

  // Step 4 setters
  void setProfileTypeId(int? value) {
    _profileTypeId = value;
    notifyListeners();
  }

  // Deprecated: kept for backwards compatibility
  void setProfileType(String value) {
    notifyListeners();
  }

  // Step 5 setters
  void setProfileImagePath(String? path) {
    _profileImagePath = path;
    notifyListeners();
  }

  void setCoverImagePath(String? path) {
    _coverImagePath = path;
    notifyListeners();
  }

  void nextStep() {
    _currentStep++;
    notifyListeners();
  }

  void previousStep() {
    if (_currentStep > 1) {
      _currentStep--;
      notifyListeners();
    }
  }

  void setStep(int step) {
    _currentStep = step;
    notifyListeners();
  }

  // Validation
  bool validateStep1() {
    return _firstName.isNotEmpty &&
        _lastName.isNotEmpty &&
        _email.isNotEmpty &&
        _password.isNotEmpty &&
        _confirmPassword.isNotEmpty &&
        _password == _confirmPassword &&
        _country.isNotEmpty &&
        _agreeTerms &&
        _agreePrivacy;
  }

  bool validateStep2() {
    return _username.isNotEmpty && _username.length >= 3;
  }

  bool validateStep3() {
    return _interestIds.isNotEmpty;
  }

  bool validateStep4() {
    return _profileTypeId != null;
  }

  bool validateStep5() {
    // Step 5 is optional (can skip)
    return true;
  }

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  String? validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _password) {
      return 'Passwords do not match';
    }
    return null;
  }

  String? validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return 'Username is required';
    }
    if (value.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      return 'Username can only contain letters, numbers, and underscores';
    }
    return null;
  }

  // Get all registration data as a map
  Map<String, dynamic> getRegistrationData() {
    return {
      'firstName': _firstName,
      'lastName': _lastName,
      'email': _email,
      'password': _password,
      'country': _country,
      'agreeTerms': _agreeTerms,
      'agreePrivacy': _agreePrivacy,
      'username': _username,
      'interestIds': _interestIds,
      'profileTypeId': _profileTypeId,
      'profileImagePath': _profileImagePath,
      'coverImagePath': _coverImagePath,
    };
  }

  // Clear all data
  void reset() {
    _firstName = '';
    _lastName = '';
    _email = '';
    _password = '';
    _confirmPassword = '';
    _country = '';
    _agreeTerms = false;
    _agreePrivacy = false;
    _userId = null;
    _suggestedUsername = '';
    _username = '';
    _interestIds = [];
    _profileTypeId = null;
    _profileImagePath = null;
    _coverImagePath = null;
    _currentStep = 1;
    _isLoading = false;
    notifyListeners();
  }
}
