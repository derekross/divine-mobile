// ABOUTME: Settings screen for managing feature flag states and overrides
// ABOUTME: Provides UI for toggling flags, viewing descriptions, and resetting to defaults

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/features/feature_flags/models/feature_flag.dart';
import 'package:openvine/features/feature_flags/providers/feature_flag_providers.dart';

class FeatureFlagScreen extends ConsumerWidget {
  const FeatureFlagScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(featureFlagServiceProvider);
    final state = ref.watch(featureFlagStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feature Flags'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Reset all flags to defaults',
            onPressed: () async {
              await service.resetAllFlags();
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: FeatureFlag.values.length,
        itemBuilder: (context, index) {
          final flag = FeatureFlag.values[index];
          final isEnabled = state[flag] ?? false;
          final hasUserOverride = service.hasUserOverride(flag);

          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: ListTile(
              title: Text(
                flag.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: hasUserOverride
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              subtitle: Text(
                flag.description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasUserOverride)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Icon(
                        Icons.edit,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  Switch(
                    value: isEnabled,
                    onChanged: (value) async {
                      await service.setFlag(flag, value);
                    },
                    activeColor: hasUserOverride
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  if (hasUserOverride)
                    IconButton(
                      icon: const Icon(Icons.undo, size: 20),
                      tooltip: 'Reset to default',
                      onPressed: () async {
                        await service.resetFlag(flag);
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
