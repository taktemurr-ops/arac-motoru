/// Küçük ifade çözücü: + − × ÷ ^ % !, parantez, sin cos tan asin acos
/// atan sqrt cbrt ln log abs exp, π ve e, x değişkeni. Gizli çarpma
/// (2π, 3(4+1), 2x) desteklenir.
library;

import 'dart:math' as math;

class ExprError implements Exception {
  final String message;
  const ExprError(this.message);
  @override
  String toString() => message;
}

class Expr {
  final String src;
  final bool degrees;
  int _i = 0;
  double _x = 0;
  late final List<_Tok> _t = _lex(src);

  Expr(this.src, {this.degrees = false});

  /// İfadeyi [x] için hesaplar.
  double eval([double x = 0]) {
    _i = 0;
    _x = x;
    final v = _expr();
    if (_i < _t.length) throw const ExprError('syntax');
    return v;
  }

  static double? tryEval(String s, {bool degrees = false, double x = 0}) {
    try {
      final v = Expr(s, degrees: degrees).eval(x);
      return v.isNaN ? null : v;
    } catch (_) {
      return null;
    }
  }

  _Tok? get _peek => _i < _t.length ? _t[_i] : null;

  bool _is(String op) => _peek?.op == op;

  double _expr() {
    var v = _term();
    while (_is('+') || _is('-')) {
      final op = _t[_i++].op;
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _unary();
    while (true) {
      if (_is('*') || _is('/')) {
        final op = _t[_i++].op;
        final r = _unary();
        v = op == '*' ? v * r : v / r;
      } else if (_peek != null && (_peek!.num != null || _peek!.id != null || _is('('))) {
        v = v * _unary();
      } else {
        return v;
      }
    }
  }

  double _unary() {
    if (_is('-')) {
      _i++;
      return -_unary();
    }
    if (_is('+')) {
      _i++;
      return _unary();
    }
    return _power();
  }

  double _power() {
    final b = _postfix();
    if (_is('^')) {
      _i++;
      return math.pow(b, _unary()).toDouble();
    }
    return b;
  }

  double _postfix() {
    var v = _primary();
    while (_is('!') || _is('%')) {
      final op = _t[_i++].op;
      v = op == '!' ? _fact(v) : v / 100;
    }
    return v;
  }

  double _primary() {
    final t = _peek;
    if (t == null) throw const ExprError('end');
    if (t.num != null) {
      _i++;
      return t.num!;
    }
    if (t.op == '(') {
      _i++;
      final v = _expr();
      if (!_is(')')) throw const ExprError(')');
      _i++;
      return v;
    }
    if (t.id != null) {
      _i++;
      final id = t.id!;
      switch (id) {
        case 'pi':
        case 'π':
          return math.pi;
        case 'e':
          return math.e;
        case 'x':
          return _x;
      }
      final arg = _unary();
      final k = degrees ? math.pi / 180 : 1.0;
      switch (id) {
        case 'sin':
          return math.sin(arg * k);
        case 'cos':
          return math.cos(arg * k);
        case 'tan':
          return math.tan(arg * k);
        case 'asin':
          return math.asin(arg) / k;
        case 'acos':
          return math.acos(arg) / k;
        case 'atan':
          return math.atan(arg) / k;
        case 'sqrt':
        case '√':
          return math.sqrt(arg);
        case 'cbrt':
          return arg < 0 ? -math.pow(-arg, 1 / 3).toDouble() : math.pow(arg, 1 / 3).toDouble();
        case 'ln':
          return math.log(arg);
        case 'log':
          return math.log(arg) / math.ln10;
        case 'abs':
          return arg.abs();
        case 'exp':
          return math.exp(arg);
      }
      throw ExprError(id);
    }
    throw ExprError(t.op ?? '?');
  }

  static double _fact(double v) {
    if (v < 0 || v != v.roundToDouble()) return double.nan;
    if (v > 170) return double.infinity;
    var r = 1.0;
    for (var i = 2; i <= v; i++) {
      r *= i;
    }
    return r;
  }

  static List<_Tok> _lex(String s) {
    final out = <_Tok>[];
    var i = 0;
    s = s
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .replaceAll('·', '*')
        .replaceAll(',', '.')
        .toLowerCase();
    while (i < s.length) {
      final c = s[i];
      if (c == ' ') {
        i++;
        continue;
      }
      if ('0123456789.'.contains(c)) {
        var j = i;
        while (j < s.length && '0123456789.'.contains(s[j])) {
          j++;
        }
        if (j < s.length && s[j] == 'e' && j + 1 < s.length && '0123456789-+'.contains(s[j + 1])) {
          var k = j + 1;
          if ('+-'.contains(s[k])) k++;
          if (k < s.length && '0123456789'.contains(s[k])) {
            j = k;
            while (j < s.length && '0123456789'.contains(s[j])) {
              j++;
            }
          }
        }
        final v = double.tryParse(s.substring(i, j));
        if (v == null) throw const ExprError('number');
        out.add(_Tok(num: v));
        i = j;
        continue;
      }
      if (c == 'π' || c == '√') {
        out.add(_Tok(id: c));
        i++;
        continue;
      }
      if (RegExp(r'[a-z]').hasMatch(c)) {
        var j = i;
        while (j < s.length && RegExp(r'[a-z]').hasMatch(s[j])) {
          j++;
        }
        var word = s.substring(i, j);
        // "2x" ya da "xsin" gibi bitişik yazımları ayır.
        while (word.isNotEmpty) {
          final m = _ids.firstWhere((id) => word.startsWith(id), orElse: () => '');
          if (m.isEmpty) throw ExprError(word);
          out.add(_Tok(id: m));
          word = word.substring(m.length);
        }
        i = j;
        continue;
      }
      if ('+-*/^()!%'.contains(c)) {
        out.add(_Tok(op: c));
        i++;
        continue;
      }
      throw ExprError(c);
    }
    return out;
  }

  static const _ids = ['asin', 'acos', 'atan', 'sqrt', 'cbrt', 'sin', 'cos', 'tan', 'abs', 'exp', 'log', 'ln', 'pi', 'e', 'x'];
}

class _Tok {
  final double? num;
  final String? id;
  final String? op;
  const _Tok({this.num, this.id, this.op});
}
