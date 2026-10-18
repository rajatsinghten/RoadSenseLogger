/// Rolling-window rate measurement over monotonic event timestamps.
///
/// Rates are computed from *measured* event timing — never copied from
/// requested settings (NFR-005).
library;

class RateMeter {
  RateMeter({this.windowCapacity = 2048});

  /// Maximum number of recent timestamps kept for the live rate.
  final int windowCapacity;

  final List<int> _window = <int>[];

  /// Total events seen (including those outside the window).
  int count = 0;

  int? _firstTs;
  int? _lastTs;

  void add(int timestampNs) {
    count++;
    _firstTs ??= timestampNs;
    _lastTs = timestampNs;
    _window.add(timestampNs);
    if (_window.length > windowCapacity) {
      _window.removeAt(0);
    }
  }

  /// Rate over the rolling window in Hz, or null before two events.
  double? get liveRateHz {
    if (_window.length < 2) return null;
    final spanNs = _window.last - _window.first;
    if (spanNs <= 0) return null;
    return (_window.length - 1) * 1e9 / spanNs;
  }

  /// Average rate over the whole recording in Hz, or null before two events.
  double? get averageRateHz {
    if (count < 2 || _firstTs == null || _lastTs == null) return null;
    final spanNs = _lastTs! - _firstTs!;
    if (spanNs <= 0) return null;
    return (count - 1) * 1e9 / spanNs;
  }
}
