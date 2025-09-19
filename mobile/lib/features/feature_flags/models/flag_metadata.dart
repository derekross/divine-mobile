// ABOUTME: Metadata container for feature flag information
// ABOUTME: Provides comprehensive flag status including overrides and build defaults

import 'package:openvine/features/feature_flags/models/feature_flag.dart';

class FlagMetadata {
  const FlagMetadata({
    required this.flag,
    required this.isEnabled,
    required this.hasUserOverride,
    required this.buildDefault,
  });

  final FeatureFlag flag;
  final bool isEnabled;
  final bool hasUserOverride;
  final bool buildDefault;
}
