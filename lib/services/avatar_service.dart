import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Setup Checklist ───────────────────────────────────────────
// 1. Supabase Dashboard → Storage → "New bucket"
//    Name:   profile-photos
//    Public: OFF (private)
//
// 2. SQL Editor – run once:
//
//    ALTER TABLE public.cs_app_profiles
//      ADD COLUMN IF NOT EXISTS avatar_path text;
//
//    CREATE POLICY "profile_photos_select" ON storage.objects
//      FOR SELECT TO authenticated
//      USING (bucket_id = 'profile-photos');
//
//    CREATE POLICY "profile_photos_insert" ON storage.objects
//      FOR INSERT TO authenticated
//      WITH CHECK (bucket_id = 'profile-photos'
//        AND (storage.foldername(name))[2] = auth.uid()::text);
//
//    CREATE POLICY "profile_photos_update" ON storage.objects
//      FOR UPDATE TO authenticated
//      USING (bucket_id = 'profile-photos'
//        AND (storage.foldername(name))[2] = auth.uid()::text);
//
//    CREATE POLICY "profile_photos_delete" ON storage.objects
//      FOR DELETE TO authenticated
//      USING (bucket_id = 'profile-photos'
//        AND (storage.foldername(name))[2] = auth.uid()::text);
//
//    NOTIFY pgrst, 'reload schema';
// ────────────────────────────────────────────────────────────────

/// Custom exception with a user-friendly message for UI display.
class AvatarUploadException implements Exception {
  final String userMessage;
  final Object? cause;
  AvatarUploadException(this.userMessage, [this.cause]);
  @override
  String toString() => userMessage;
}

class AvatarService {
  static final _supabase = Supabase.instance.client;
  static const _bucket = 'profile-photos';

  /// Max file size: 2 MB
  static const _maxBytes = 2 * 1024 * 1024;

  /// Allowed file extensions (lowercase, without dot)
  static const _allowedExts = {'jpg', 'jpeg', 'png', 'heic'};

  /// Cached bucket existence flag – only caches positive results so that
  /// a missing bucket is re-checked every time.
  static bool _bucketVerified = false;

  /// SQL block that must be executed once in Supabase SQL Editor
  /// to create the Storage RLS policies.
  static const setupSql = '''ALTER TABLE public.cs_app_profiles
  ADD COLUMN IF NOT EXISTS avatar_path text;

CREATE POLICY "profile_photos_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'profile-photos');

CREATE POLICY "profile_photos_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'profile-photos'
    AND (storage.foldername(name))[2] = auth.uid()::text);

CREATE POLICY "profile_photos_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'profile-photos'
    AND (storage.foldername(name))[2] = auth.uid()::text);

CREATE POLICY "profile_photos_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'profile-photos'
    AND (storage.foldername(name))[2] = auth.uid()::text);

NOTIFY pgrst, 'reload schema';''';

  /// Checks whether the Storage bucket exists (result cached after first
  /// success, so the network call only happens once per app session).
  ///
  /// Returns `true`  → bucket ready, proceed with upload.
  /// Returns `false` → bucket missing, show setup dialog.
  static Future<bool> checkBucketExists() async {
    if (_bucketVerified) return true;
    try {
      // Listing the bucket root – fails with 404 if the bucket is missing.
      await _supabase.storage.from(_bucket).list(path: '');
      _bucketVerified = true;
      return true;
    } on StorageException catch (e) {
      if (e.statusCode == '404' || e.message.contains('Bucket not found')) {
        return false;
      }
      // Other errors (e.g. 403 policy) – bucket exists, policies may be off.
      // Let the actual upload surface the specific error later.
      _bucketVerified = true;
      return true;
    }
  }

  /// Resets the cached check so the next call to [checkBucketExists]
  /// performs a fresh network request (e.g. after the user created the bucket).
  static void resetBucketCache() => _bucketVerified = false;

  /// Opens the image picker, validates the file, uploads to Supabase Storage
  /// (bucket "profile-photos"), and saves the storage path in
  /// cs_app_profiles.avatar_path.
  ///
  /// Returns the storage path on success, null if the user cancelled.
  /// Throws [AvatarUploadException] with a clear user message on failure.
  static Future<String?> pickAndUploadAvatar() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw AvatarUploadException('Nicht eingeloggt. Bitte neu starten.');
    }

    // ── 1. Pick image ───────────────────────────────────────
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return null; // user cancelled

    // ── 2. Validate extension ───────────────────────────────
    final ext = picked.path.split('.').last.toLowerCase();
    if (!_allowedExts.contains(ext)) {
      throw AvatarUploadException(
        'Nicht unterstütztes Format (.$ext).\n'
        'Erlaubt: JPG, PNG, HEIC.',
      );
    }

    // ── 3. Validate file size ───────────────────────────────
    final bytes = await picked.readAsBytes();
    if (bytes.length > _maxBytes) {
      final sizeMB = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      throw AvatarUploadException(
        'Bild zu gross ($sizeMB MB).\n'
        'Maximale Grösse: 2 MB.',
      );
    }

    final storagePath = 'avatars/$uid/avatar.$ext';

    // ── 4. Upload with differentiated error handling ─────────
    try {
      await _supabase.storage
          .from(_bucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
    } on StorageException catch (e) {
      final code = e.statusCode;
      if (code == '404' || e.message.contains('Bucket not found')) {
        throw AvatarUploadException(
          "Storage-Bucket '$_bucket' fehlt.\n"
          'Bitte im Supabase Dashboard unter Storage anlegen (private).',
          e,
        );
      }
      if (code == '403' ||
          e.message.contains('security') ||
          e.message.contains('policy') ||
          e.message.contains('row-level')) {
        throw AvatarUploadException(
          'Kein Zugriff auf Storage (Policy/RLS).\n'
          'Bitte die Storage-Policies im Supabase SQL Editor prüfen.',
          e,
        );
      }
      throw AvatarUploadException('Upload fehlgeschlagen: ${e.message}', e);
    }

    // ── 5. Persist path in profile ──────────────────────────
    try {
      await _supabase
          .from('cs_app_profiles')
          .update({'avatar_path': storagePath})
          .eq('user_id', uid);
    } catch (e) {
      // Upload succeeded but DB update failed – still return the path
      // ignore: avoid_print
      print('avatar_path DB update failed (upload ok): $e');
    }

    return storagePath;
  }

  /// Creates a signed URL for a single storage path (TTL 1 hour).
  static Future<String> createSignedUrl(String path) async {
    return _supabase.storage.from(_bucket).createSignedUrl(path, 3600);
  }

  /// Creates signed URLs for multiple storage paths in one call.
  /// Returns a map: storagePath → signedUrl.
  static Future<Map<String, String>> createSignedUrls(
    List<String> paths,
  ) async {
    if (paths.isEmpty) return {};

    final result = await _supabase.storage
        .from(_bucket)
        .createSignedUrls(paths, 3600);

    final map = <String, String>{};
    for (final item in result) {
      if (item.signedUrl.isNotEmpty) {
        map[item.path] = item.signedUrl;
      }
    }
    return map;
  }

  /// Extracts avatar_path from an embedded or separate profile map.
  /// Returns null if no avatar is set.
  static String? avatarPathFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    final path = profile['avatar_path'] as String?;
    return (path != null && path.isNotEmpty) ? path : null;
  }
}
