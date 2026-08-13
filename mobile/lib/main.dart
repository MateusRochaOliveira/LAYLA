import 'package:flutter/material.dart';
import 'views/home_page.dart';

void main() {
  runApp(const LaylaApp());
}

class LaylaApp extends StatelessWidget {
  const LaylaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LAYLA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}