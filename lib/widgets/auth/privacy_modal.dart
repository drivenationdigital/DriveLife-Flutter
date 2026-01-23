import 'package:flutter/material.dart';

class PrivacyModal extends StatelessWidget {
  const PrivacyModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Privacy Policy',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This Privacy Policy describes Our policies and procedures on the collection, use and disclosure of Your information when You use the Service and tells You about Your privacy rights and how the law protects You.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'We use Your Personal data to provide and improve the Service. By using the Service, You agree to the collection and use of information in accordance with this Privacy Policy.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'INTERPRETATION AND DEFINITIONS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'The words of which the initial letter is capitalized have meanings defined under the following conditions. The following definitions shall have the same meaning regardless of whether they appear in singular or in plural.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'DEFINITIONS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '• Account: means a unique account created for You to access our Service or parts of our Service.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Company: (referred to as either "CarEvents.com", "the Company", "We", "Us" or "Our" in this Agreement) refers to Car Events Ltd, The Motorist Lennerton Lane, Sherburn In Elmet, Leeds, England, LS25 6JE.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Personal Data: is any information that relates to an identified or identifiable individual.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Service: refers to the Website.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'TYPES OF DATA COLLECTED',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Personal Data',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'While using Our Service, We may ask You to provide Us with certain personally identifiable information that can be used to contact or identify You. Personally identifiable information may include, but is not limited to:',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Email address\n• First name and last name\n• Address, State, Province, ZIP/Postal code, City\n• Usage Data',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'USE OF YOUR PERSONAL DATA',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'The Company may use Personal Data for the following purposes:',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• To provide and maintain our Service\n• To manage Your Account\n• For the performance of a contract\n• To contact You\n• To manage Your requests',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'SECURITY OF YOUR PERSONAL DATA',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'The security of Your Personal Data is important to Us, but remember that no method of transmission over the Internet, or method of electronic storage is 100% secure. While We strive to use commercially acceptable means to protect Your Personal Data, We cannot guarantee its absolute security.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'CHILDREN\'S PRIVACY',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Our Service does not address anyone under the age of 13. We do not knowingly collect personally identifiable information from anyone under the age of 13.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'CONTACT US',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'If you have any questions about this Privacy Policy, You can contact us by email at: info@CarEvents.com',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'For the complete Privacy Policy, please visit our website.',
                        style: TextStyle(
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
