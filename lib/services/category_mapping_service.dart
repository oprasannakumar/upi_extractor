import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/category_mapping.dart';

class CategoryMappingService {
  static const String _storageKey = 'saved_category_mappings_v1';

  /// Default initial category mappings with rich English & Telugu terminology
  static final List<CategoryMapping> defaultCategoryMappings = [
    CategoryMapping(
      category: 'Bills & Utilities',
      keywords: [
        'recharge',
        'prepaid',
        'postpaid',
        'airtel',
        'jio',
        'vi ',
        'bsnl',
        'electricity',
        'water',
        'gas',
        'cylinder',
        'broadband',
        'wifi',
        'dth',
        'mobile',
        'bill',
        'tneb',
        'bescom',
        'apspdcl',
        'tsspdcl',
      ],
    ),
    CategoryMapping(
      category: 'Vegetables',
      keywords: [
        'kothimera',
        'coriander',
        'carrot',
        'beetroot',
        'chamadumpa',
        'keera',
        'cucumber',
        'beerak',
        'bendi',
        'bhindi',
        'okra',
        'capcicum',
        'capsicum',
        'dosakai',
        'dosakaya',
        'kandha',
        'kanda',
        'tomato',
        'tamata',
        'onion',
        'ullipaya',
        'potato',
        'aloo',
        'brinjal',
        'vankaya',
        'palak',
        'methi',
        'ginger',
        'garlic',
        'allam',
        'vellulli',
        'pudina',
        'mirchi',
        'chilli',
        'cabbage',
        'cauliflower',
        'vegetable',
        'sabzi',
        'rythu bazar',
      ],
    ),
    CategoryMapping(
      category: 'Fruits',
      keywords: [
        'lemon',
        'amla',
        'usiri',
        'apple',
        'banana',
        'ariti',
        'mango',
        'mamidi',
        'orange',
        'papaya',
        'bopayi',
        'grapes',
        'draksha',
        'guava',
        'jama',
        'sapota',
        'fruit',
        'watermelon',
        'pomegranate',
        'danimma',
      ],
    ),
    CategoryMapping(
      category: 'Dairy',
      keywords: [
        'milk',
        'paalu',
        'curd',
        'perugu',
        'paneer',
        'butter',
        'venna',
        'ghee',
        'neyyi',
        'cheese',
        'dairy',
        'amul',
        'heritage',
        'vijaya',
        'ganesh milk',
        'nandini',
        'sangam',
      ],
    ),
    CategoryMapping(
      category: 'Food & Dining',
      keywords: [
        'swiggy',
        'zomato',
        'restaurant',
        'restuarant',
        'cafe',
        'hotel',
        'bakery',
        'sweets',
        'mithai',
        'biryani',
        'tiffin',
        'mess',
        'canteen',
        'pizza',
        'burger',
        'dhaba',
        'tea',
        'chai',
        'coffee',
        'juice',
        'shawarma',
      ],
    ),
    CategoryMapping(
      category: 'Fuel & Transportation',
      keywords: [
        'petrol',
        'diesel',
        'fuel',
        'cng',
        'hpcl',
        'bpcl',
        'iocl',
        'indian oil',
        'bharat petroleum',
        'hindustan petroleum',
        'shell',
        'uber',
        'ola',
        'rapido',
        'metro',
        'fastag',
        'toll',
        'parking',
        'auto',
        'irctc',
        'redbus',
      ],
    ),
    CategoryMapping(
      category: 'Entertainment',
      keywords: [
        'netflix',
        'prime',
        'hotstar',
        'spotify',
        'youtube',
        'cinema',
        'movies',
        'theatre',
        'pvr',
        'inox',
        'bookmyshow',
        'game',
        'playstation',
      ],
    ),
    CategoryMapping(
      category: 'Health & Medical',
      keywords: [
        'pharmacy',
        'medical',
        'chemist',
        'apollo',
        'medplus',
        'hospital',
        'clinic',
        'doctor',
        'dentist',
        'medicine',
        'lab',
        'diagnostics',
      ],
    ),
    CategoryMapping(
      category: 'Rent & Maintenance',
      keywords: [
        'rent',
        'maintenance',
        'society',
        'apartment',
        'flat',
        'house rent',
        'room rent',
      ],
    ),
    CategoryMapping(
      category: 'Transfer to Others',
      keywords: [
        'advance salary',
        'salary',
        'advance',
        'wage',
        'paisa',
        'money',
        'transfer',
        'loan',
        'repay',
        'sent to',
      ],
    ),
  ];

  /// Load user custom category mappings from persistent storage
  static Future<List<CategoryMapping>> loadMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final String? rawJson = prefs.getString(_storageKey);
    if (rawJson == null) {
      // First time launch: persist defaults
      await saveMappings(defaultCategoryMappings);
      return List.from(defaultCategoryMappings);
    }

    try {
      final List<dynamic> list = json.decode(rawJson);
      final loaded = list.map((e) => CategoryMapping.fromMap(e)).toList();
      return loaded.isNotEmpty ? loaded : List.from(defaultCategoryMappings);
    } catch (_) {
      return List.from(defaultCategoryMappings);
    }
  }

  /// Save category mappings to persistent storage
  static Future<void> saveMappings(List<CategoryMapping> mappings) async {
    final prefs = await SharedPreferences.getInstance();
    final String rawJson = json.encode(mappings.map((m) => m.toMap()).toList());
    await prefs.setString(_storageKey, rawJson);
  }

  /// Add or update a category mapping
  static Future<void> addOrUpdateMapping(CategoryMapping newMapping) async {
    final mappings = await loadMappings();
    final index = mappings.indexWhere(
      (m) => m.category.trim().toLowerCase() == newMapping.category.trim().toLowerCase(),
    );

    if (index >= 0) {
      mappings[index] = newMapping;
    } else {
      mappings.add(newMapping);
    }
    await saveMappings(mappings);
  }

  /// Delete a category mapping by category name
  static Future<void> deleteMapping(String categoryName) async {
    final mappings = await loadMappings();
    mappings.removeWhere(
      (m) => m.category.trim().toLowerCase() == categoryName.trim().toLowerCase(),
    );
    await saveMappings(mappings);
  }

  /// Reset all category mappings back to system defaults
  static Future<void> resetToDefaults() async {
    await saveMappings(defaultCategoryMappings);
  }

  /// Categorize transaction based on message and payee name using registered mappings
  static String categorize(
    String msg, {
    String name = '',
    List<CategoryMapping>? mappings,
  }) {
    final activeMappings = mappings ?? defaultCategoryMappings;
    final combined = '$msg $name'.trim();
    if (combined.isEmpty) return 'Transfer to Others';

    for (final mapping in activeMappings) {
      if (mapping.matches(combined)) {
        return mapping.category;
      }
    }

    return 'Transfer to Others';
  }
}
