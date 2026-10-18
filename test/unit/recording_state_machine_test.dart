import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/domain/recording_state_machine.dart';

void main() {
  group('RecordingStateMachine', () {
    test('starts idle', () {
      expect(RecordingStateMachine().state, RecordingState.idle);
    });

    test('follows the happy path', () {
      final machine = RecordingStateMachine();
      machine.transition(RecordingState.preparing);
      machine.transition(RecordingState.recording);
      machine.transition(RecordingState.finalizing);
      machine.transition(RecordingState.completed);
      expect(machine.state, RecordingState.completed);
    });

    test('rejects duplicate start (idle -> recording is illegal)', () {
      final machine = RecordingStateMachine();
      expect(
        () => machine.transition(RecordingState.recording),
        throwsA(isA<StateTransitionError>()),
      );
      expect(machine.state, RecordingState.idle);
    });

    test('rejects stop before recording', () {
      final machine = RecordingStateMachine();
      expect(machine.canTransition(RecordingState.finalizing), isFalse);
    });

    test('handles interruption then finalization', () {
      final machine = RecordingStateMachine();
      machine.transition(RecordingState.preparing);
      machine.transition(RecordingState.recording);
      machine.transition(RecordingState.interrupted, reason: 'camera error');
      machine.transition(RecordingState.finalizing);
      machine.transition(RecordingState.completed);
      expect(machine.state, RecordingState.completed);
    });

    test('preparing can fail to error and reset to idle', () {
      final machine = RecordingStateMachine();
      machine.transition(RecordingState.preparing);
      machine.transition(RecordingState.error, reason: 'no camera');
      machine.transition(RecordingState.idle);
      expect(machine.state, RecordingState.idle);
    });

    test('finalizing validation failure goes to error', () {
      final machine = RecordingStateMachine();
      machine.transition(RecordingState.preparing);
      machine.transition(RecordingState.recording);
      machine.transition(RecordingState.finalizing);
      machine.transition(RecordingState.error, reason: 'validation failed');
      expect(machine.state, RecordingState.error);
    });

    test('recovery path at startup', () {
      final machine = RecordingStateMachine();
      machine.transition(RecordingState.recovering);
      machine.transition(RecordingState.completed);
      expect(machine.state, RecordingState.completed);
    });

    test('cannot skip finalizing', () {
      final machine = RecordingStateMachine();
      machine.transition(RecordingState.preparing);
      machine.transition(RecordingState.recording);
      expect(machine.canTransition(RecordingState.completed), isFalse);
    });

    test('throws with context on illegal transition', () {
      final machine = RecordingStateMachine();
      expect(
        () => machine.transition(RecordingState.completed),
        throwsA(
          isA<StateTransitionError>().having(
            (e) => e.context['from'],
            'context.from',
            'idle',
          ),
        ),
      );
    });
  });
}
