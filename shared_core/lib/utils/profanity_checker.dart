import 'package:profanity_filter/profanity_filter.dart';

class ProfanityChecker {
  static final ProfanityFilter _filter = ProfanityFilter();

  static bool hasProfanity(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    return _filter.hasProfanity(text);
  }

  static String censor(String text) {
    if (text.isEmpty) return text;
    return _filter.censor(text);
  }
}
