/// Recording state machine (FR-002).
///
/// Pure Dart; illegal transitions throw [StateTransitionError]. See
/// `specs/architecture.md` §3 for the transition table.
library;

import 'package:roadsense_logger/core/errors/app_failure.dart';

enum RecordingState {
  idle,
  preparing,
  recording,
  finalizing,
  completed,
  error,
  interrupted,
  recovering,
}

class RecordingStateMachine {
  RecordingStateMachine({RecordingState initial = RecordingState.idle})
    : _state = initial;

  RecordingState _state;

  RecordingState get state => _state;

  static const Map<RecordingState, Set<RecordingState>> _allowed = {
    RecordingState.idle: {RecordingState.preparing, RecordingState.recovering},
    RecordingState.preparing: {RecordingState.recording, RecordingState.error},
    RecordingState.recording: {
      RecordingState.finalizing,
      RecordingState.interrupted,
    },
    RecordingState.interrupted: {
      RecordingState.finalizing,
      RecordingState.error,
    },
    RecordingState.finalizing: {RecordingState.completed, RecordingState.error},
    RecordingState.recovering: {RecordingState.completed, RecordingState.error},
    RecordingState.completed: {RecordingState.idle},
    RecordingState.error: {RecordingState.idle},
  };

  /// Whether a transition from the current state to [next] is legal.
  bool canTransition(RecordingState next) =>
      _allowed[_state]?.contains(next) ?? false;

  /// Moves to [next] or throws [StateTransitionError].
  void transition(RecordingState next, {String? reason}) {
    if (!canTransition(next)) {
      throw StateTransitionError(
        'Illegal recording transition ${_state.name} -> ${next.name}'
        '${reason == null ? '' : ' ($reason)'}',
        context: {'from': _state.name, 'to': next.name, 'reason': reason},
      );
    }
    _state = next;
  }
}
