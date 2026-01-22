import 'package:flutter/material.dart';

class FilterBottomSheet extends StatefulWidget {
  final String title;
  final List<FilterOption> options;
  final List<String> selectedValues;
  final bool multiSelect;
  final Function(List<String>) onApply;
  final Widget? customWidget; // NEW: For custom date/location UI
  final Function(String)?
  onCustomSelected; // NEW: Callback when custom is selected

  const FilterBottomSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selectedValues,
    this.multiSelect = true,
    required this.onApply,
    this.customWidget, // NEW
    this.onCustomSelected, // NEW
  });

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class FilterOption {
  final String label;
  final String value;

  FilterOption({required this.label, required this.value});
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late List<String> _selectedValues;

  @override
  void initState() {
    super.initState();
    _selectedValues = List.from(widget.selectedValues);
  }

  void _toggleSelection(String value) {
    setState(() {
      if (widget.multiSelect) {
        if (_selectedValues.contains(value)) {
          _selectedValues.remove(value);
        } else {
          _selectedValues.add(value);
        }
      } else {
        _selectedValues = [value];
        // NEW: Notify parent when custom is selected
        if (value == 'custom' && widget.onCustomSelected != null) {
          widget.onCustomSelected!(value);
        }
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedValues.length == widget.options.length) {
        _selectedValues.clear();
      } else {
        _selectedValues = widget.options.map((o) => o.value).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAllSelected = _selectedValues.length == widget.options.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85, // NEW: Max height
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Changed from MainAxisSize to min
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Options list - Wrapped in Flexible instead of Expanded
          Flexible(
            child: SingleChildScrollView(
              // NEW: Wrap ListView in SingleChildScrollView
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // "All" option (for multi-select)
                  if (widget.multiSelect)
                    _buildOptionTile(
                      label: 'All',
                      isSelected: isAllSelected,
                      onTap: _selectAll,
                      showCheckmark: true,
                    ),

                  // Individual options
                  ...widget.options.map((option) {
                    final isSelected = _selectedValues.contains(option.value);
                    return _buildOptionTile(
                      label: option.label,
                      isSelected: isSelected,
                      onTap: () => _toggleSelection(option.value),
                      showCheckmark: widget.multiSelect,
                    );
                  }),

                  // Show custom widget if "custom" is selected
                  if (_selectedValues.contains('custom') &&
                      widget.customWidget != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: widget.customWidget!,
                    ),
                ],
              ),
            ),
          ),

          // Apply button
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onApply(_selectedValues);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB8935E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'APPLY FILTERS',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool showCheckmark,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(
          children: [
            if (showCheckmark) ...[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFB8935E)
                        : Colors.grey.shade400,
                    width: 2,
                  ),
                  color: isSelected
                      ? const Color(0xFFB8935E)
                      : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                label.replaceAll('&amp;', '&'),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (!showCheckmark && isSelected)
              const Icon(Icons.check, color: Color(0xFFB8935E), size: 24),
          ],
        ),
      ),
    );
  }
}
