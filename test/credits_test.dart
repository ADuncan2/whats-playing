// Settings -> Credits and licences: the required TMDB and TfL notices are there.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whats_playing/features/settings/credits_screen.dart';

void main() {
  testWidgets('Credits shows the TMDB notice and the TfL credit', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Powered by TfL Open Data'), findsOneWidget);
  });
}
