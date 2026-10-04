import 'package:flutter_test/flutter_test.dart';
import 'package:tv_app/main.dart';

void main() {
  testWidgets('EzMVApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EzMVApp());
    expect(find.byType(EzMVApp), findsOneWidget);
  });
}
