import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../services/logger_service.dart';

class Receipt {
  final int id;
  final String imageUrl;
  final DateTime createdAt;
  final int? expenseId;
  final String userId;

  Receipt({
    required this.id,
    required this.imageUrl,
    required this.createdAt,
    this.expenseId,
    required this.userId,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      id: json['id'],
      imageUrl: json['image_url'],
      createdAt: DateTime.parse(json['created_at']),
      expenseId: json['expense_id'],
      userId: json['user_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'image_url': imageUrl,
      'created_at': createdAt.toIso8601String(),
      'expense_id': expenseId,
      'user_id': userId,
    };
  }
}

class ReceiptService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Fetch a receipt by ID
  Future<Receipt?> fetchReceipt(int id) async {
    try {
      final response = await supabase
          .from('receipts')
          .select('*')
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        LoggerService.warning('No receipt found for ID: $id');
        return null;
      }

      return Receipt.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching receipt: $error');
      return null;
    }
  }

  /// Create a new receipt
  Future<bool> createReceipt(Receipt receipt) async {
    try {
      await supabase.from('receipts').insert(receipt.toJson());
      LoggerService.info('Receipt created successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error creating receipt: $error');
      return false;
    }
  }

  /// Update an existing receipt
  Future<bool> updateReceipt(Receipt receipt) async {
    try {
      await supabase
          .from('receipts')
          .update(receipt.toJson())
          .eq('id', receipt.id);

      LoggerService.info('Receipt updated successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error updating receipt: $error');
      return false;
    }
  }

  /// Delete a receipt by ID
  Future<bool> deleteReceipt(int id) async {
    try {
      await supabase.from('receipts').delete().eq('id', id);
      LoggerService.info('Receipt deleted successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error deleting receipt: $error');
      return false;
    }
  }

  /// Upload a receipt image and save to database
  Future<Receipt?> uploadReceipt(File file) async {
    try {
      // 1. Compress the image before uploading
      final compressedFile = await _compressImage(file);

      // 2. Generate a unique filename
      final fileExt = path.extension(compressedFile.path);
      final fileName = '${const Uuid().v4()}$fileExt';
      final storagePath = 'receipts/$fileName';

      // 3. Upload to Supabase Storage
      final response = await supabase.storage
          .from('receipts')
          .upload(
            storagePath,
            compressedFile,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      LoggerService.debug('Receipt uploaded: $response');

      // 4. Get the public URL for the uploaded image
      final publicUrl = supabase.storage
          .from('receipts')
          .getPublicUrl(storagePath);

      LoggerService.debug('Public URL: $publicUrl');

      // 5. Save receipt record to database
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final receiptData = {
        'image_url': publicUrl,
        'created_at': DateTime.now().toIso8601String(),
        'user_id': userId,
      };

      final insertResponse = await supabase
          .from('receipts')
          .insert(receiptData)
          .select()
          .single();

      LoggerService.debug('Receipt DB insert: $insertResponse');

      return Receipt.fromJson(insertResponse);

    } on StorageException catch (e) {
      LoggerService.error('Storage error during upload', e);

      if (e.statusCode == '413') {
        throw Exception('Image too large. Compress below 50MB');
      } else if (e.statusCode == '404') {
        throw Exception('Storage configuration error');
      }
      rethrow;
    } catch (e) {
      LoggerService.error('General upload error', e);
      rethrow;
    }
  }

  // Compress image to reduce size
  Future<File> _compressImage(File file) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_compressed.jpg';

    try {
      LoggerService.debug('Original image size: ${file.lengthSync()} bytes');

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 85,
      );

      if (result != null) {
        final compressedFile = File(result.path);
        LoggerService.debug(
            'Compressed image size: ${compressedFile.lengthSync()} bytes');
        return compressedFile;
      } else {
        LoggerService.warning('Compression failed, using original file');
        return file;
      }
    } catch (e) {
      LoggerService.error('Error during compression', e);
      return file;
    }
  }

  /// Link a receipt with an expense
  Future<bool> linkReceiptToExpense(int receiptId, int expenseId) async {
    try {
      LoggerService.info('Linking receipt $receiptId to expense $expenseId');
      await supabase
          .from('receipts')
          .update({'expense_id': expenseId}).eq('id', receiptId);
      return true;
    } catch (e) {
      LoggerService.error('Error linking receipt to expense', e);
      return false;
    }
  }
}
