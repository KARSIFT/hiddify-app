/// Combines the normalized, cached sing-box configs; never downloads subscriptions.
/// Only server definitions are imported. Routing/DNS use the app's global settings.
({Map<String, dynamic> config, String outboundTag}) aggregateConfig(
  List<({String id, String name, Map<String, dynamic> config})> sources, {
  required String strategy,
}) {
  final outbounds = <Map<String, dynamic>>[];
  final endpoints = <Map<String, dynamic>>[];
  final candidates = <String>[];
  final useNativeLowest = strategy == 'lowest-delay';
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
      final isCandidate = node['type'] != 'direct' && !tag.contains('§hide§');
      final hidden = useNativeLowest && isCandidate ? '' : ' §hide§';
      names[tag.isEmpty ? '#$i' : tag] = '${source.name} / ${tag.isEmpty ? i : tag} [${source.id}:$i]$hidden';
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
  if (!useNativeLowest) {
    outbounds.insert(0, {
      'type': 'balancer',
      'tag': 'All subscriptions',
      'outbounds': candidates,
      'strategy': strategy,
      'delay_acceptable_ratio': 2,
      'tolerance': 1,
      'interrupt_exist_connections': true,
    });
  }
  // Visible servers let the core build its normal Lowest group ("lowest") over
  // the entire pool. Select it explicitly: the core defaults to Balance and
  // may restore a cached selection when connecting or hot reloading.
  return (
    config: {'outbounds': outbounds, if (endpoints.isNotEmpty) 'endpoints': endpoints},
    outboundTag: useNativeLowest ? (candidates.length > 1 ? 'lowest' : candidates.single) : 'All subscriptions',
  );
}
