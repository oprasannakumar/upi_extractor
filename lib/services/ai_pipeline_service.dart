import 'dart:developer' as dev;
import '../models/account_mapping.dart';
import '../models/category_mapping.dart';
import '../models/upi_transaction.dart';
import 'category_mapping_service.dart';
import 'gemini_service.dart';
import 'groq_service.dart';
import 'upi_extractor_service.dart';

class AiPipelineService {
  /// Robust extraction pipeline:
  /// Primary: Groq (qwen/qwen3.8-27b)
  /// Fallback 1: Google Gemini (gemini-3.6-flash)
  /// Fallback 2: Local On-Device AI Engine (ML Kit)
  static Future<UpiTransaction> extractWithPipeline(
    String imagePath,
    List<AccountMapping> mappings, {
    List<CategoryMapping>? categoryMappings,
    void Function(String stepMessage)? onStepChange,
  }) async {
    final catMappings = categoryMappings ?? await CategoryMappingService.loadMappings();
    final engineMode = await GeminiService.getEngineMode();
    final groqKey = await GroqService.getApiKey();
    final groqModel = await GroqService.getModel();
    final geminiKey = await GeminiService.getApiKey();
    final geminiModel = await GeminiService.getModel();

    UpiTransaction applyCategory(UpiTransaction tx) {
      final customCat = CategoryMappingService.categorize(tx.msg, name: tx.name, mappings: catMappings);
      if (customCat != 'Transfer to Others') {
        tx.category = customCat;
      }
      return tx;
    }

    // Case 1: Primary is Groq (Default)
    if (engineMode == 'groq') {
      if (groqKey != null && groqKey.isNotEmpty) {
        try {
          onStepChange?.call('Processing with Groq ($groqModel)...');
          final result = await GroqService.extractWithGroq(
            imagePath,
            mappings,
            groqKey,
            modelOverride: groqModel,
          );
          return applyCategory(result);
        } catch (e) {
          dev.log('Groq extraction failed: $e');
          onStepChange?.call('Groq encountered an issue. Falling back to Gemini ($geminiModel)...');
        }
      } else {
        onStepChange?.call('Groq key not configured. Trying Gemini ($geminiModel)...');
      }

      // Fallback 1: Gemini
      if (geminiKey != null && geminiKey.isNotEmpty) {
        try {
          final result = await GeminiService.extractWithGemini(
            imagePath,
            mappings,
            geminiKey,
            modelOverride: geminiModel,
          );
          return applyCategory(result);
        } catch (e) {
          dev.log('Gemini fallback failed: $e');
          onStepChange?.call('Gemini fallback failed. Trying Local On-Device AI Engine...');
        }
      } else {
        onStepChange?.call('Gemini key not configured. Using Local On-Device AI Engine...');
      }

      // Fallback 2: Local Engine
      final localResult = await UpiExtractorService.extractFromImage(imagePath, mappings, categoryMappings: catMappings);
      return applyCategory(localResult);
    }

    // Case 2: Primary is Gemini
    if (engineMode == 'gemini') {
      if (geminiKey != null && geminiKey.isNotEmpty) {
        try {
          onStepChange?.call('Processing with Gemini ($geminiModel)...');
          final result = await GeminiService.extractWithGemini(
            imagePath,
            mappings,
            geminiKey,
            modelOverride: geminiModel,
          );
          return applyCategory(result);
        } catch (e) {
          dev.log('Gemini extraction failed: $e');
          onStepChange?.call('Gemini failed. Falling back to Groq ($groqModel)...');
        }
      }

      // Fallback to Groq
      if (groqKey != null && groqKey.isNotEmpty) {
        try {
          final result = await GroqService.extractWithGroq(
            imagePath,
            mappings,
            groqKey,
            modelOverride: groqModel,
          );
          return applyCategory(result);
        } catch (_) {}
      }

      // Fallback to Local
      final localResult = await UpiExtractorService.extractFromImage(imagePath, mappings, categoryMappings: catMappings);
      return applyCategory(localResult);
    }

    // Case 3: Local Engine selected explicitly
    onStepChange?.call('Processing with Local On-Device Engine...');
    final localResult = await UpiExtractorService.extractFromImage(imagePath, mappings, categoryMappings: catMappings);
    return applyCategory(localResult);
  }
}
