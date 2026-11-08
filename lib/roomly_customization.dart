import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const rmMediaBucket = 'organization-media';
SupabaseClient get _db => Supabase.instance.client;

String _message(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is StorageException) return e.message;
  if (e is FormatException) return e.message;
  return 'Unable to complete the request. Check your connection and retry.';
}

class RmMedia {
  static final changed = ValueNotifier<int>(0);
  static final _cache = <String, Future<Map<String, dynamic>>>{};

  static Future<Map<String, dynamic>> load(String organizationId) {
    return _cache.putIfAbsent(organizationId, () async {
      final data = await _db.rpc('rm_public_branding', params: {
        'p_organization_id': organizationId,
      });
      return data == null ? <String, dynamic>{}
          : Map<String, dynamic>.from(data as Map);
    });
  }

  static void refresh(String organizationId) {
    _cache.remove(organizationId);
    changed.value++;
  }

  static String url(String path) =>
      _db.storage.from(rmMediaBucket).getPublicUrl(path);

  static String? path(Map<String, dynamic> data, String kind, String? roomId) {
    if (kind == 'room') {
      final photos = data['room_photos'];
      return photos is Map ? photos[roomId] as String? : null;
    }
    return data['${kind}_path'] as String?;
  }
}

// A fresh future is only created when the organization is explicitly refreshed.
class RmMediaImage extends StatelessWidget {
  const RmMediaImage({super.key, required this.organizationId,
    required this.kind, required this.fallback, this.roomId,
    this.fit = BoxFit.cover, this.height, this.width});
  final String organizationId;
  final String kind;
  final String? roomId;
  final Widget fallback;
  final BoxFit fit;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: RmMedia.changed,
    builder: (context, _, child) => FutureBuilder<Map<String, dynamic>>(
      future: RmMedia.load(organizationId),
      builder: (context, snapshot) {
        final path = RmMedia.path(snapshot.data ?? {}, kind, roomId);
        final image = path == null ? fallback : Image.network(
          RmMedia.url(path), fit: fit,
          semanticLabel: kind == 'logo' ? 'Organization logo' : 'Organization photo',
          errorBuilder: (_, __, ___) => fallback,
        );
        return SizedBox(height: height, width: width, child: image);
      },
    ),
  );
}

class RmAppLogo extends StatelessWidget {
  const RmAppLogo({super.key, this.height = 43.2});
  final double height;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/roomly-logo.png', height: height, width: height * 3,
    fit: BoxFit.contain, semanticLabel: 'Roomly',
    errorBuilder: (_, __, ___) => const Text('Roomly'),
  );
}

class RmBrandTitle extends StatelessWidget {
  const RmBrandTitle({super.key, this.organizationId, this.title});
  final String? organizationId;
  final String? title;
  @override
  Widget build(BuildContext context) {
    final height = title == null ? 43.2 : 33.6;
    final logo = organizationId == null ? RmAppLogo(height: height)
      : RmMediaImage(organizationId: organizationId!, kind: 'logo',
          fit: BoxFit.contain, height: height, width: height * 3,
          fallback: RmAppLogo(height: height));
    if (title == null) return logo;
    return Row(children: [logo, const SizedBox(width: 12),
      Expanded(child: Text(title!, maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium)),
    ]);
  }
}

// Wrap each PAGE Scaffold once, not each dialog. It never covers page controls.
class RmPageShell extends StatelessWidget {
  const RmPageShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(children: [
    Expanded(child: child),
    Material(color: Theme.of(context).colorScheme.surface,
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Powered by', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 8), const RmAppLogo(height: 22),
        ]),
      )),
    ),
  ]);
}

Future<bool> _confirm(BuildContext context, String title, Widget content) async {
  return await showDialog<bool>(context: context, builder: (dialogContext) =>
    AlertDialog(title: Text(title), content: content, actions: [
      TextButton(onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
        child: const Text('Confirm')),
    ])) ?? false;
}

class RmMediaEditor extends StatefulWidget {
  const RmMediaEditor({super.key, required this.organizationId,
    required this.kind, required this.label, this.roomId});
  final String organizationId;
  final String kind;
  final String label;
  final String? roomId;
  @override
  State<RmMediaEditor> createState() => _RmMediaEditorState();
}

class _RmMediaEditorState extends State<RmMediaEditor> {
  bool busy = false;
  String? error;

  Future<void> save(String? path) async {
    await _db.rpc('rm_admin_set_media', params: {
      'p_organization_id': widget.organizationId,
      'p_kind': widget.kind, 'p_path': path, 'p_room_id': widget.roomId,
    });
    RmMedia.refresh(widget.organizationId);
  }

  Future<void> upload() async {
    if (busy) return;
    setState(() {busy = true; error = null;});
    try {
      final file = await FilePicker.pickFile(type: FileType.custom,
        allowedExtensions: ['jpg','jpeg','png','webp']);
      if (file == null) return;
      final length = file.lengthSync() ?? await file.length();
      if (length == null || length < 1 || length > 5 * 1024 * 1024) {
        throw const FormatException('Choose an image no larger than 5 MB.');
      }
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        throw const FormatException('Choose an image no larger than 5 MB.');
      }
      String extension;
      String mime;
      if (bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80 &&
          bytes[2] == 78 && bytes[3] == 71) {
        extension = 'png'; mime = 'image/png';
      } else if (bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) {
        extension = 'jpg'; mime = 'image/jpeg';
      } else if (bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(0,4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8,12)) == 'WEBP') {
        extension = 'webp'; mime = 'image/webp';
      } else {
        throw const FormatException('Select a valid JPG, PNG or WebP image.');
      }
      final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: 1600, allowUpscaling: false);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {codec.dispose();}
      if (!mounted) return;
      final approved = await _confirm(context, 'Use this ${widget.label.toLowerCase()}?',
        SizedBox(width: 440, height: 260,
          child: Image.memory(bytes, fit: BoxFit.contain)));
      if (!approved) return;
      if (!mounted) return;
      final directory = widget.kind == 'room'
          ? '${widget.organizationId}/rooms/${widget.roomId}'
          : '${widget.organizationId}/${widget.kind}';
      final path = '$directory/${const Uuid().v4()}.$extension';
      await _db.storage.from(rmMediaBucket).uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: mime, upsert: false));
      // Do not auto-delete on a network error: the RPC may have committed.
      await save(path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image saved.')));
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {if (mounted) setState(() => busy = false);}
  }

  Future<void> remove() async {
    if (busy) return;
    final approved = await _confirm(context, 'Remove ${widget.label.toLowerCase()}?',
      const Text('The page will use its fallback image or branding.'));
    if (!approved || !mounted) return;
    setState(() {busy = true; error = null;});
    try {await save(null);}
    catch (e) {if (mounted) setState(() => error = _message(e));}
    finally {if (mounted) setState(() => busy = false);}
  }

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.label, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        RmMediaImage(organizationId: widget.organizationId, kind: widget.kind,
          roomId: widget.roomId, height: 180, width: double.infinity,
          fit: BoxFit.contain,
          fallback: const Center(child: Icon(Icons.image_outlined, size: 56))),
        const SizedBox(height: 12),
        const Text('JPG, PNG or WebP. Maximum 5 MB. Images are publicly viewable.'),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, children: [
          FilledButton.icon(onPressed: busy ? null : upload,
            icon: const Icon(Icons.upload), label: const Text('Upload photo')),
          TextButton(onPressed: busy ? null : remove, child: const Text('Remove')),
        ]),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ],
    ),
  ));
}

// Add a button to your existing organization profile screen to open this page.
class RmOrganizationMediaScreen extends StatefulWidget {
  const RmOrganizationMediaScreen({super.key, required this.organizationId});
  final String organizationId;
  @override
  State<RmOrganizationMediaScreen> createState() => _RmOrganizationMediaScreenState();
}
class _RmOrganizationMediaScreenState extends State<RmOrganizationMediaScreen> {
  late final Future<List<Map<String,dynamic>>> rooms = _loadRooms();
  Future<List<Map<String,dynamic>>> _loadRooms() async {
    final data = await _db.rpc('rm_admin_list_rooms', params: {
      'p_organization_id': widget.organizationId,
    });
    return (data as List).map((r) => Map<String,dynamic>.from(r as Map)).toList();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: RmBrandTitle(organizationId: widget.organizationId,
      title: 'Photos and branding')),
    body: FutureBuilder<List<Map<String,dynamic>>>(future: rooms,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text(_message(snapshot.error!)));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(padding: const EdgeInsets.all(24), children: [
          RmMediaEditor(organizationId: widget.organizationId,
            kind: 'logo', label: 'Organization logo'),
          RmMediaEditor(organizationId: widget.organizationId,
            kind: 'welcome', label: 'Welcome-page photo'),
          for (final room in snapshot.data!) RmMediaEditor(
            key: ValueKey(room['id']), organizationId: widget.organizationId,
            kind: 'room', roomId: room['id'] as String,
            label: '${room['name']} — room photo'),
        ]);
      }),
  );
}

class RmSlugButton extends StatefulWidget {
  const RmSlugButton({super.key, required this.organizationId,
    required this.currentSlug, required this.onSaved});
  final String organizationId;
  final String currentSlug;
  final ValueChanged<String> onSaved;
  @override
  State<RmSlugButton> createState() => _RmSlugButtonState();
}
class _RmSlugButtonState extends State<RmSlugButton> {
  bool busy = false;
  Future<void> edit() async {
    final controller = TextEditingController(text: widget.currentSlug);
    String? value;
    try {
      final approved = await _confirm(context, 'Edit organization booking URL',
        TextField(controller: controller, maxLength: 80,
          decoration: const InputDecoration(labelText: 'Booking slug',
            helperText: 'Old links remain valid. Use letters, numbers and hyphens.')));
      if (!approved) return;
      value = controller.text.trim().toLowerCase();
    } finally {controller.dispose();}
    if (!mounted) return;
    final input = value ?? '';
    if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(input) ||
        input.length < 3 || input.length > 80) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Use 3–80 lowercase letters, numbers and single hyphens.')));
      return;
    }
    setState(() => busy = true);
    try {
      final slug = await _db.rpc('rm_system_set_org_slug', params: {
        'p_organization_id': widget.organizationId, 'p_slug': input,
      }) as String;
      RmMedia.refresh(widget.organizationId);
      if (!mounted) return;
      widget.onSaved(slug);
      final link = Uri.base.replace(query: '', fragment: '/o/$slug').toString()
        .replaceFirst('?#', '#');
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Booking address saved'),
        content: SelectableText(link), actions: [
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: link)),
            child: const Text('Copy link')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done')),
        ]));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_message(e))));
    } finally {if (mounted) setState(() => busy = false);}
  }
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: busy ? null : edit, icon: const Icon(Icons.link),
    label: Text(busy ? 'Saving…' : 'Edit booking URL'),
  );
}
