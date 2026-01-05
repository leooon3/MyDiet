import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../providers/diet_provider.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text("Cronologia Diete")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: firestore.getDietHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Errore: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Nessuna dieta salvata in cloud."));
          }

          final diets = snapshot.data!;
          return ListView.builder(
            itemCount: diets.length,
            itemBuilder: (context, index) {
              final diet = diets[index];
              DateTime date = DateTime.now();
              if (diet['uploadedAt'] != null) {
                date = (diet['uploadedAt'] as Timestamp).toDate();
              }

              // [Replace the existing ListTile in ListView.builder with this updated version]
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.history_edu, size: 32),
                  title: Text(
                    "Dieta del ${DateFormat('dd/MM/yyyy HH:mm').format(date)}",
                  ),
                  subtitle: const Text("Tocca per ripristinare"),
                  // --- NEW: Add Delete Button ---
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text("Elimina Dieta"),
                          content: const Text(
                            "Sei sicuro di voler eliminare questa versione salvata? L'azione è irreversibile.",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text("Annulla"),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              onPressed: () async {
                                await firestore.deleteDiet(
                                  diet['id'],
                                ); // Calls the new method
                                if (!context.mounted) return;

                                Navigator.pop(c);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Dieta eliminata."),
                                  ),
                                );
                              },
                              child: const Text("Elimina"),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  // ------------------------------
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text("Ripristina Dieta"),
                        content: const Text(
                          "Vuoi sostituire la dieta attuale con questa versione salvata?",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text("Annulla"),
                          ),
                          FilledButton(
                            onPressed: () {
                              context.read<DietProvider>().loadHistoricalDiet(
                                diet,
                              );
                              Navigator.pop(c);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Dieta ripristinata!"),
                                ),
                              );
                            },
                            child: const Text("Ripristina"),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
