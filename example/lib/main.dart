// Minimal example for `applaudiq_embed`. A full runnable example (manual + auto login + SSO, with
// a mint client and native scheme registration) lives in the applaudiq-sdk-example repo under
// native-integration/flutter.
import 'package:applaudiq_embed/applaudiq_embed.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Applaud IQ embed')),
        body: const ApplaudIQEmbed(
          // 👉 Replace with your publishable key + portal origin (HR portal → Embed SDK Keys / Admin).
          config: EmbedConfig(
            key: 'pk_live_xxxxxxxxxxxxxxxxxxxxxxxx',
            ssoCallback: 'myapp://sso-callback',
          ),
          mode: ApplaudIQMode.manual,
        ),
      ),
    );
  }
}
