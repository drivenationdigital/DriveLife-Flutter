import 'package:flutter/material.dart';

class TermsModal extends StatelessWidget {
  const TermsModal({Key? key}) : super(key: key);

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
                      'Terms & Conditions',
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
                        'INTRODUCTION',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '1.1 Car Events Ltd. ("CarEvents.com", "we", "us", "our") is a company registered in England and Wales under company number 12698619, with registered offices at The Motorist Lennerton Lane, Sherburn In Elmet, Leeds, England, LS25 6JE.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '1.2 We operate an online and mobile App service where you can search for and purchase car show and related event tickets. No tickets are sold by us, we simply facilitate the sale process via a direct link to the show organiser\'s Stripe and/or Paypal accounts.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '1.3 This "Purchase Policy" sets out the terms and conditions applicable to purchases of Tickets via any of the CarEvents.com platforms. If you are making a purchase online, this Purchase Policy also incorporates our website Terms of Use.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'YOUR ACCOUNT AND REGISTRATION',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '2.1 In order to set up a CarEvents.com account to purchase or sell Tickets you must:',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '(a) be at least 18 years old (or the age of legal capacity in the country of purchase) and able to enter into legally binding contracts; and',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '(b) follow the instructions to set up a password-protected account providing your correct full name and email address (all your details must be kept up to date at all times).',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'LEGALLY BINDING CONTRACT',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '3.1 In order to make a purchase from us or any of our event partners, you must be at least 18 years old (or the age of legal capacity in the country of purchase) and able to enter into legally binding contracts.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '3.2 Any purchase from us or our event partners forms a legally binding contract that is subject to this Purchase Policy and any special terms and conditions.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'REFUNDS AND CANCELLATIONS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'We can\'t offer any exchanges or refunds if the event is going ahead on the date originally planned. If the date of an event is changed, your tickets will be transferred to the new date. If the date does change, you may request a refund by emailing the event organiser directly (within a minimum of 14 days before the event takes place). Refunds are not guaranteed and are at the event organiser\'s discretion.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'For the complete Terms & Conditions, please visit our website or contact us at info@CarEvents.com',
                        style: TextStyle(
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Publication Date: 16 January 2024',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
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
