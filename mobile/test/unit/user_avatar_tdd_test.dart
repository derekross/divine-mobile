import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/widgets/user_avatar.dart';

void main() {
  testWidgets('UserAvatar shows fallback initial when image fails', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserAvatar(
            imageUrl: 'https://invalid.example.invalid/nonexistent.jpg',
            name: 'Foo',
            size: 40,
          ),
        ),
      ),
    );

    // Placeholder should render initial from name 'Foo' => 'F'
    expect(find.text('F'), findsOneWidget);
  });
}

