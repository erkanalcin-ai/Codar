/// Defers layout work while a geometry slider is being dragged and keeps only
/// the newest revision for the single exact reflow after the gesture.
class ReaderReflowCoalescer {
  bool _interacting = false;
  int? _pendingRevision;

  void beginInteraction() => _interacting = true;

  int? request(int revision) {
    if (_interacting) {
      _pendingRevision = revision;
      return null;
    }
    return revision;
  }

  void defer(int revision) {
    if (_interacting) _pendingRevision = revision;
  }

  int? endInteraction() {
    _interacting = false;
    final revision = _pendingRevision;
    _pendingRevision = null;
    return revision;
  }
}
