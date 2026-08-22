import 'package:flutter_test/flutter_test.dart';
import 'package:rayzi_admin/app.dart';

void main() {
  testWidgets('admin app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const AdminApp());
    expect(find.text('Rayzi Admin'), findsWidgets);
  });
}
