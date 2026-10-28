// Port of IconPicker.tsx — pick, square-crop to 256px, upload to `entity-icons`.

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'theme.dart';
import 'toast.dart';
import 'widgets.dart';

const _bucket = 'entity-icons';
const _maxSourceBytes = 10 * 1024 * 1024;

class IconPickerField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final String userId;
  final String folder; // assets | wallets
  final IconData fallback;
  final Color? bgColor;
  final String? label;
  const IconPickerField({super.key, required this.value, required this.onChanged, required this.userId, required this.folder, required this.fallback, this.bgColor, this.label});
  @override
  State<IconPickerField> createState() => _IconPickerFieldState();
}

class _IconPickerFieldState extends State<IconPickerField> {
  bool uploading = false;

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxSourceBytes) {
      Toast.error('حجم تصویر نباید بیشتر از ۱۰ مگابایت باشد.');
      return;
    }
    setState(() => uploading = true);
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        Toast.error('لطفاً یک فایل تصویری انتخاب کن.');
        return;
      }
      final side = decoded.width < decoded.height ? decoded.width : decoded.height;
      final cropped = img.copyCrop(decoded, x: (decoded.width - side) ~/ 2, y: (decoded.height - side) ~/ 2, width: side, height: side);
      final target = side < 256 ? side : 256;
      final resized = img.copyResize(cropped, width: target, height: target, interpolation: img.Interpolation.cubic);
      final out = img.encodeJpg(resized, quality: 85);
      final path = '${widget.userId}/${widget.folder}/${const Uuid().v4()}.jpg';
      final storage = Supabase.instance.client.storage.from(_bucket);
      await storage.uploadBinary(path, out, fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '31536000', upsert: false));
      widget.onChanged(storage.getPublicUrl(path));
    } catch (e) {
      Toast.error('بارگذاری آیکون ناموفق بود.');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Stack(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: widget.bgColor ?? const Color(0x1F94A3B8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.white10),
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.value != null ? Image.network(widget.value!, fit: BoxFit.cover) : Icon(widget.fallback, color: C.slate300),
        ),
        if (uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
              child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            ),
          ),
      ]),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.label != null) Text(widget.label!, style: const TextStyle(fontSize: 12, color: C.slate400)),
          const SizedBox(height: 6),
          Row(children: [
            AppButton(widget.value != null ? 'تغییر آیکون' : 'بارگذاری آیکون',
                icon: Icons.photo_camera_outlined, variant: BtnVariant.secondary, dense: true, onPressed: uploading ? null : _pick),
            if (widget.value != null && !uploading)
              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: C.rose300), onPressed: () => widget.onChanged(null)),
          ]),
          const SizedBox(height: 4),
          const Text('اختیاری · PNG/JPG/WebP · به‌صورت مربع ۲۵۶ پیکسل فشرده می‌شود', style: TextStyle(fontSize: 11, color: C.slate500)),
        ]),
      ),
    ]);
  }
}

String? iconUrlToStoragePath(String? url) {
  if (url == null) return null;
  const marker = '/entity-icons/';
  final idx = url.indexOf(marker);
  if (idx == -1) return null;
  return Uri.decodeComponent(url.substring(idx + marker.length));
}

Future<void> deleteEntityIcon(String? iconUrl) async {
  final path = iconUrlToStoragePath(iconUrl);
  if (path == null) return;
  try {
    await Supabase.instance.client.storage.from(_bucket).remove([path]);
  } catch (_) {}
}
