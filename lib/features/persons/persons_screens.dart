// STUB — replaced during port.
import 'package:flutter/material.dart';

class ManagePersonsScreen extends StatelessWidget {
  const ManagePersonsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('ManagePersonsScreen')));
}

class PersonDetailScreen extends StatelessWidget {
  final String personId;
  const PersonDetailScreen({super.key, required this.personId});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('PersonDetailScreen')));
}
