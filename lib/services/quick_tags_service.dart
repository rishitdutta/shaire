import 'package:shared_preferences/shared_preferences.dart';

class QuickTagsService {
  static const String _tagsKey = 'quick_expense_tags';
  static const List<String> defaultTags = [
    '🍔 Food',
    '☕ Coffee',
    '🚕 Cab',
  ];

  static Future<List<String>> getTags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_tagsKey);
      if (list != null && list.isNotEmpty) {
        return list;
      }
      return List<String>.from(defaultTags);
    } catch (_) {
      return List<String>.from(defaultTags);
    }
  }

  static Future<void> saveTags(List<String> tags) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_tagsKey, tags);
    } catch (_) {}
  }

  static Future<List<String>> addTag(String tag) async {
    final tags = await getTags();
    final trimmed = tag.trim();
    if (trimmed.isNotEmpty && !tags.contains(trimmed)) {
      tags.add(trimmed);
      await saveTags(tags);
    }
    return tags;
  }

  static Future<List<String>> removeTag(String tag) async {
    final tags = await getTags();
    tags.remove(tag);
    if (tags.isEmpty) {
      tags.addAll(defaultTags);
    }
    await saveTags(tags);
    return tags;
  }

  static Future<List<String>> reorderTags(int oldIndex, int newIndex) async {
    final tags = await getTags();
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = tags.removeAt(oldIndex);
    tags.insert(newIndex, item);
    await saveTags(tags);
    return tags;
  }
}
