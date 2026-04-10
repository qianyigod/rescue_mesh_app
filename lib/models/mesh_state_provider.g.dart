// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mesh_state_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Mesh 状态通知器

@ProviderFor(MeshStateNotifier)
final meshStateProvider = MeshStateNotifierProvider._();

/// Mesh 状态通知器
final class MeshStateNotifierProvider
    extends $NotifierProvider<MeshStateNotifier, MeshState> {
  /// Mesh 状态通知器
  MeshStateNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'meshStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$meshStateNotifierHash();

  @$internal
  @override
  MeshStateNotifier create() => MeshStateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MeshState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MeshState>(value),
    );
  }
}

String _$meshStateNotifierHash() => r'5927881145fcf8b38ab603893f9fb3ea04a8b00d';

/// Mesh 状态通知器

abstract class _$MeshStateNotifier extends $Notifier<MeshState> {
  MeshState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<MeshState, MeshState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MeshState, MeshState>,
              MeshState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
