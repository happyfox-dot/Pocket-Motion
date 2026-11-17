// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dji_live_gallery/src/watermark.dart';
import 'package:dji_live_gallery/src/watermark_controls.dart';

void main() {
  testWidgets('watermark can be enabled, placed, and locked during export', (
    tester,
  ) async {
    var settings = const WatermarkSettings();
    var locked = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 268,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return WatermarkControls(
                  settings: settings,
                  locked: locked,
                  onChanged: (value) => setState(() => settings = value),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('水印位置'), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(settings.enabled, isTrue);
    expect(find.text(WatermarkSettings.text), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<WatermarkPosition>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('左上角').last);
    await tester.pumpAndSettle();
    expect(settings.position, WatermarkPosition.topLeft);
    expect(settings.outputSuffix, '_WM_TL');
    rebuild(() => locked = true);
    await tester.pump();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(
      tester
          .widget<DropdownButton<WatermarkPosition>>(
            find.byType(DropdownButton<WatermarkPosition>),
          )
          .onChanged,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
