import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/diet_provider.dart';
import '../models/active_swap.dart';
import '../services/api_client.dart';
import 'diet_view.dart';
import 'pantry_view.dart';
import 'shopping_list_view.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late TabController _tabController;
  final List<String> days = [
    "Lunedì",
    "Martedì",
    "Mercoledì",
    "Giovedì",
    "Venerdì",
    "Sabato",
    "Domenica",
  ];

  @override
  void initState() {
    super.initState();
    int today = DateTime.now().weekday - 1;
    _tabController = TabController(
      length: 7,
      initialIndex: today < 0 ? 0 : today,
      vsync: this,
    );
  }

  void _uploadDiet(BuildContext context) async {
    final provider = context.read<DietProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (!mounted) return;

    if (result != null) {
      try {
        await provider.uploadDiet(result.files.single.path!);
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text("Dieta caricata!")),
        );
      } catch (e) {
        if (mounted) {
          String errorMessage = "Errore sconosciuto";
          if (e is ApiException) {
            errorMessage = "Errore Server (${e.statusCode}): ${e.message}";
          } else if (e is NetworkException) {
            errorMessage = "Errore di rete. Controlla la connessione.";
          }
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _onConsume(
    BuildContext context,
    DietProvider provider,
    String name,
    String qty,
  ) {
    provider.consumeSmart(name, qty);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Hai mangiato $name! 😋"),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _onEdit(
    BuildContext context,
    DietProvider provider,
    String day,
    String mealName,
    int index,
    String currentName,
    String currentQty,
  ) {
    TextEditingController nameCtrl = TextEditingController(text: currentName);
    TextEditingController qtyCtrl = TextEditingController(text: currentQty);

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Modifica Piatto"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Nome"),
            ),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: "Quantità"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Annulla"),
          ),
          FilledButton(
            onPressed: () {
              provider.updateDietMeal(
                day,
                mealName,
                index,
                nameCtrl.text,
                qtyCtrl.text,
              );
              Navigator.pop(c);
            },
            child: const Text("Salva"),
          ),
        ],
      ),
    );
  }

  void _onSwap(
    BuildContext context,
    DietProvider provider,
    String swapKey,
    int cadCode,
  ) {
    String cadKey = cadCode.toString();
    final subs = provider.substitutions;

    if (subs == null || !subs.containsKey(cadKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nessuna alternativa trovata.")),
      );
      return;
    }

    var subData = subs[cadKey];
    List<dynamic> options = subData['options'] ?? [];

    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Alternative per ${subData['name']}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                separatorBuilder: (context, index) => const Divider(),
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  var opt = options[i];
                  return ListTile(
                    title: Text(opt['name']),
                    subtitle: Text(opt['qty'].toString()),
                    onTap: () {
                      provider.swapMeal(
                        swapKey,
                        ActiveSwap(
                          name: opt['name'],
                          qty: opt['qty'].toString(),
                          unit: opt['unit'] ?? "",
                        ),
                      );
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DietProvider>();

    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const UserAccountsDrawerHeader(
              accountName: Text("NutriScan"),
              accountEmail: Text("Gestione Dieta"),
              decoration: BoxDecoration(color: Color(0xFF2E7D32)),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text("Carica Dieta PDF"),
              onTap: () => _uploadDiet(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Reset Dati"),
              onTap: () {
                provider.clearData();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text("NutriScan"),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              icon: Icon(
                provider.isTranquilMode ? Icons.spa : Icons.spa_outlined,
              ),
              tooltip: "Modalità Relax",
              onPressed: provider.toggleTranquilMode,
            ),
        ],
        bottom: _currentIndex == 0
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: days
                    .map((d) => Tab(text: d.substring(0, 3).toUpperCase()))
                    .toList(),
              )
            : null,
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(provider),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today),
            label: 'Piano',
          ),
          NavigationDestination(icon: Icon(Icons.kitchen), label: 'Dispensa'),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart),
            label: 'Lista',
          ),
        ],
      ),
    );
  }

  Widget _buildBody(DietProvider provider) {
    switch (_currentIndex) {
      case 0:
        return DietView(
          tabController: _tabController,
          days: days,
          dietData: provider.dietData,
          isLoading: provider.isLoading,
          activeSwaps: provider.activeSwaps,
          substitutions: provider.substitutions,
          pantryItems: provider.pantryItems,
          isTranquilMode: provider.isTranquilMode,
          onConsume: (name, qty) => _onConsume(context, provider, name, qty),
          onEdit: (d, m, i, n, q) => _onEdit(context, provider, d, m, i, n, q),
          onSwap: (key, cad) => _onSwap(context, provider, key, cad),
        );
      case 1:
        return PantryView(
          pantryItems: provider.pantryItems,
          onAddManual: provider.addPantryItem,
          onRemove: provider.removePantryItem,
          onScanTap: () async {
            FilePickerResult? result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['jpg', 'png', 'jpeg', 'pdf'],
            );
            if (!mounted) return;
            if (result != null) {
              try {
                int count = await provider.scanReceipt(
                  result.files.single.path!,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Aggiunti $count prodotti!")),
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Errore scansione: $e")),
                  );
                }
              }
            }
          },
        );
      case 2:
        return ShoppingListView(
          shoppingList: provider.shoppingList,
          dietData: provider.dietData,
          activeSwaps: provider.activeSwaps,
          pantryItems: provider.pantryItems,
          onUpdateList: provider.updateShoppingList,
          onAddToPantry: provider.addPantryItem,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
