import 'hub_server.dart';

const List<String> knownLanguages = [
  'en',
  'ru',
  'de',
  'fr',
  'es',
  'pt',
  'uk',
  'be',
  'pl'
];
const List<String> knownRegions = ['eu', 'am', 'as', 'au'];
const List<String> knownRpLevels = ['nrp', 'lrp', 'mrp', 'hrp'];

class ServerTagInfo {
  const ServerTagInfo._();

  static final RegExp _langPattern = RegExp(
    r'\[(EN|RU|DE|FR|ES|PT|UK|BE|PL)\]',
    caseSensitive: false,
  );
  static final RegExp _adultPattern = RegExp(r'\[18\+\]', caseSensitive: false);
  static final RegExp _whitelistPattern =
      RegExp(r'\[(WL|WHITELIST)\]', caseSensitive: false);
  static final RegExp _rpPattern = RegExp(
    r'\[(NRP|LRP|MRP|HRP)\]',
    caseSensitive: false,
  );
  static final RegExp _regionPattern = RegExp(
    r'\[(EU|AM|AS|AU)\]',
    caseSensitive: false,
  );

  static String _allMatches(RegExp pattern, String name) {
    return pattern
        .allMatches(name)
        .map((match) => match.group(1) ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '')
        .toLowerCase();
  }

  static List<String> infer(HubServer server) {
    final tags = <String>{};
    var inferFromName = true;
    for (final tag in server.tags) {
      final clean = tag.trim().toLowerCase();
      if (clean.isEmpty || clean == 'no_tag_infer') {
        if (clean == 'no_tag_infer') {
          inferFromName = false;
        }
        continue;
      }
      tags.add(clean);
    }
    if (inferFromName) {
      final name = server.name;
      final lang = _allMatches(_langPattern, name);
      if (lang.isNotEmpty) {
        tags.add('lang:$lang');
      }
      final region = _allMatches(_regionPattern, name);
      if (region.isNotEmpty) {
        tags.add('region:$region');
      }
      final rp = _allMatches(_rpPattern, name);
      if (rp.isNotEmpty) {
        tags.add('rp:$rp');
      }
      if (_adultPattern.hasMatch(name)) {
        tags.add('18+');
      }
      if (_whitelistPattern.hasMatch(name)) {
        tags.add('wl');
      }
    }
    return tags.toList()..sort();
  }

  static String categoryOf(String filter) {
    if (filter == '18+' || filter == 'wl') {
      return filter;
    }
    final index = filter.indexOf(':');
    if (index <= 0) {
      return '';
    }
    return filter.substring(0, index);
  }

  static String filterLabel(String filter) {
    switch (filter) {
      case '18+':
        return '18+';
      case 'wl':
        return 'Вайтлист';
    }
    final category = categoryOf(filter);
    final value = filter.substring(filter.indexOf(':') + 1);
    switch (category) {
      case 'lang':
        return 'Язык: ${value.toUpperCase()}';
      case 'region':
        return 'Регион: ${value.toUpperCase()}';
      case 'rp':
        return 'RP: ${value.toUpperCase()}';
      default:
        return filter;
    }
  }

  static List<String> availableFilters(List<HubServer> servers) {
    final languages = <String>{};
    final regions = <String>{};
    final rpLevels = <String>{};
    var adult = false;
    var whitelist = false;
    for (final server in servers) {
      for (final tag in infer(server)) {
        final category = categoryOf(tag);
        switch (category) {
          case 'lang':
            languages.add(tag);
          case 'region':
            regions.add(tag);
          case 'rp':
            rpLevels.add(tag);
          case '18+':
            adult = true;
          case 'wl':
            whitelist = true;
        }
      }
    }
    List<String> sorted(List<String> values) => values.toList()..sort();
    return [
      if (adult) '18+',
      if (whitelist) 'wl',
      ...sorted(languages),
      ...sorted(regions),
      ...sorted(rpLevels),
    ];
  }
}
