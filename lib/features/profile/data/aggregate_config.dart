/// Combines the normalized, cached sing-box configs; never downloads subscriptions.
/// Only server definitions are imported. Routing/DNS use the app's global settings.
Map<String, dynamic> aggregateConfig(
  List<({String id, String name, Map<String, dynamic> config})> sources, {
  required String strategy,
}) {
  final outbounds = <Map<String, dynamic>>[];
  final endpoints = <Map<String, dynamic>>[];
  final candidates = <String>[];
  const groups = {'selector', 'urltest', 'balancer', 'block', 'dns'};

  for (final source in sources) {
    final nodes = [
      ...((source.config['outbounds'] as List?) ?? []).cast<Map<String, dynamic>>(),
      ...((source.config['endpoints'] as List?) ?? []).cast<Map<String, dynamic>>(),
    ];
    final names = <String, String>{};
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (groups.contains(node['type'])) continue;
      final tag = node['tag'] as String? ?? '';
      if (tag.isNotEmpty && names.containsKey(tag)) {
        throw FormatException('Duplicate server tag in ${source.name}');
      }
      // IDs prevent collisions even when providers and servers share names.
      names[tag.isEmpty ? '#$i' : tag] = '${source.name} / ${tag.isEmpty ? i : tag} [${source.id}:$i] §hide§';
    }
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (groups.contains(node['type'])) continue;
      final tag = node['tag'] as String? ?? '';
      final renamed = names[tag.isEmpty ? '#$i' : tag]!;
      final copy = <String, dynamic>{...node, 'tag': renamed};
      final detour = node['detour'] as String?;
      if (detour != null && detour.isNotEmpty) {
        if (!names.containsKey(detour)) {
          throw FormatException('Unsupported server detour in ${source.name}');
        }
        copy['detour'] = names[detour];
      }
      final isEndpoint = i >= ((source.config['outbounds'] as List?)?.length ?? 0);
      (isEndpoint ? endpoints : outbounds).add(copy);
      if (node['type'] != 'direct' && !tag.contains('§hide§')) candidates.add(renamed);
    }
  }
  if (candidates.isEmpty) throw const FormatException('No usable servers across subscriptions');
  // A single visible group makes the core select this algorithm by default,
  // including after hot reload. Hidden server definitions remain its members.
  outbounds.insert(0, {
    'type': 'balancer',
    'tag': 'All subscriptions',
    'outbounds': candidates,
    'strategy': strategy,
    'delay_acceptable_ratio': 2,
    'tolerance': 1,
    'interrupt_exist_connections': true,
  });
  return {'outbounds': outbounds, if (endpoints.isNotEmpty) 'endpoints': endpoints};
}
