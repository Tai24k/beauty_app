import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BeautyApp());
}

class BeautyApp extends StatelessWidget {
  const BeautyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ảnh Đẹp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0E10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF3B5C),
          surface: Color(0xFF1A1A1D),
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 2,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
          activeTrackColor: Color(0xFFFF3B5C),
          inactiveTrackColor: Color(0xFF2C2C30),
          thumbColor: Color(0xFFFF3B5C),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// HOME
// ═══════════════════════════════════════════════════════════════
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _pick(BuildContext ctx) async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (f == null || !ctx.mounted) return;
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => EditorScreen(file: File(f.path))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Text('Ảnh Đẹp',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Chỉnh ảnh đơn giản, đẹp tự nhiên',
                  style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
              const Spacer(),
              GestureDetector(
                onTap: () => _pick(context),
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A1A1D), Color(0xFF232327)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF2C2C30)),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 56, color: Color(0xFFFF3B5C)),
                        SizedBox(height: 16),
                        Text('Chọn ảnh từ thư viện',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text('Chạm để bắt đầu',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF8E8E93))),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              const Center(
                child: Text('Xử lý 100% trên máy · Không watermark',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6E6E73))),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// EDITOR
// ═══════════════════════════════════════════════════════════════
class EditorScreen extends StatefulWidget {
  final File file;
  const EditorScreen({super.key, required this.file});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late File _currentFile = widget.file;
  img.Image? _decoded;
  Uint8List? _previewBytes;
  bool _processing = false;
  int _tab = 0; // 0=Filter, 1=Adjust, 2=Crop

  // Adjust values
  double _brightness = 0;
  double _contrast = 0;
  double _saturation = 0;
  double _warmth = 0;
  double _smooth = 0;

  // Filter
  int _presetIndex = 0;

  // Crop
  int _rotation = 0;
  String _cropRatio = 'Gốc';

  // Undo
  final List<_Snapshot> _history = [];

  static const _presets = <_Preset>[
    _Preset('Gốc', 0, 0, 0, 0),
    _Preset('Tươi sáng', 0.15, 0.1, 0.2, 0.05),
    _Preset('Mềm mại', 0.1, -0.05, -0.1, 0.15),
    _Preset('Cổ điển', 0.05, 0.15, -0.2, 0.1),
    _Preset('Ấm áp', 0.08, 0.05, 0.1, 0.25),
    _Preset('Lạnh', 0, 0.1, 0.05, -0.2),
    _Preset('Đen trắng', 0, 0.2, -1.0, 0),
    _Preset('Cinematic', -0.05, 0.25, -0.15, 0.1),
  ];

  static const _ratios = <String, double?>{
    'Gốc': null,
    '1:1': 1.0,
    '4:3': 4 / 3,
    '3:4': 3 / 4,
    '16:9': 16 / 9,
    '9:16': 9 / 16,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await _currentFile.readAsBytes();
    _decoded = img.decodeImage(bytes);
    await _render();
  }

  Future<void> _render() async {
    if (_decoded == null) return;
    setState(() => _processing = true);

    final params = _RenderParams(
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
      warmth: _warmth,
      smooth: _smooth,
      preset: _presets[_presetIndex],
      rotation: _rotation,
    );

    final result = await _processImage(_decoded!, params);
    if (!mounted) return;
    setState(() {
      _previewBytes = Uint8List.fromList(img.encodeJpg(result, quality: 90));
      _processing = false;
    });
  }

  void _pushHistory() {
    _history.add(_Snapshot(
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
      warmth: _warmth,
      smooth: _smooth,
      presetIndex: _presetIndex,
      rotation: _rotation,
    ));
    if (_history.length > 30) _history.removeAt(0);
  }

  void _undo() {
    if (_history.isEmpty) return;
    final s = _history.removeLast();
    setState(() {
      _brightness = s.brightness;
      _contrast = s.contrast;
      _saturation = s.saturation;
      _warmth = s.warmth;
      _smooth = s.smooth;
      _presetIndex = s.presetIndex;
      _rotation = s.rotation;
    });
    _render();
  }

  Future<void> _save() async {
    if (_decoded == null) return;
    setState(() => _processing = true);
    try {
      var result = await _processImage(
        _decoded!,
        _RenderParams(
          brightness: _brightness,
          contrast: _contrast,
          saturation: _saturation,
          warmth: _warmth,
          smooth: _smooth,
          preset: _presets[_presetIndex],
          rotation: _rotation,
        ),
      );
      result = _applyCrop(result);

      final dir = await getTemporaryDirectory();
      final out = File(
          '${dir.path}/beauty_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await out.writeAsBytes(img.encodeJpg(result, quality: 95));

      await Gal.putImage(out.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu vào thư viện ảnh')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi lưu: $e')),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  img.Image _applyCrop(img.Image src) {
    final ratio = _ratios[_cropRatio];
    if (ratio == null) return src;

    final w = src.width.toDouble();
    final h = src.height.toDouble();
    final srcRatio = w / h;

    int cw, ch;
    if (srcRatio > ratio) {
      ch = h.toInt();
      cw = (ch * ratio).toInt();
    } else {
      cw = w.toInt();
      ch = (cw / ratio).toInt();
    }

    final x = ((w - cw) / 2).toInt();
    final y = ((h - ch) / 2).toInt();
    return img.copyCrop(src, x: x, y: y, width: cw, height: ch);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _history.isEmpty ? null : _undo,
          ),
          TextButton(
            onPressed: _processing ? null : _save,
            child: _processing
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFFF3B5C)),
                  )
                : const Text('Lưu',
                    style: TextStyle(
                        color: Color(0xFFFF3B5C),
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _previewBytes == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: Image.memory(_previewBytes!, fit: BoxFit.contain),
                  ),
          ),
          _panel(),
        ],
      ),
    );
  }

  Widget _panel() {
    return Container(
      color: const Color(0xFF1A1A1D),
      padding: EdgeInsets.only(
          top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _tabBtn(0, Icons.filter_vintage, 'Filter'),
              _tabBtn(1, Icons.tune, 'Chỉnh'),
              _tabBtn(2, Icons.crop, 'Cắt'),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            child: _tabContent(),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(int i, IconData icon, String label) {
    final active = _tab == i;
    return GestureDetector(
      onTap: () => setState(() => _tab = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFF3B5C).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: active ? const Color(0xFFFF3B5C) : const Color(0xFF8E8E93)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active
                        ? const Color(0xFFFF3B5C)
                        : const Color(0xFF8E8E93))),
          ],
        ),
      ),
    );
  }

  Widget _tabContent() {
    switch (_tab) {
      case 0:
        return _filterTab();
      case 1:
        return _adjustTab();
      case 2:
        return _cropTab();
      default:
        return const SizedBox();
    }
  }

  Widget _filterTab() {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final active = _presetIndex == i;
          return GestureDetector(
            onTap: () {
              _pushHistory();
              setState(() => _presetIndex = i);
              _render();
            },
            child: Column(
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: active
                            ? const Color(0xFFFF3B5C)
                            : const Color(0xFF2C2C30),
                        width: active ? 2 : 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _previewBytes == null
                        ? Container(color: const Color(0xFF232327))
                        : ColorFiltered(
                            colorFilter: ColorFilter.matrix(
                                _presets[i].matrix()),
                            child: Image.memory(_previewBytes!,
                                fit: BoxFit.cover),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(_presets[i].name,
                    style: TextStyle(
                        fontSize: 10,
                        color: active
                            ? const Color(0xFFFF3B5C)
                            : const Color(0xFF8E8E93))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _adjustTab() {
    return Column(
      children: [
        _slider('Sáng', _brightness, (v) {
          _pushHistory();
          setState(() => _brightness = v);
          _render();
        }),
        _slider('Tương phản', _contrast, (v) {
          _pushHistory();
          setState(() => _contrast = v);
          _render();
        }),
        _slider('Bão hòa', _saturation, (v) {
          _pushHistory();
          setState(() => _saturation = v);
          _render();
        }),
        _slider('Độ ấm', _warmth, (v) {
          _pushHistory();
          setState(() => _warmth = v);
          _render();
        }),
        _slider('Mịn da', _smooth, (v) {
          _pushHistory();
          setState(() => _smooth = v);
          _render();
        }),
      ],
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF8E8E93))),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: label == 'Mịn da' ? 0 : -1,
              max: 1,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text((value * 100).toInt().toString(),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF8E8E93))),
          ),
        ],
      ),
    );
  }

  Widget _cropTab() {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: _ratios.keys.map((r) {
              final active = _cropRatio == r;
              return GestureDetector(
                onTap: () => setState(() => _cropRatio = r),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFFF3B5C).withOpacity(0.15)
                        : const Color(0xFF232327),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: active
                            ? const Color(0xFFFF3B5C)
                            : Colors.transparent),
                  ),
                  child: Center(
                    child: Text(r,
                        style: TextStyle(
                            fontSize: 12,
                            color: active
                                ? const Color(0xFFFF3B5C)
                                : Colors.white)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _cropBtn(Icons.rotate_90_degrees_ccw, 'Xoay trái', () {
              _pushHistory();
              setState(() => _rotation = (_rotation - 90) % 360);
              _render();
            }),
            _cropBtn(Icons.rotate_90_degrees_cw, 'Xoay phải', () {
              _pushHistory();
              setState(() => _rotation = (_rotation + 90) % 360);
              _render();
            }),
            _cropBtn(Icons.restart_alt, 'Đặt lại', () {
              _pushHistory();
              setState(() {
                _rotation = 0;
                _cropRatio = 'Gốc';
              });
              _render();
            }),
          ],
        ),
      ],
    );
  }

  Widget _cropBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF232327),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Color(0xFF8E8E93))),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// IMAGE PROCESSING
// ═══════════════════════════════════════════════════════════════
class _RenderParams {
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;
  final double smooth;
  final _Preset preset;
  final int rotation;
  _RenderParams({
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.warmth,
    required this.smooth,
    required this.preset,
    required this.rotation,
  });
}

Future<img.Image> _processImage(img.Image src, _RenderParams p) async {
  // Downscale để xử lý nhanh (preview)
  var out = src;
  if (out.width > 1600) {
    out = img.copyResize(out, width: 1600);
  }

  // Xoay
  if (p.rotation != 0) {
    out = img.copyRotate(out, angle: p.rotation);
  }

  // Lấy tổng adjustment
  final bri = p.brightness + p.preset.brightness;
  final con = p.contrast + p.preset.contrast;
  final sat = p.saturation + p.preset.saturation;
  final wrm = p.warmth + p.preset.warmth;

  // Áp dụng điều chỉnh per-pixel
  for (int y = 0; y < out.height; y++) {
    for (int x = 0; x < out.width; x++) {
      final px = out.getPixel(x, y);
      double r = px.r / 255;
      double g = px.g / 255;
      double b = px.b / 255;

      // Brightness
      r += bri;
      g += bri;
      b += bri;

      // Contrast
      r = (r - 0.5) * (1 + con) + 0.5;
      g = (g - 0.5) * (1 + con) + 0.5;
      b = (b - 0.5) * (1 + con) + 0.5;

      // Saturation
      final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      r = lum + (r - lum) * (1 + sat);
      g = lum + (g - lum) * (1 + sat);
      b = lum + (b - lum) * (1 + sat);

      // Warmth
      r *= 1 + wrm * 0.15;
      b *= 1 - wrm * 0.15;

      r = r.clamp(0.0, 1.0);
      g = g.clamp(0.0, 1.0);
      b = b.clamp(0.0, 1.0);

      out.setPixelRgb(x, y, (r * 255).toInt(), (g * 255).toInt(),
          (b * 255).toInt());
    }
  }

  // Smooth (mịn da) — blend với ảnh blur
  if (p.smooth > 0.01) {
    final blurred = img.gaussianBlur(out, radius: 4);
    final amount = p.smooth.clamp(0.0, 1.0);
    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final o = out.getPixel(x, y);
        final b = blurred.getPixel(x, y);
        final r = (o.r * (1 - amount) + b.r * amount).toInt();
        final g = (o.g * (1 - amount) + b.g * amount).toInt();
        final bl = (o.b * (1 - amount) + b.b * amount).toInt();
        out.setPixelRgb(x, y, r, g, bl);
      }
    }
  }

  return out;
}

// ═══════════════════════════════════════════════════════════════
// PRESET
// ═══════════════════════════════════════════════════════════════
class _Preset {
  final String name;
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;

  const _Preset(this.name, this.brightness, this.contrast, this.saturation,
      this.warmth);

  /// Ma trận màu cho preview live (dùng cho ColorFiltered)
  List<double> matrix() {
    final c = 1 + contrast;
    final s = 1 + saturation;
    final t = 0.5 * (1 - c) + brightness;
    final sr = 0.2126 * (1 - s);
    final sg = 0.7152 * (1 - s);
    final sb = 0.0722 * (1 - s);

    final wr = 1 + warmth * 0.15;
    final wb = 1 - warmth * 0.15;

    return [
      c * (sr + s) * wr, c * sg * wr, c * sb * wr, 0, t * 255,
      c * sr, c * (sg + s), c * sb, 0, t * 255,
      c * sr, c * sg, c * (sb + s) * wb, 0, t * 255,
      0, 0, 0, 1, 0,
    ];
  }
}

// ═══════════════════════════════════════════════════════════════
// UNDO SNAPSHOT
// ═══════════════════════════════════════════════════════════════
class _Snapshot {
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;
  final double smooth;
  final int presetIndex;
  final int rotation;
  _Snapshot({
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.warmth,
    required this.smooth,
    required this.presetIndex,
    required this.rotation,
  });
}
