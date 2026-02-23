import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

class NewsReaderSheet extends StatefulWidget {
  final String title;
  final String htmlContent;
  final String date;
  final List<String> imageUrls;
  final String? creatorProfileImage;
  final String? username;
  final bool? isVerified;
  final String? postUserId;


  const NewsReaderSheet({
    super.key,
    required this.title,
    required this.htmlContent,
    required this.date,
    required this.imageUrls,
    this.creatorProfileImage,
    this.username,
    this.isVerified,
    this.postUserId,
  });

  @override
  State<NewsReaderSheet> createState() => _NewsReaderSheetState();
}

class _NewsReaderSheetState extends State<NewsReaderSheet> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const Color _gold = Color(0xFFAE9159);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String formatDate(String date) {
    try {
      final parsedDate = DateTime.parse(date);
      return "${parsedDate.day}/${parsedDate.month}/${parsedDate.year}";
    } catch (e) {
      return date; // Return original string if parsing fails
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.93,
      minChildSize: 0.6,
      maxChildSize: 0.97,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    const Spacer(),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.grey.shade600,
                        size: 22,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // ── Scrollable content ───────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image carousel
                      if (widget.imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 260,
                          child: Stack(
                            children: [
                              PageView.builder(
                                controller: _pageController,
                                onPageChanged: (i) =>
                                    setState(() => _currentPage = i),
                                itemCount: widget.imageUrls.length,
                                itemBuilder: (context, index) {
                                  return Image.network(
                                    widget.imageUrls[index],
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey.shade100,
                                      child: Icon(
                                        Icons.broken_image_rounded,
                                        color: Colors.grey.shade400,
                                        size: 40,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              // Dot indicators
                              if (widget.imageUrls.length > 1)
                                Positioned(
                                  bottom: 12,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(
                                      widget.imageUrls.length,
                                      (i) => AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        width: _currentPage == i ? 20 : 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: _currentPage == i
                                              ? _gold
                                              : Colors.white.withOpacity(0.7),
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],

                      // Title + date
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                            letterSpacing: -0.5,
                            height: 1.25,
                          ),
                        ),
                      ),

                      // Show author and date if available
                      if (widget.username != null && widget.username!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                          child: Row(
                            children: [
                              Text(
                                "By ",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (widget.creatorProfileImage != null &&
                                  widget.creatorProfileImage!.isNotEmpty)
                                CircleAvatar(
                                  radius: 10,
                                  backgroundImage: NetworkImage(
                                    widget.creatorProfileImage!,
                                  ),
                                  backgroundColor: Colors.grey.shade200,
                                ),
                              if (widget.creatorProfileImage != null &&
                                  widget.creatorProfileImage!.isNotEmpty)
                                const SizedBox(width: 8),
                              Text(
                                widget.username!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (widget.isVerified == true)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF3AB4F2),
                                    size: 14,
                                  ),
                                ),
                            ],
                          ),
                        ),

                      if (widget.date.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                          child: Text(
                            formatDate(widget.date),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),


                      // Gold divider
                      Container(
                        margin: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_gold, _gold.withOpacity(0.0)],
                          ),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),

                      // HTML content
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
                        child: Html(
                          data: widget.htmlContent,
                          style: {
                            "body": Style(
                              margin: Margins.zero,
                              padding: HtmlPaddings.zero,
                              fontSize: FontSize(15),
                              lineHeight: const LineHeight(1.6),
                              color: Colors.grey.shade700,
                            ),
                            "p": Style(margin: Margins.only(bottom: 12)),
                            "h1, h2, h3, h4, h5, h6": Style(
                              margin: Margins.only(top: 16, bottom: 8),
                              fontWeight: FontWeight.bold,
                            ),
                            "ul, ol": Style(
                              margin: Margins.only(left: 16, bottom: 12),
                            ),
                            "li": Style(margin: Margins.only(bottom: 4)),
                            "a": Style(
                              color: const Color(0xFFAE9159),
                              textDecoration: TextDecoration.underline,
                            ),
                            "strong, b": Style(fontWeight: FontWeight.bold),
                            "em, i": Style(fontStyle: FontStyle.italic),
                          },
                          onLinkTap: (url, attributes, element) async {
                            if (url != null) {
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            }
                          },
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
