// ============================================================================
//  NEXUS CALC 4D  -  Spatial Node + Time-Travel Smart Calculator
//  Single-file Flutter app (Android / iOS / Windows / macOS / Linux / Web)
//  Only dependency: shared_preferences
// ============================================================================
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ----------------------------------------------------------------------------
// Theme constants
// ----------------------------------------------------------------------------
const Color kCyan = Color(0xFF6585A6); // slate blue
const Color kPurple = Color(0xFFC9581A); // orange
const Color kPink = Color(0xFFD4668F);
const Color kGreen = Color(0xFF2F855A);
const Color kAmber = Color(0xFFD9A21B);
const Color kRed = Color(0xFFD1391D);
const Color kGrey = Color(0xFF6B7A93);
const Color kInk = Color(0xFF2A3A5C);
const Color kBg = Color(0xFFF6F6F7);
const double kNodeW = 132;
const double kNodeH = 76;
const List<String> kOps = ['+', '−', '×', '÷', '%'];
const List<Color> kTagColors = [Color(0xFF9AA5B5), kCyan, kPurple, kGreen, kAmber, kPink, kRed];
const List<String> kTagNames = ['None', 'Blue', 'Orange', 'Green', 'Amber', 'Pink', 'Red'];
const List<List<String>> kRows = [
  ['C', '(', ')', '⌫'],
  ['7', '8', '9', '÷'],
  ['4', '5', '6', '×'],
  ['1', '2', '3', '−'],
  ['0', '.', '%', '+'],
  ['='],
];
const String kPrefsKey = 'nexus_history_v1';

Color al(Color c, double o) => c.withAlpha((o * 255).round());

BoxShadow softShadow({required Color color, required double blurRadius}) =>
    const BoxShadow(color: Color(0x1F2A3A5C), blurRadius: 8, offset: Offset(0, 2));

String _two(int n) => n.toString().padLeft(2, '0');
String _hms(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
String _stamp(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

// ----------------------------------------------------------------------------
// Number formatting
// ----------------------------------------------------------------------------
String fmt(double v) {
  if (!v.isFinite) return 'Error';
  if (v.abs() >= 1e15) return v.toStringAsExponential(4);
  var s = v.abs().toStringAsFixed(8);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  final parts = s.split('.');
  final ip = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  final res = parts.length > 1 ? '$ip.${parts[1]}' : ip;
  return (v < 0 && res != '0' ? '-' : '') + res;
}

String plainNum(double v) {
  if (!v.isFinite) return '0';
  if (v.abs() >= 1e15) return v.toStringAsExponential(6);
  var s = v.toStringAsFixed(10);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  if (s == '-0') s = '0';
  return s;
}

// ----------------------------------------------------------------------------
// Expression evaluator (recursive descent; supports + - * / % ( ) and unary -)
// ----------------------------------------------------------------------------
class _Parser {
  final String s;
  int i = 0;
  _Parser(this.s);
  bool get atEnd => i >= s.length;

  double parse() {
    final v = _expr();
    if (!atEnd) throw const FormatException('Unexpected token');
    return v;
  }

  double _expr() {
    var v = _term();
    while (!atEnd && (s[i] == '+' || s[i] == '-')) {
      final op = s[i++];
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _unary();
    while (!atEnd && (s[i] == '*' || s[i] == '/')) {
      final op = s[i++];
      final r = _unary();
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }

  double _unary() {
    if (!atEnd && s[i] == '-') {
      i++;
      return -_unary();
    }
    if (!atEnd && s[i] == '+') {
      i++;
      return _unary();
    }
    return _post();
  }

  double _post() {
    var v = _prim();
    while (!atEnd && s[i] == '%') {
      i++;
      v /= 100;
    }
    return v;
  }

  double _prim() {
    if (atEnd) throw const FormatException('Unexpected end');
    if (s[i] == '(') {
      i++;
      final v = _expr();
      if (atEnd || s[i] != ')') throw const FormatException('Missing )');
      i++;
      return v;
    }
    final st = i;
    while (!atEnd && (s.codeUnitAt(i) >= 48 && s.codeUnitAt(i) <= 57 || s[i] == '.')) {
      i++;
    }
    if (st == i) throw const FormatException('Number expected');
    return double.parse(s.substring(st, i));
  }
}

double? evalExpr(String src) {
  var s = src
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-')
      .replaceAll(' ', '')
      .replaceAll(',', '');
  final open = '('.allMatches(s).length - ')'.allMatches(s).length;
  if (open > 0) s += ')' * open;
  while (s.isNotEmpty && '+-*/'.contains(s[s.length - 1])) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return null;
  try {
    final p = _Parser(s);
    final v = p.parse();
    return v.isFinite ? v : null;
  } catch (_) {
    return null;
  }
}

// ----------------------------------------------------------------------------
// Models
// ----------------------------------------------------------------------------
class NodeItem {
  final String id;
  String label;
  double value;
  double x, y;
  NodeItem(this.id, this.label, this.value, this.x, this.y);
  NodeItem copy() => NodeItem(id, label, value, x, y);
}

class EdgeItem {
  final String id;
  final String from;
  final String to;
  String op;
  EdgeItem(this.id, this.from, this.to, this.op);
  EdgeItem copy() => EdgeItem(id, from, to, op);
}

class Snap {
  final List<NodeItem> nodes;
  final List<EdgeItem> edges;
  final String expr;
  final String desc;
  final DateTime t;
  Snap(this.nodes, this.edges, this.expr, this.desc, this.t);
}

class HistoryEntry {
  final String id;
  String title;
  final String expr;
  final double result;
  final DateTime ts;
  int tag;
  final String src;
  HistoryEntry({
    required this.id,
    required this.title,
    required this.expr,
    required this.result,
    required this.ts,
    required this.tag,
    required this.src,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'expr': expr,
        'result': result,
        'ts': ts.millisecondsSinceEpoch,
        'tag': tag,
        'src': src,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String,
        title: j['title'] as String,
        expr: j['expr'] as String,
        result: (j['result'] as num).toDouble(),
        ts: DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
        tag: (j['tag'] as int).clamp(0, 6),
        src: (j['src'] as String?) ?? 'keypad',
      );
}

// ----------------------------------------------------------------------------
// Graph math.
// Edge  A --op--> B  means:  computed(B) = computed(A) op value(B)
// A node with several incoming edges folds the extra ones in order:
//   acc = acc op computed(source_i)
// Total = sum of computed values of all END nodes (nodes with no outgoing edge)
// ----------------------------------------------------------------------------
double applyOp(String op, double a, double b) {
  switch (op) {
    case '+':
      return a + b;
    case '−':
      return a - b;
    case '×':
      return a * b;
    case '÷':
      return b == 0 ? double.nan : a / b;
    case '%':
      return a * b / 100;
  }
  return b;
}

Map<String, double> computeAll(List<NodeItem> nodes, List<EdgeItem> edges) {
  final byId = {for (final n in nodes) n.id: n};
  final res = <String, double>{};
  final visiting = <String>{};
  double calc(String id) {
    if (res.containsKey(id)) return res[id]!;
    final n = byId[id];
    if (n == null) return 0;
    if (!visiting.add(id)) return double.nan;
    final inc = edges.where((e) => e.to == id).toList();
    double acc;
    if (inc.isEmpty) {
      acc = n.value;
    } else {
      acc = applyOp(inc[0].op, calc(inc[0].from), n.value);
      for (var i = 1; i < inc.length; i++) {
        acc = applyOp(inc[i].op, acc, calc(inc[i].from));
      }
    }
    visiting.remove(id);
    res[id] = acc;
    return acc;
  }

  for (final n in nodes) {
    calc(n.id);
  }
  return res;
}

double graphTotal(List<NodeItem> nodes, List<EdgeItem> edges) {
  if (nodes.isEmpty) return 0;
  final comp = computeAll(nodes, edges);
  final hasOut = edges.map((e) => e.from).toSet();
  var total = 0.0;
  for (final n in nodes) {
    if (!hasOut.contains(n.id)) total += comp[n.id] ?? 0;
  }
  return total;
}

Offset _clipToRect(Offset c, Offset other) {
  final d = other - c;
  if (d.distance < 0.001) return c;
  final sx = d.dx.abs() < 1e-6 ? double.infinity : (kNodeW / 2) / d.dx.abs();
  final sy = d.dy.abs() < 1e-6 ? double.infinity : (kNodeH / 2) / d.dy.abs();
  final s = math.min(sx, sy) * 1.03;
  return c + d * s;
}

List<Offset> edgePoints(NodeItem a, NodeItem b) {
  final ca = Offset(a.x + kNodeW / 2, a.y + kNodeH / 2);
  final cb = Offset(b.x + kNodeW / 2, b.y + kNodeH / 2);
  return [_clipToRect(ca, cb), _clipToRect(cb, ca)];
}

// ----------------------------------------------------------------------------
// Painter: dotted grid + glowing neon connections with arrow heads
// ----------------------------------------------------------------------------
class CanvasPainter extends CustomPainter {
  final List<NodeItem> nodes;
  final List<EdgeItem> edges;
  CanvasPainter(this.nodes, this.edges);

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = al(kInk, .12);
    for (double x = 14; x < size.width; x += 28) {
      for (double y = 14; y < size.height; y += 28) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
    final byId = {for (final n in nodes) n.id: n};
    for (final e in edges) {
      final a = byId[e.from];
      final b = byId[e.to];
      if (a == null || b == null) continue;
      final pts = edgePoints(a, b);
      final p1 = pts[0];
      final p2 = pts[1];
      if ((p2 - p1).distance < 2) continue;

      final glow = Paint()
        ..color = al(kCyan, .18)
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      canvas.drawLine(p1, p2, glow);

      final line = Paint()
        ..shader = ui.Gradient.linear(p1, p2, [kCyan, kPurple])
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(p1, p2, line);

      final ang = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
      final head = Path()
        ..moveTo(p2.dx, p2.dy)
        ..lineTo((p2 - Offset.fromDirection(ang - 0.45, 12)).dx, (p2 - Offset.fromDirection(ang - 0.45, 12)).dy)
        ..lineTo((p2 - Offset.fromDirection(ang + 0.45, 12)).dx, (p2 - Offset.fromDirection(ang + 0.45, 12)).dy)
        ..close();
      canvas.drawPath(
          head,
          Paint()
            ..color = al(kPurple, .25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawPath(head, Paint()..color = kPurple);
    }
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) => true;
}

// ----------------------------------------------------------------------------
// Glassmorphism card
// ----------------------------------------------------------------------------
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? border;
  final Color? fill;
  final double blur;
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 20,
    this.border,
    this.fill,
    this.blur = 14,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill ?? Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border ?? al(kInk, .13)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// App
// ----------------------------------------------------------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexusApp());
}

ThemeData _buildTheme() {
  final base = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.light(primary: kCyan, secondary: kPurple, surface: Colors.white),
  );
  return base.copyWith(textTheme: base.textTheme.apply(bodyColor: kInk, displayColor: kInk));
}

class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nexus Calc 4D',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const CalcHome(),
    );
  }
}

class CalcHome extends StatefulWidget {
  const CalcHome({super.key});
  @override
  State<CalcHome> createState() => _CalcHomeState();
}

class _CalcHomeState extends State<CalcHome> {
  // canvas state
  List<NodeItem> _nodes = [];
  List<EdgeItem> _edges = [];
  String _tool = 'node'; // 'node' or an operator
  String? _linkFrom;
  Size _canvasSize = Size.zero;

  // keypad state
  String _expr = '';
  bool _justEval = false;
  bool _keyErr = false;
  bool _keypadMode = false;

  // time travel
  final List<Snap> _timeline = [];
  int _cursor = 0;

  // history / ledger
  List<HistoryEntry> _history = [];
  final TextEditingController _search = TextEditingController();
  int _tagFilter = 0;
  SharedPreferences? _prefs;

  // misc
  final FocusNode _focus = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _wide = false;
  int _uid = 0;

  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_uid++}';

  @override
  void initState() {
    super.initState();
    _timeline.add(Snap([], [], '', 'Start', DateTime.now()));
    _loadHistory();
  }

  @override
  void dispose() {
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ persistence
  Future<void> _loadHistory() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(kPrefsKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        final loaded = list.map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (mounted) setState(() => _history = loaded);
      }
    } catch (_) {
      // in-memory fallback
    }
  }

  void _persist() {
    try {
      _prefs?.setString(kPrefsKey, jsonEncode(_history.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  void _addHistory({required String title, required String expr, required double result, required String src, int tag = 0}) {
    _history.insert(
      0,
      HistoryEntry(id: _id(), title: title, expr: expr, result: result, ts: DateTime.now(), tag: tag, src: src),
    );
    _persist();
  }

  // ------------------------------------------------------------------ time travel
  void _record(String desc, {bool explicit = false}) {
    final branched = _cursor < _timeline.length - 1;
    final d = (branched && !explicit) ? 'Branch from #${_cursor + 1}: $desc' : desc;
    _timeline.add(Snap(
      _nodes.map((n) => n.copy()).toList(),
      _edges.map((e) => e.copy()).toList(),
      _expr,
      d,
      DateTime.now(),
    ));
    if (_timeline.length > 500) _timeline.removeAt(0);
    _cursor = _timeline.length - 1;
  }

  void _apply(Snap s) {
    _nodes = s.nodes.map((n) => n.copy()).toList();
    _edges = s.edges.map((e) => e.copy()).toList();
    _expr = s.expr;
    _justEval = false;
    _keyErr = false;
    _linkFrom = null;
  }

  void _goTo(int i) {
    final t = math.max(0, math.min(i, _timeline.length - 1));
    if (t == _cursor) return;
    setState(() {
      _cursor = t;
      _apply(_timeline[t]);
    });
  }

  void _branchHere() {
    setState(() {
      final atEnd = _cursor == _timeline.length - 1;
      _record(atEnd ? 'Checkpoint' : 'Branch point from #${_cursor + 1}', explicit: true);
    });
    _snack('New timeline step created from this state');
  }

  // ------------------------------------------------------------------ keyboard
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null && (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final k = e.logicalKey;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      _goTo(_cursor - 1);
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      _goTo(_cursor + 1);
      return KeyEventResult.handled;
    }
    if (ctrl) return KeyEventResult.ignored;
    if (!_keypadMode) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _press('=');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _press('⌫');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.delete) {
      _press('C');
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch == null) return KeyEventResult.ignored;
    const map = {
      '*': '×', 'x': '×', 'X': '×', '/': '÷', '-': '−', '+': '+', '.': '.', ',': '.',
      '%': '%', '(': '(', ')': ')', '=': '=',
    };
    if (RegExp(r'^[0-9]$').hasMatch(ch)) {
      _press(ch);
      return KeyEventResult.handled;
    }
    if (map.containsKey(ch)) {
      _press(map[ch]!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------------ keypad logic
  bool _isDigitCh(String c) => c.isNotEmpty && c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  bool _isOpCh(String c) => c.isNotEmpty && '+−×÷'.contains(c);

  void _press(String k) {
    _focus.requestFocus();
    setState(() {
      _keyErr = false;
      var changed = true;
      var desc = 'Key $k';
      String lc() => _expr.isEmpty ? '' : _expr[_expr.length - 1];

      if (_isDigitCh(k) || k == '.') {
        if (_justEval) {
          _expr = '';
          _justEval = false;
        }
        if (k == '.') {
          final seg = RegExp(r'[0-9.]*$').firstMatch(_expr)?.group(0) ?? '';
          if (seg.contains('.') || lc() == ')' || lc() == '%') {
            changed = false;
          } else if (seg.isEmpty) {
            _expr += '0.';
          } else {
            _expr += '.';
          }
        } else {
          if (lc() == ')' || lc() == '%') _expr += '×';
          _expr += k;
        }
      } else if ('+−×÷'.contains(k)) {
        _justEval = false;
        final last = lc();
        if (_expr.isEmpty) {
          _expr = k == '−' ? '−' : '0$k';
        } else if (_expr == '−') {
          changed = false;
        } else if (last == '(') {
          if (k == '−') {
            _expr += k;
          } else {
            changed = false;
          }
        } else if (_isOpCh(last)) {
          if (k == '−' && (last == '×' || last == '÷')) {
            _expr += k;
          } else {
            var e = _expr.substring(0, _expr.length - 1);
            if (e.isNotEmpty && _isOpCh(e[e.length - 1])) e = e.substring(0, e.length - 1);
            _expr = e.isEmpty ? '0$k' : e + k;
          }
        } else {
          _expr += k;
        }
      } else if (k == '%') {
        _justEval = false;
        final last = lc();
        if (_isDigitCh(last) || last == ')' || last == '%') {
          _expr += '%';
        } else {
          changed = false;
        }
      } else if (k == '(') {
        if (_justEval) {
          _expr = '';
          _justEval = false;
        }
        final last = lc();
        _expr += (_isDigitCh(last) || last == ')' || last == '%') ? '×(' : '(';
      } else if (k == ')') {
        final open = '('.allMatches(_expr).length - ')'.allMatches(_expr).length;
        final last = lc();
        if (open > 0 && (_isDigitCh(last) || last == ')' || last == '%')) {
          _expr += ')';
        } else {
          changed = false;
        }
      } else if (k == 'C') {
        _expr = '';
        _justEval = false;
        desc = 'Clear';
      } else if (k == '⌫') {
        if (_justEval) {
          _expr = '';
          _justEval = false;
        } else if (_expr.isNotEmpty) {
          _expr = _expr.substring(0, _expr.length - 1);
        } else {
          changed = false;
        }
        desc = 'Backspace';
      } else if (k == '=') {
        if (_expr.isEmpty || _justEval) {
          changed = false;
        } else {
          final v = evalExpr(_expr);
          if (v == null) {
            _keyErr = true;
            changed = false;
          } else {
            final before = _expr;
            _addHistory(title: 'Quick Calc', expr: before, result: v, src: 'keypad');
            _expr = plainNum(v).replaceAll('-', '−');
            _justEval = true;
            desc = '$before = ${fmt(v)}';
          }
        }
      }
      if (changed) _record(desc);
    });
  }

  // ------------------------------------------------------------------ canvas logic
  bool _reaches(String start, String target) {
    final seen = <String>{};
    final stack = [start];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      if (cur == target) return true;
      if (!seen.add(cur)) continue;
      for (final e in _edges) {
        if (e.from == cur) stack.add(e.to);
      }
    }
    return false;
  }

  void _addEdge(String from, String to, String op) {
    if (from == to) return;
    if (_reaches(to, from)) {
      _snack('That link would create a loop');
      return;
    }
    final a = _nodes.firstWhere((n) => n.id == from);
    final b = _nodes.firstWhere((n) => n.id == to);
    setState(() {
      final idx = _edges.indexWhere((e) => e.from == from && e.to == to);
      if (idx >= 0) {
        _edges[idx].op = op;
      } else {
        _edges.add(EdgeItem(_id(), from, to, op));
      }
      _record("Linked '${a.label}' $op '${b.label}'");
    });
  }

  void _nodeTap(NodeItem n) {
    _focus.requestFocus();
    if (_tool == 'node') {
      _nodeDialog(node: n);
      return;
    }
    if (_linkFrom == null) {
      setState(() => _linkFrom = n.id);
    } else if (_linkFrom == n.id) {
      setState(() => _linkFrom = null);
    } else {
      final from = _linkFrom!;
      setState(() => _linkFrom = null);
      _addEdge(from, n.id, _tool);
    }
  }

  double _clampX(double v) => math.max(0.0, math.min(v, math.max(0.0, _canvasSize.width - kNodeW)));
  double _clampY(double v) => math.max(0.0, math.min(v, math.max(0.0, _canvasSize.height - kNodeH)));

  void _loadSample() {
    setState(() {
      final w = _canvasSize.width;
      final a = NodeItem(_id(), 'Budget', 50000, 16, 24);
      final b = NodeItem(_id(), 'Rent', 12000, math.max(16.0, math.min(200.0, w - kNodeW - 16)), 130);
      final c = NodeItem(_id(), 'Food', 8000, 16, 236);
      _nodes = [a, b, c];
      _edges = [EdgeItem(_id(), a.id, b.id, '−'), EdgeItem(_id(), b.id, c.id, '−')];
      _linkFrom = null;
      _record('Loaded sample budget');
    });
  }

  void _clearCanvas() {
    if (_nodes.isEmpty) return;
    setState(() {
      _nodes = [];
      _edges = [];
      _linkFrom = null;
      _record('Cleared canvas');
    });
  }

  String _canvasSummary() {
    final byId = {for (final n in _nodes) n.id: n};
    final nodes = _nodes.map((n) => '${n.label}: ${fmt(n.value)}').join(', ');
    final links = _edges
        .where((e) => byId[e.from] != null && byId[e.to] != null)
        .map((e) => '${byId[e.from]!.label} ${e.op} ${byId[e.to]!.label}')
        .join(', ');
    return links.isEmpty ? nodes : '$nodes  ·  $links';
  }

  void _saveCanvas() {
    final t = graphTotal(_nodes, _edges);
    if (!t.isFinite) {
      _snack('Fix the error (e.g. division by zero) before saving');
      return;
    }
    _entryDialog(initTitle: 'Canvas total', result: t, expr: _canvasSummary(), src: 'canvas');
  }

  // ------------------------------------------------------------------ history actions
  List<HistoryEntry> _filtered() {
    final q = _search.text.trim().toLowerCase();
    final qn = q.replaceAll(',', '');
    return _history.where((e) {
      if (_tagFilter != 0 && e.tag != _tagFilter) return false;
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.expr.toLowerCase().contains(q) ||
          fmt(e.result).replaceAll(',', '').contains(qn) ||
          plainNum(e.result).contains(qn);
    }).toList();
  }

  void _reuse(HistoryEntry e) {
    setState(() {
      if (_keypadMode) {
        final pn = plainNum(e.result).replaceAll('-', '−');
        final last = _expr.isEmpty ? '' : _expr[_expr.length - 1];
        if (_expr.isEmpty || _justEval) {
          _expr = pn;
          _justEval = false;
        } else if (_isOpCh(last) || last == '(') {
          _expr += pn;
        } else {
          _expr = pn;
        }
        _record("Reused '${e.title}' (${fmt(e.result)})");
      } else {
        final k = _nodes.length % 6;
        _nodes.add(NodeItem(_id(), e.title, e.result, _clampX(24.0 + k * 40), _clampY(24.0 + k * 50)));
        _record("Added node from ledger '${e.title}'");
      }
    });
    if (!_wide) _scaffoldKey.currentState?.closeEndDrawer();
    _snack(_keypadMode ? 'Inserted ${fmt(e.result)} into keypad' : 'Added as a node on the canvas');
  }

  void _snack(String m) {
    if (!mounted) return;
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm.showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(color: Colors.white)),
      duration: const Duration(seconds: 2),
      backgroundColor: kInk,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: al(kCyan, .4))),
    ));
  }

  String _csv() {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('Timestamp,Title,Tag,Source,Expression,Result\n');
    for (final e in _history.reversed) {
      b.writeln([
        q(e.ts.toIso8601String()),
        q(e.title),
        q(kTagNames[e.tag]),
        q(e.src),
        q(e.expr),
        q(plainNum(e.result)),
      ].join(','));
    }
    return b.toString();
  }

  String _textSummary() {
    final b = StringBuffer('NEXUS CALC 4D - History Summary (${_history.length} entries)\n');
    b.writeln('=' * 48);
    for (final e in _history.reversed) {
      b.writeln('[${_stamp(e.ts)}] ${e.title}${e.tag == 0 ? '' : ' (${kTagNames[e.tag]})'}');
      b.writeln('    ${e.expr}');
      b.writeln('    = ${fmt(e.result)}');
    }
    return b.toString();
  }

  // ------------------------------------------------------------------ dialogs
  AlertDialog _darkDialog({required Widget title, required Widget content, required List<Widget> actions}) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: al(kCyan, .4))),
      title: title,
      content: content,
      actions: actions,
    );
  }

  InputDecoration _fieldDeco(String label, {String? error, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      filled: true,
      fillColor: al(kInk, .05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: al(kInk, .15))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kCyan)),
    );
  }

  Future<void> _nodeDialog({NodeItem? node, Offset? pos}) async {
    final lc = TextEditingController(text: node?.label ?? 'Node ${_nodes.length + 1}');
    final vc = TextEditingController(text: node == null ? '' : plainNum(node.value));
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        void submit() {
          final raw = vc.text.trim().isEmpty ? '0' : vc.text;
          final v = evalExpr(raw);
          if (v == null) {
            setD(() => err = 'Enter a number or expression (e.g. 50000-1200)');
            return;
          }
          final label = lc.text.trim().isEmpty ? 'Node' : lc.text.trim();
          Navigator.pop(ctx);
          setState(() {
            if (node == null) {
              final p = pos ?? const Offset(60, 60);
              final n = NodeItem(_id(), label, v, _clampX(p.dx - kNodeW / 2), _clampY(p.dy - kNodeH / 2));
              _nodes.add(n);
              _record("Added '${n.label}' = ${fmt(v)}");
            } else {
              node.label = label;
              node.value = v;
              _record("Edited '$label' → ${fmt(v)}");
            }
          });
        }

        return _darkDialog(
          title: Text(node == null ? 'New Number Node' : 'Edit Node'),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: lc, decoration: _fieldDeco('Label (e.g. Budget)')),
              const SizedBox(height: 12),
              TextField(
                controller: vc,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onSubmitted: (_) => submit(),
                decoration: _fieldDeco('Value (e.g. 50000 or -12000)', error: err),
              ),
            ]),
          ),
          actions: [
            if (node != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _nodes.removeWhere((n) => n.id == node.id);
                    _edges.removeWhere((e) => e.from == node.id || e.to == node.id);
                    if (_linkFrom == node.id) _linkFrom = null;
                    _record("Deleted '${node.label}'");
                  });
                },
                child: const Text('Delete', style: TextStyle(color: kRed)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Save')),
          ],
        );
      }),
    );
  }

  Future<void> _edgeDialog(EdgeItem e) async {
    final a = _nodes.firstWhere((n) => n.id == e.from);
    final b = _nodes.firstWhere((n) => n.id == e.to);
    await showDialog<void>(
      context: context,
      builder: (ctx) => _darkDialog(
        title: Text("${a.label}  →  ${b.label}"),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final op in kOps)
              ChoiceChip(
                label: Text(op, style: const TextStyle(fontSize: 20)),
                selected: e.op == op,
                selectedColor: al(kCyan, .35),
                onSelected: (_) {
                  Navigator.pop(ctx);
                  setState(() {
                    e.op = op;
                    _record("Changed link '${a.label}' → '${b.label}' to $op");
                  });
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _edges.removeWhere((x) => x.id == e.id);
                _record("Removed link '${a.label}' → '${b.label}'");
              });
            },
            child: const Text('Delete link', style: TextStyle(color: kRed)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _entryDialog({HistoryEntry? existing, String? initTitle, double? result, String? expr, String src = 'keypad'}) async {
    final tc = TextEditingController(text: existing?.title ?? initTitle ?? 'Untitled');
    var tag = existing?.tag ?? 0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        void save() {
          final title = tc.text.trim().isEmpty ? 'Untitled' : tc.text.trim();
          Navigator.pop(ctx);
          setState(() {
            if (existing != null) {
              existing.title = title;
              existing.tag = tag;
            } else {
              _history.insert(
                0,
                HistoryEntry(id: _id(), title: title, expr: expr ?? '', result: result ?? 0, ts: DateTime.now(), tag: tag, src: src),
              );
            }
          });
          _persist();
        }

        return _darkDialog(
          title: Text(existing == null ? 'Save to Ledger' : 'Edit entry'),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (existing == null && result != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('Result: ${fmt(result)}',
                      style: const TextStyle(color: kCyan, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              TextField(
                controller: tc,
                autofocus: true,
                onSubmitted: (_) => save(),
                decoration: _fieldDeco('Title / note', hint: 'e.g. Shop Hisab, Salary'),
              ),
              const SizedBox(height: 16),
              const Text('Color tag', style: TextStyle(color: kGrey)),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 8, children: [
                for (var i = 0; i < kTagColors.length; i++)
                  GestureDetector(
                    onTap: () => setD(() => tag = i),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kTagColors[i],
                        border: Border.all(color: tag == i ? kInk : Colors.transparent, width: 2.5),
                        boxShadow: [softShadow(color: al(kTagColors[i], .55), blurRadius: 10)],
                      ),
                      child: i == 0 ? const Icon(Icons.block, size: 16, color: Colors.black54) : null,
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: save, child: const Text('Save')),
          ],
        );
      }),
    );
  }

  Future<void> _exportDialog() async {
    var asCsv = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final content = _history.isEmpty ? 'Nothing to export yet.' : (asCsv ? _csv() : _textSummary());
        return _darkDialog(
          title: const Text('Export History'),
          content: SizedBox(
            width: 520,
            height: 340,
            child: Column(children: [
              Row(children: [
                ChoiceChip(label: const Text('CSV'), selected: asCsv, onSelected: (_) => setD(() => asCsv = true)),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Text summary'), selected: !asCsv, onSelected: (_) => setD(() => asCsv = false)),
              ]),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: al(kInk, .05), borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    child: SelectableText(content, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            FilledButton.icon(
              onPressed: _history.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: content));
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('${asCsv ? 'CSV' : 'Text summary'} copied to clipboard - paste into Notepad/Excel and save');
                    },
              icon: const Icon(Icons.copy),
              label: Text(asCsv ? 'Copy CSV' : 'Copy text'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _confirmClearHistory() async {
    if (_history.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _darkDialog(
        title: const Text('Clear entire ledger?'),
        content: const Text('All saved calculations will be deleted permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _history.clear());
              _persist();
            },
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ BUILD
  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, c) {
        _wide = c.maxWidth >= 980;
        final drawerW = math.min(420.0, c.maxWidth * 0.92);
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: kBg,
          endDrawer: _wide
              ? null
              : Drawer(
                  width: drawerW,
                  backgroundColor: kBg,
                  child: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: _historyPanel())),
                ),
          onEndDrawerChanged: (open) {
            if (!open) _focus.requestFocus();
          },
          body: SafeArea(
            child: _wide
                ? Row(children: [
                    Expanded(child: _mainArea()),
                    SizedBox(
                      width: 390,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                        child: Glass(radius: 24, padding: const EdgeInsets.all(14), child: _historyPanel()),
                      ),
                    ),
                  ])
                : _mainArea(),
          ),
        );
      }),
    );
  }

  Widget _mainArea() {
    return Column(children: [
      _topBar(),
      Expanded(child: _keypadMode ? _keypadView() : _canvasView()),
      _timeBar(),
    ]);
  }

  Widget _topBar() {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFDCDEE3)))),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
      child: Row(children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: const Text('NEXUS CALC 4D',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 2.5, color: kInk)),
          ),
        ),
        const SizedBox(width: 8),
        _seg('Canvas', Icons.hub_outlined, !_keypadMode, () => setState(() => _keypadMode = false)),
        const SizedBox(width: 6),
        _seg('Keypad', Icons.dialpad, _keypadMode, () => setState(() => _keypadMode = true)),
        if (!_wide)
          IconButton(
            tooltip: 'Smart Ledger',
            icon: const Icon(Icons.menu_book_rounded, color: kCyan),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
      ]),
    );
  }

  Widget _seg(String label, IconData icon, bool selected, VoidCallback onTap) {
    return InkWell(
      canRequestFocus: false,
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        onTap();
        _focus.requestFocus();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? const Color(0xFFC2D4E8) : Colors.white,
          border: Border.all(color: selected ? kCyan : al(kInk, .15)),
          boxShadow: selected ? [softShadow(color: al(kCyan, .35), blurRadius: 12)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: selected ? kInk : kGrey),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 13, color: selected ? kInk : kGrey, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ CANVAS VIEW
  Widget _canvasView() {
    return Column(children: [
      _toolbar(),
      Expanded(child: _canvasBox()),
      _totalBar(),
    ]);
  }

  Widget _toolbar() {
    String hint;
    if (_tool == 'node') {
      hint = 'Tap empty space to create a node · tap a node to edit · drag to move · tap a link badge to edit it';
    } else if (_linkFrom == null) {
      hint = 'Link "$_tool": tap the SOURCE node';
    } else {
      hint = 'Now tap the TARGET node (tap the source again to cancel)';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _toolChip('node', Icons.add_circle_outline, 'Node'),
            for (final op in kOps) _toolChip(op, null, op),
            const SizedBox(width: 8),
            _actionChip(Icons.auto_awesome, 'Sample', _loadSample),
            _actionChip(Icons.delete_sweep_outlined, 'Clear', _clearCanvas),
          ]),
        ),
        const SizedBox(height: 6),
        Text(hint, style: TextStyle(fontSize: 11.5, color: _linkFrom != null ? kAmber : kGrey)),
      ]),
    );
  }

  Widget _toolChip(String id, IconData? icon, String label) {
    final sel = _tool == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            _tool = id;
            _linkFrom = null;
          });
          _focus.requestFocus();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(horizontal: icon == null ? 16 : 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: sel ? const Color(0xFFC2D4E8) : Colors.white,
            border: Border.all(color: sel ? kCyan : al(kInk, .15)),
            boxShadow: sel ? [softShadow(color: al(kPurple, .5), blurRadius: 14)] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: sel ? kCyan : kGrey), const SizedBox(width: 6)],
            Text(label, style: TextStyle(fontSize: icon == null ? 20 : 13, fontWeight: FontWeight.w700, color: kInk)),
          ]),
        ),
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          onTap();
          _focus.requestFocus();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: al(kInk, .15)),
            color: Colors.white,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: kCyan),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, color: kGrey, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _canvasBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: al(kCyan, .25)),
          ),
          child: LayoutBuilder(builder: (context, cons) {
            _canvasSize = Size(cons.maxWidth, cons.maxHeight);
            final comp = computeAll(_nodes, _edges);
            final byId = {for (final n in _nodes) n.id: n};
            final children = <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    _focus.requestFocus();
                    if (_tool == 'node') {
                      _nodeDialog(pos: d.localPosition);
                    } else if (_linkFrom != null) {
                      setState(() => _linkFrom = null);
                    }
                  },
                  child: CustomPaint(painter: CanvasPainter(_nodes, _edges)),
                ),
              ),
            ];
            if (_nodes.isEmpty) {
              children.add(const Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Tap anywhere to drop your first number node\n(e.g. "Budget: 50000"), or press ✨ Sample',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kGrey, fontSize: 15, height: 1.5),
                      ),
                    ),
                  ),
                ),
              ));
            }
            for (final e in _edges) {
              final a = byId[e.from];
              final b = byId[e.to];
              if (a == null || b == null) continue;
              final pts = edgePoints(a, b);
              final mid = Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
              children.add(Positioned(
                left: mid.dx - 16,
                top: mid.dy - 16,
                child: GestureDetector(
                  onTap: () => _edgeDialog(e),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: kCyan, width: 1.6),
                      boxShadow: [softShadow(color: al(kCyan, .6), blurRadius: 12)],
                    ),
                    child: Text(e.op, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kCyan)),
                  ),
                ),
              ));
            }
            for (final n in _nodes) {
              children.add(_nodeWidget(n, comp));
            }
            return Stack(clipBehavior: Clip.hardEdge, children: children);
          }),
        ),
      ),
    );
  }

  Widget _nodeWidget(NodeItem n, Map<String, double> comp) {
    final hasIn = _edges.any((e) => e.to == n.id);
    final c = comp[n.id] ?? n.value;
    final isSrc = _linkFrom == n.id;
    final color = isSrc ? kInk : (hasIn ? kPurple : kCyan);
    return Positioned(
      left: n.x,
      top: n.y,
      width: kNodeW,
      height: kNodeH,
      child: GestureDetector(
        onTap: () => _nodeTap(n),
        onPanUpdate: (d) {
          setState(() {
            n.x = _clampX(n.x + d.delta.dx);
            n.y = _clampY(n.y + d.delta.dy);
          });
        },
        onPanEnd: (_) => setState(() => _record("Moved '${n.label}'")),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [softShadow(color: al(color, isSrc ? .8 : .35), blurRadius: isSrc ? 24 : 16)],
          ),
          child: Glass(
            radius: 16,
            blur: 10,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            fill: Colors.white,
            border: al(color, .9),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(n.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kGrey)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(fmt(n.value), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
              ),
              if (hasIn)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('= ${fmt(c)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kCyan)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _totalBar() {
    final t = graphTotal(_nodes, _edges);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Glass(
        radius: 20,
        border: al(kCyan, .4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('LIVE TOTAL · ${_nodes.length} nodes · ${_edges.length} links',
                  style: const TextStyle(fontSize: 11, color: kGrey, letterSpacing: 1.2)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(fmt(t),
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                    )),
              ),
            ]),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kCyan, foregroundColor: Colors.white),
            onPressed: _nodes.isEmpty ? null : _saveCanvas,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Save'),
          ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ KEYPAD VIEW
  Widget _keypadView() {
    final cur = _expr.isEmpty ? null : evalExpr(_expr);
    final hasOp = _expr.length > 1 && RegExp(r'[+−×÷%(]').hasMatch(_expr.substring(1));
    final showPreview = !_justEval && cur != null && hasOp;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Column(children: [
            Flexible(
              flex: 3,
              child: Glass(
                radius: 24,
                border: al(kCyan, .35),
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton.icon(
                        onPressed: cur == null
                            ? null
                            : () => _entryDialog(initTitle: 'Quick Calc', result: cur, expr: _expr, src: 'keypad'),
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Save as…'),
                      ),
                    ]),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(_expr.isEmpty ? '0' : _expr,
                          style: TextStyle(fontSize: 34, color: _expr.isEmpty ? kGrey : kInk, fontWeight: FontWeight.w300)),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _keyErr
                          ? const Text('Invalid expression', style: TextStyle(fontSize: 22, color: kRed, fontWeight: FontWeight.w600))
                          : Text(
                              showPreview ? '= ${fmt(cur)}' : (_justEval ? 'Saved to ledger ✓' : ' '),
                              style: TextStyle(
                                fontSize: showPreview ? 44 : 18,
                                fontWeight: FontWeight.w800,
                                color: showPreview ? kCyan : kGreen,
                              ),
                            ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 7,
              child: Column(children: [
                for (final row in kRows)
                  Expanded(child: Row(children: [for (final k in row) Expanded(child: _keyBtn(k))])),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _keyBtn(String k) {
    final isNum = RegExp(r'^[0-9.]$').hasMatch(k);
    Color bg;
    Color fg = kInk;
    if (k == 'C') {
      bg = kPurple;
      fg = Colors.white;
    } else if (k == '(' || k == ')' || k == '⌫') {
      bg = kCyan;
      fg = Colors.white;
    } else if (isNum) {
      bg = const Color(0xFFE7E7EA);
    } else {
      bg = const Color(0xFFC2D4E8);
    }
    final Widget label = k == '⌫'
        ? Icon(Icons.backspace_outlined, color: fg, size: 24)
        : Text(k, style: TextStyle(fontSize: 26, fontWeight: k == '=' ? FontWeight.w700 : FontWeight.w500, color: fg));
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x332A3A5C), blurRadius: 5, offset: Offset(0, 3))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(20),
            onTap: () => _press(k),
            child: Center(child: label),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ TIME TRAVEL BAR
  Widget _timeBar() {
    final n = _timeline.length;
    final s = _timeline[_cursor];
    final live = _cursor == n - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Glass(
        radius: 20,
        border: al(kPurple, .5),
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.history_toggle_off, color: kPurple, size: 20),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: al(live ? kGreen : kAmber, .2),
                border: Border.all(color: live ? kGreen : kAmber),
              ),
              child: Text(live ? 'LIVE' : 'PAST',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: live ? kGreen : kAmber)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('#${_cursor + 1}/$n · ${s.desc} · ${_hms(s.t)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kGrey)),
            ),
            TextButton.icon(
              onPressed: _branchHere,
              icon: const Icon(Icons.call_split, size: 18, color: kPurple),
              label: const Text('Branch', style: TextStyle(color: kPurple)),
            ),
          ]),
          Row(children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'First step',
              icon: const Icon(Icons.skip_previous),
              onPressed: _cursor > 0 ? () => _goTo(0) : null,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Step back (Ctrl+Z)',
              icon: const Icon(Icons.chevron_left),
              onPressed: _cursor > 0 ? () => _goTo(_cursor - 1) : null,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: kCyan,
                  inactiveTrackColor: al(kInk, .15),
                  thumbColor: kPurple,
                  overlayColor: al(kPurple, .25),
                  trackHeight: 4,
                  activeTickMarkColor: Colors.transparent,
                  inactiveTickMarkColor: Colors.transparent,
                ),
                child: Slider(
                  min: 0,
                  max: n > 1 ? (n - 1).toDouble() : 1,
                  value: _cursor.toDouble(),
                  divisions: (n > 1 && n <= 300) ? n - 1 : null,
                  onChanged: n > 1 ? (v) => _goTo(v.round()) : null,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Step forward (Ctrl+Y)',
              icon: const Icon(Icons.chevron_right),
              onPressed: _cursor < n - 1 ? () => _goTo(_cursor + 1) : null,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Latest step',
              icon: const Icon(Icons.skip_next),
              onPressed: _cursor < n - 1 ? () => _goTo(n - 1) : null,
            ),
          ]),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ HISTORY PANEL
  Widget _historyPanel() {
    final list = _filtered();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.menu_book_rounded, color: kCyan),
        const SizedBox(width: 8),
        const Text('Smart Ledger', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const Spacer(),
        Text('${_history.length} saved', style: const TextStyle(color: kGrey, fontSize: 12)),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search title or amount…',
          isDense: true,
          filled: true,
          fillColor: al(kInk, .06),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _search.clear()),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: al(kInk, .15))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kCyan)),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 34,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (var i = 0; i < kTagColors.length; i++) _tagFilterChip(i),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _history.isEmpty
                        ? 'No saved calculations yet.\nPress = on the keypad or Save on the canvas.'
                        : 'No entries match your search.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kGrey, height: 1.5),
                  ),
                ),
              )
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _historyTile(list[i]),
              ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _exportDialog,
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('Export'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _history.isEmpty ? null : _confirmClearHistory,
            icon: const Icon(Icons.delete_outline, size: 18, color: kRed),
            label: const Text('Clear all', style: TextStyle(color: kRed)),
          ),
        ),
      ]),
    ]);
  }

  Widget _tagFilterChip(int i) {
    final sel = _tagFilter == i;
    final col = kTagColors[i];
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _tagFilter = i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: sel ? al(col, .25) : al(kInk, .04),
            border: Border.all(color: sel ? col : al(kInk, .15)),
          ),
          child: i == 0
              ? Text('All', style: TextStyle(fontSize: 12, color: sel ? kInk : kGrey, fontWeight: FontWeight.w600))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: col)),
                  const SizedBox(width: 6),
                  Text(kTagNames[i], style: TextStyle(fontSize: 12, color: sel ? kInk : kGrey)),
                ]),
        ),
      ),
    );
  }

  Widget _historyTile(HistoryEntry e) {
    final col = kTagColors[e.tag];
    return InkWell(
      canRequestFocus: false,
      borderRadius: BorderRadius.circular(14),
      onTap: () => _reuse(e),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
        decoration: BoxDecoration(
          color: al(kInk, .05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: al(col, e.tag == 0 ? .2 : .6)),
        ),
        child: Row(children: [
          Container(
            width: 4,
            height: 58,
            decoration: BoxDecoration(
              color: col,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [softShadow(color: al(col, .6), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(e.src == 'canvas' ? Icons.hub_outlined : Icons.dialpad, size: 13, color: kGrey),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
              Text(e.expr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kGrey)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(fmt(e.result),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kCyan)),
              ),
              Text(_stamp(e.ts), style: const TextStyle(fontSize: 10, color: kGrey)),
            ]),
          ),
          PopupMenuButton<String>(
            color: Colors.white,
            icon: const Icon(Icons.more_vert, size: 18, color: kGrey),
            onSelected: (v) {
              if (v == 'reuse') {
                _reuse(e);
              } else if (v == 'edit') {
                _entryDialog(existing: e);
              } else if (v == 'delete') {
                setState(() => _history.removeWhere((x) => x.id == e.id));
                _persist();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reuse', child: Text('Reuse result')),
              PopupMenuItem(value: 'edit', child: Text('Edit title / tag')),
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: kRed))),
            ],
          ),
        ]),
      ),
    );
  }
}
