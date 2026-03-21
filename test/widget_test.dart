import 'package:flutter_test/flutter_test.dart';

import 'package:rescue_mesh_app/main.dart';

void main() {
  testWidgets('Rescue shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const RescueApp());

    expect(find.text('Rescue Mesh'), findsOneWidget);
    expect(find.text('SOS'), findsAtLeastNWidgets(1));
  });
}
