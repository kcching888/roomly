import 'package:flutter_test/flutter_test.dart';

import 'package:roomly/main.dart';

void main() {
  testWidgets('Roomly home route builds', (tester) async {
    await tester.pumpWidget(const RoomlyApp());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Welcome to Roomly.\n\n'
        'Open the booking link provided by your organization.',
      ),
      findsOneWidget,
    );
  });
}