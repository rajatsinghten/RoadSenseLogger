/// Seam over the native GPS collector so recorders are testable with fakes.
library;

import 'package:roadsense_logger/services/native/native_bridge.dart';

abstract interface class LocationSource {
  Stream<NativeGpsEvent> get gpsEvents;

  Future<void> startGps({required int intervalMs});

  Future<void> stopGps();
}
