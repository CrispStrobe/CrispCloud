/// Explicit opt-in for a non-native publication backend. Implementations must
/// establish that private staging, exact moves, and declared metadata preserve
/// the original container's access policy, including sharing/ACLs and inherited
/// provider properties. Generic rename support does not establish this promise.
abstract interface class ArchivePublicationAccessPolicy {
  bool get preservesArchiveAccessPolicy;
}
