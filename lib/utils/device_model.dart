// Device model keys from a product name, for "more parts for this model".
//
//   "Fully Tested Motherboard For iPhone 12 Pro Max ..."
//      -> [(key: "iphone 12 pro max", series: "iphone 12")]
//
// Pro / Pro Max / Plus / mini / Max / Lite / e / s / FE / Ultra / + are part
// of the model: iphone 12, iphone 12 pro, iphone 12 pro max and iphone 12
// mini are four different keys. The series key drops them.
//
// Mirror of functions/catalog/deviceModel.js. Both are checked against
// test/fixtures/device_model_cases.json — keep them in step.

typedef DeviceModel = ({String key, String series});

const _suffixWords = {'pro', 'max', 'plus', 'mini', 'lite', 'ultra', 'fe'};
const _listNoise = {'4g', '5g', 'and', '&', 'galaxy'};

final Set<String> _iphoneModels = () {
  final set = <String>{
    '6', '6 plus', '6s', '6s plus', '7', '7 plus', '8', '8 plus', //
    'se', 'se 2020', 'se 2022', 'x', 'xr', 'xs', 'xs max',
    '11', '11 pro', '11 pro max', '16e', '17 air',
  };
  for (final n in [12, 13]) {
    for (final s in ['', ' mini', ' pro', ' pro max']) {
      set.add('$n$s');
    }
  }
  for (final n in [14, 15, 16]) {
    for (final s in ['', ' plus', ' pro', ' pro max']) {
      set.add('$n$s');
    }
  }
  for (final s in ['', ' pro', ' pro max']) {
    set.add('17$s');
  }
  return set;
}();

String _replace(String s, String pattern, String Function(Match m) to) =>
    s.replaceAllMapped(RegExp(pattern), to);

/// Lower-cased words, with glued suffixes split: "12ProMax" -> 12 pro max.
List<String> deviceModelTokens(String? name) {
  var s = (name ?? '').toLowerCase();
  s = s.replaceAll(RegExp(r'''[/,|()\[\]{}:;!?"']'''), ' ');
  s = _replace(s, r'\bse(20(?:20|22))\b', (m) => 'se ${m[1]}');
  s = _replace(s, r'\bs(\d{2})u\b', (m) => 's${m[1]} ultra');
  // "+" after a model or "pro" means Plus; "AAA+++" (a grade) stays junk.
  s = _replace(s, r'(\d|\bpro)\+', (m) => '${m[1]} plus ');
  s = s.replaceAll(RegExp(r'promax\b'), 'pro max');
  s = _replace(s, r'(\d[se]?)(pro|max|plus|mini|lite|ultra|fe)\b', (m) => '${m[1]} ${m[2]}');
  s = _replace(s, r'\b(cyber)(\d+)\b', (m) => '${m[1]} ${m[2]}');
  return s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
}

bool _hasLetterSuffix(String base) =>
    RegExp(r'\d[a-z]$').hasMatch(base) || base == 'xr' || base == 'xs';

String _at(List<String> tokens, int i) => i >= 0 && i < tokens.length ? tokens[i] : '';

/// Suffix words right after a model: "pro max" is one suffix, other words
/// each give a model of their own ("s21 plus ultra" -> s21 plus, s21 ultra).
({List<String> suffixes, int next}) _readSuffixes(List<String> tokens, int start) {
  final words = <String>[];
  var i = start;
  while (i < tokens.length && _suffixWords.contains(tokens[i])) {
    words.add(tokens[i++]);
  }
  final suffixes = <String>[];
  for (var j = 0; j < words.length; j++) {
    final following = j + 1 < words.length ? words[j + 1] : '';
    if (words[j] == 'pro' && (following == 'max' || following == 'plus')) {
      suffixes.add('pro $following');
      j++;
    } else {
      suffixes.add(words[j]);
    }
  }
  return (suffixes: suffixes, next: i);
}

String _seriesOf(String prefix, String base) {
  var b = base;
  if (prefix == 'iphone') {
    if (b == 'xr' || b == 'xs') {
      b = 'x';
    } else if (b.startsWith('se')) {
      b = 'se';
    }
  }
  b = _replace(b, r'^([a-z]?\d+)[a-z]$', (m) => m[1]!);
  return '$prefix $b';
}

typedef _Add = void Function(String key, String series);

/// A suffixed model that ends a list of plain ones names the plain model too:
/// "X XR XS Max" lists x, xr, xs and xs max; "S21 S20 Ultra" s20 and s20 ultra.
void _addModel(_Add add, String prefix, String base, List<String> suffixes, bool inList) {
  final series = _seriesOf(prefix, base);
  if (suffixes.isEmpty || inList) add('$prefix $base', series);
  for (final sfx in suffixes) {
    add('$prefix $base $sfx', series);
  }
}

/// Models after a family word ("nova 2 2i 3e", "redmi note 9 10 7 pro") until
/// a word that is neither a model, a suffix nor list noise.
int _readRun(List<String> tokens, int start, String prefix, RegExp modelRe, _Add add) {
  var i = start;
  var inList = false;
  while (i < tokens.length) {
    final t = tokens[i];
    if (_listNoise.contains(t)) {
      i++;
      continue;
    }
    if (!modelRe.hasMatch(t)) break;
    final r = _readSuffixes(tokens, i + 1);
    final usable = _hasLetterSuffix(t) ? const <String>[] : r.suffixes;
    _addModel(add, prefix, t, usable, inList);
    inList = r.suffixes.isEmpty;
    i = r.next;
  }
  return i;
}

void _apple(List<String> tokens, _Add add) {
  // Whole name: listings put models after "For" with no "iPhone" ("for
  // 6Plus 6sPlus") and between screen words ("LCD 11 Pro MAX Touch").
  final baseRe = RegExp(r'^(?:[678]s?|x|xr|xs|se|1[1-7]e?)$');
  var plainEnd = -1;
  for (var i = 0; i < tokens.length; i++) {
    final start = i;
    var t = tokens[i];
    if (!baseRe.hasMatch(t)) continue;
    if (t == 'se' && RegExp(r'^20(20|22)$').hasMatch(_at(tokens, i + 1))) {
      t = 'se ${tokens[++i]}';
    }
    if (t == 'x' &&
        _at(tokens, i - 1) != 'iphone' &&
        !baseRe.hasMatch(_at(tokens, i - 1)) &&
        !baseRe.hasMatch(_at(tokens, i + 1))) {
      continue; // a lone "x" is a dimension/"x2", not an iPhone
    }
    final r = _readSuffixes(tokens, i + 1);
    final valid = r.suffixes.where((s) => _iphoneModels.contains('$t $s')).toList();
    if (!_iphoneModels.contains(t) && valid.isEmpty) continue;
    final inList = plainEnd == start && _iphoneModels.contains(t);
    _addModel(add, 'iphone', t, valid, inList);
    if (valid.isEmpty) plainEnd = r.next;
    i = r.next - 1;
  }
}

void _samsung(List<String> tokens, _Add add) {
  var plainEnd = -1;
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (RegExp(r'^[asmfj]\d{1,2}[se]?$').hasMatch(t)) {
      final r = _readSuffixes(tokens, i + 1);
      final usable = _hasLetterSuffix(t) ? const <String>[] : r.suffixes;
      _addModel(add, 'samsung', t, usable, plainEnd == i);
      if (usable.isEmpty) plainEnd = r.next;
      i = r.next - 1;
    } else if (RegExp(r'^s\d{1,2}fe$').hasMatch(t)) {
      final base = t.substring(0, t.length - 2);
      add('samsung $base fe', _seriesOf('samsung', base));
    } else if (t == 'note') {
      i = _readRun(tokens, i + 1, 'samsung note', RegExp(r'^\d{1,2}$'), add) - 1;
    } else if (t == 'tab' && RegExp(r'^(a\d?|s\d{0,2})$').hasMatch(_at(tokens, i + 1))) {
      final model = tokens[i + 1];
      final sizeToken = _at(tokens, i + 2);
      final size = RegExp(r'^\d{1,2}\.\d$').hasMatch(sizeToken) ? ' $sizeToken' : '';
      add('samsung tab $model$size', 'samsung tab $model');
    }
  }
}

void _huawei(List<String> tokens, _Add add) {
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == 'nova') {
      i = _readRun(tokens, i + 1, 'huawei nova', RegExp(r'^\d{1,2}[a-z]?$'), add) - 1;
    } else if (t == 'mate') {
      i = _readRun(tokens, i + 1, 'huawei mate', RegExp(r'^\d{1,2}$'), add) - 1;
    } else if (RegExp(r'^[py]\d{1,2}$').hasMatch(t)) {
      i = _readRun(tokens, i, 'huawei', RegExp(r'^[py]\d{1,2}$'), add) - 1;
    }
  }
}

void _redmi(List<String> tokens, _Add add) {
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] != 'redmi') continue;
    final note = _at(tokens, i + 1) == 'note';
    i = _readRun(tokens, i + (note ? 2 : 1), note ? 'redmi note' : 'redmi',
            RegExp(r'^(?:[ac]?\d{1,2}[a-z]?)$'), add) -
        1;
  }
}

void _realme(List<String> tokens, _Add add) {
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] != 'realme') continue;
    // "C11 2020" (was "C11(2020)"): the year is not a model.
    final filtered = [
      for (var j = 0; j < tokens.length; j++)
        j > i && RegExp(r'^20\d\d$').hasMatch(tokens[j]) ? 'and' : tokens[j],
    ];
    i = _readRun(filtered, i + 1, 'realme', RegExp(r'^(?:[c]?\d{1,2})$'), add) - 1;
  }
}

void _moto(List<String> tokens, _Add add) {
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] != 'moto' && tokens[i] != 'motorola') continue;
    i = _readRun(tokens, i + 1, 'moto', RegExp(r'^[ge]\d{1,3}$'), add) - 1;
  }
}

void _other(List<String> tokens, _Add add) {
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    final next = _at(tokens, i + 1);
    if (t == 'cyber' && _at(tokens, i - 1) == 'hotwav' && RegExp(r'^\d{1,2}$').hasMatch(next)) {
      add('hotwav cyber $next', 'hotwav cyber $next');
    }
    if ((t == 'probook' || t == 'elitebook' || t == 'pavilion') &&
        RegExp(r'^\d{2,4}(-[a-z0-9]+)?$').hasMatch(next)) {
      add('hp $t $next', 'hp $t $next');
    }
    if (RegExp(r'^\d{3}$').hasMatch(t) && RegExp(r'^g\d$').hasMatch(next) && tokens.contains('hp')) {
      add('hp $t $next', 'hp $t $next');
    }
  }
}

/// Every device model the name names, in order.
List<DeviceModel> deviceModels(String? name) {
  final tokens = deviceModelTokens(name);
  final out = <DeviceModel>[];
  final seen = <String>{};
  void add(String key, String series) {
    if (seen.add(key)) out.add((key: key, series: series));
  }

  if (tokens.contains('iphone')) _apple(tokens, add);
  if (tokens.contains('samsung') || tokens.contains('galaxy')) _samsung(tokens, add);
  if (tokens.contains('huawei')) _huawei(tokens, add);
  if (tokens.contains('redmi')) _redmi(tokens, add);
  if (tokens.contains('realme')) _realme(tokens, add);
  if (tokens.contains('moto') || tokens.contains('motorola')) _moto(tokens, add);
  _other(tokens, add);
  return out;
}

/// modelKeys + modelSeries (unique), as stored on the product doc.
({List<String> modelKeys, List<String> modelSeries}) modelFieldsForName(String? name) {
  final models = deviceModels(name);
  return (
    modelKeys: [for (final m in models) m.key],
    modelSeries: {for (final m in models) m.series}.toList(),
  );
}
