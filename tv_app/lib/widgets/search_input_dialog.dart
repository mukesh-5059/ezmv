import 'package:flutter/material.dart';
import 'tv_keyboard_dialog.dart';

class SearchInputDialog {
  static Future<String?> show({
    required BuildContext context,
    String initialQuery = '',
    required ValueChanged<String> onSearch,
  }) async {
    final result = await TvKeyboardDialog.show(
      context: context,
      title: 'Search Titles & People',
      initialValue: initialQuery,
      hintText: 'e.g. Inception, Marvel, Rajinikanth...',
      acceptLabel: 'Search',
      isUrl: false,
    );
    if (result != null) onSearch(result);
    return result;
  }
}
