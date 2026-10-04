import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/main.dart';

void main() {
  testWidgets('EzMVMobileApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EzMVMobileApp());
    expect(find.text('Home'), findsWidgets);
  });
}
