import '../l10n/strings.dart';
import 'hub_server.dart';

class ServerTagInfo {
  const ServerTagInfo._();

  static final RegExp _bracketTags = RegExp(r'\[(.*?)\]');

  static List<String> infer(HubServer server) {
    final tags = <String>{};
    var noInfer = false;
    for (final tag in server.tags) {
      final clean = tag.trim().toLowerCase();
      if (clean.isEmpty) {
        continue;
      }
      if (clean == 'no_tag_infer') {
        noInfer = true;
      }
      tags.add(clean);
    }
    if (noInfer) {
      return tags.where((tag) => tag != 'no_tag_infer').toList()..sort();
    }
    final bracket = _bracketTags
        .allMatches(server.name)
        .map((match) => (match.group(1) ?? '').trim().toLowerCase())
        .toSet();
    final hasLang = tags.any((tag) => tag.startsWith('lang:'));
    if (!hasLang) {
      if (bracket.contains('en')) {
        tags.add('lang:en');
      } else if (bracket.contains('ru') || bracket.contains('rus')) {
        tags.add('lang:ru');
      }
    }
    if (!tags.contains('18+')) {
      if (bracket.contains('18+') ||
          bracket.contains('+18') ||
          bracket.contains('18') ||
          bracket.contains('erp')) {
        tags.add('18+');
      }
    }
    final hasRp = tags.any((tag) => tag.startsWith('rp:'));
    if (!hasRp) {
      if (bracket.contains('nrp')) {
        tags.add('rp:none');
      } else if (bracket.contains('lrp')) {
        tags.add('rp:low');
      } else if (bracket.contains('mrp')) {
        tags.add('rp:medium');
      } else if (bracket.contains('hrp')) {
        tags.add('rp:high');
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

  static String filterLabel(String filter, S s) {
    switch (filter) {
      case '18+':
        return filter;
      case 'wl':
        return s.whitelist;
    }
    final category = categoryOf(filter);
    final value = filter.substring(filter.indexOf(':') + 1);
    switch (category) {
      case 'lang':
        return '${s.langPrefix}${value.toUpperCase()}';
      case 'region':
        return '${s.regionPrefix}${value.toUpperCase()}';
      case 'rp':
        return rpLabel(value, s);
      default:
        return filter;
    }
  }

  static String rpLabel(String value, S s) {
    switch (value) {
      case 'none':
        return s.rpNone;
      case 'low':
      case 'lrp':
        return s.rpLow;
      case 'med':
      case 'medium':
        return s.rpMedium;
      case 'high':
      case 'hrp':
        return s.rpHigh;
      default:
        return value.toUpperCase();
    }
  }

  static const List<String> fixedRpFilters = [
    'rp:none',
    'rp:low',
    'rp:medium',
    'rp:high',
  ];

  static const List<String> fixedLangFilters = ['lang:ru', 'lang:en'];

  static List<String> availableFilters(List<HubServer> servers) {
    final languages = <String>{...fixedLangFilters};
    final regions = <String>{};
    final rpLevels = <String>{...fixedRpFilters};
    final extras = <String>{};
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
          default:
            if (category.isNotEmpty) {
              extras.add(tag);
            }
        }
      }
    }
    List<String> sorted(Set<String> values) => values.toList()..sort();
    final extraRp =
        rpLevels.where((value) => !fixedRpFilters.contains(value)).toList()
          ..sort();
    return [
      ...sorted(languages),
      ...sorted(regions),
      ...fixedRpFilters,
      ...extraRp,
      ...sorted(extras),
    ];
  }
}
