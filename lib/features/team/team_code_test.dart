import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_connect/features/team/data/team_repository.dart';

void main() {
  test('team code has 6 characters from the safe alphabet', () {
    for (var i = 0; i < 500; i++) {
      final code = TeamRepository.generateTeamCode();
      expect(code, hasLength(TeamRepository.codeLength));
      for (final character in code.split('')) {
        expect(TeamRepository.codeAlphabet, contains(character));
      }
    }
  });

  test('alphabet has no look-alike characters', () {
    for (final character in ['0', 'O', '1', 'I', 'L']) {
      expect(TeamRepository.codeAlphabet.contains(character), isFalse);
    }
  });

  test('codes are random', () {
    final codes = {
      for (var i = 0; i < 200; i++) TeamRepository.generateTeamCode(),
    };
    expect(codes.length, greaterThan(190));
  });

  test('normalizeCode trims and upper-cases', () {
    expect(TeamRepository.normalizeCode('  ab12cd '), 'AB12CD');
  });
}
