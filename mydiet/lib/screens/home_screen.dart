import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pantry_item.dart';
import '../models/active_swap.dart';
import '../services/api_service.dart';
import '../constants.dart';
import 'diet_view.dart';
import 'pantry_view.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  Map<String, dynamic>? dietData;
  Map<String, dynamic>? substitutions;
  Map<String, ActiveSwap> activeSwaps = {};
  List<PantryItem> pantryItems = [];

  bool isLoading = true;
  bool isUploading = false;
  bool isTranquilMode = false;

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
    int todayIndex = DateTime.now().weekday - 1;
    if (todayIndex < 0) todayIndex = 0;
    _tabController = TabController(
      length: days.length,
      initialIndex: todayIndex,
      vsync: this,
    );
    _loadLocalData();
  }

  // --- LOGICA DATI ---
  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    String? dietJson = prefs.getString('dietData');
    if (dietJson != null) {
      final data = json.decode(dietJson);
      setState(() {
        dietData = data['plan'];
        substitutions = data['substitutions'];
      });
    } else {
      _loadAssetDiet();
    }

    String? pantryJson = prefs.getString('pantryItems');
    if (pantryJson != null) {
      List<dynamic> decoded = json.decode(pantryJson);
      setState(
        () => pantryItems = decoded
            .map((item) => PantryItem.fromJson(item))
            .toList(),
      );
    }

    String? swapsJson = prefs.getString('activeSwaps');
    if (swapsJson != null) {
      Map<String, dynamic> decoded = json.decode(swapsJson);
      setState(
        () => activeSwaps = decoded.map(
          (key, value) => MapEntry(key, ActiveSwap.fromJson(value)),
        ),
      );
    }
    setState(() => isLoading = false);
  }

  Future<void> _loadAssetDiet() async {
    try {
      final String response = await rootBundle.loadString('assets/dieta.json');
      final data = json.decode(response);
      setState(() {
        dietData = data['plan'];
        substitutions = data['substitutions'];
      });
    } catch (e) {
      debugPrint("Nessun asset dieta trovato");
    }
  }

  Future<void> _saveLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(
      'pantryItems',
      json.encode(pantryItems.map((e) => e.toJson()).toList()),
    );
    prefs.setString(
      'activeSwaps',
      json.encode(
        activeSwaps.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
    if (dietData != null) {
      prefs.setString(
        'dietData',
        json.encode({'plan': dietData, 'substitutions': substitutions}),
      );
    }
  }

  void _addOrUpdatePantry(String name, double qty, String unit) {
    int existingIndex = pantryItems.indexWhere(
      (p) => p.name.toLowerCase() == name.toLowerCase() && p.unit == unit,
    );
    if (existingIndex != -1) {
      setState(() => pantryItems[existingIndex].quantity += qty);
    } else {
      setState(
        () =>
            pantryItems.add(PantryItem(name: name, quantity: qty, unit: unit)),
      );
    }
    _saveLocalData();
  }

  // --- AZIONI UI ---
  Future<void> _uploadDietAction() async {
    try {
      setState(() => isUploading = true);
      final data = await ApiService.uploadDietPdf();
      if (data != null) {
        setState(() {
          dietData = data['plan'];
          substitutions = data['substitutions'];
          isUploading = false;
        });
        _saveLocalData();
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Dieta Aggiornata!"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => isUploading = false);
      }
    } catch (e) {
      setState(() => isUploading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Errore: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _scanReceiptAction() async {
    try {
      setState(() => isUploading = true);
      final importedItems = await ApiService.scanReceipt();
      setState(() => isUploading = false);

      if (importedItems == null) return;
      if (importedItems.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Nessun cibo trovato."),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      int added = 0;
      for (var item in importedItems) {
        String name = item['name'];
        if (name.toLowerCase().contains("filetti")) {
          String? s = await _showSimpleDialog(
            "Filetti di cosa?",
            ["🐓 Pollo", "Platessa", "🥩 Manzo"],
            ["Petto di pollo", "Platessa", "Manzo magro"],
          );
          if (s == null) continue;
          name = s;
        }
        var result = await _showQuantityDialog(name);
        if (result != null && result['qty'] > 0) {
          _addOrUpdatePantry(name, result['qty'], result['unit']);
          added++;
        }
      }
      if (added > 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Aggiunti $added prodotti!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => isUploading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Errore Scan: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // --- HELPER UI ---
  Future<String?> _showSimpleDialog(
    String title,
    List<String> labels,
    List<String> values,
  ) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SimpleDialog(
        title: Text(title),
        backgroundColor: Colors.white,
        children: List.generate(
          labels.length,
          (i) => SimpleDialogOption(
            onPressed: () => Navigator.pop(context, values[i]),
            child: Text(labels[i]),
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showQuantityDialog(String itemName) {
    TextEditingController q = TextEditingController();
    String u =
        (fruitKeywords.any((k) => itemName.toLowerCase().contains(k)) ||
            veggieKeywords.any((k) => itemName.toLowerCase().contains(k)))
        ? 'pz'
        : 'g';
    return showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, st) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text("Aggiungi $itemName"),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: q,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: "0"),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: u,
                items: const [
                  DropdownMenuItem(value: 'g', child: Text("g")),
                  DropdownMenuItem(value: 'pz', child: Text("pz")),
                ],
                onChanged: (v) => st(() => u = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("Salta"),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () => Navigator.pop(c, {
                'qty': double.tryParse(q.text) ?? 0.0,
                'unit': u,
              }),
              child: const Text("Ok"),
            ),
          ],
        ),
      ),
    );
  }

  // --- LOGICHE PASTO ---
  void _consumeFood(String name, String dietQtyString) {
    int idx = pantryItems.indexWhere(
      (p) =>
          name.toLowerCase().contains(p.name.toLowerCase()) ||
          p.name.toLowerCase().contains(name.toLowerCase()),
    );
    if (idx == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Non hai $name!"),
          backgroundColor: Colors.red[100],
        ),
      );
      return;
    }

    // Parsing Semplificato per brevità
    RegExp regExp = RegExp(r'(\d+(?:[.,]\d+)?)');
    double qtyToEat = 0.0;
    if (pantryItems[idx].unit == 'g') {
      var match = regExp.firstMatch(dietQtyString);
      qtyToEat = match != null
          ? double.parse(match.group(1)!.replaceAll(',', '.'))
          : 100.0;
    } else {
      qtyToEat = 1.0;
    }

    setState(() {
      pantryItems[idx].quantity -= qtyToEat;
      if (pantryItems[idx].quantity <= 0.1) {
        pantryItems.removeAt(idx);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Finito! 🗑️"),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Rimasti ${pantryItems[idx].quantity.toInt()} ${pantryItems[idx].unit}",
            ),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    });
    _saveLocalData();
  }

  void _editMealItem(
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
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("Modifica"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Nome"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: "Quantità"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annulla"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green[700]),
            onPressed: () {
              setState(() {
                dietData![day][mealName][index]['name'] = nameCtrl.text;
                dietData![day][mealName][index]['qty'] = qtyCtrl.text;
              });
              _saveLocalData();
              Navigator.pop(context);
            },
            child: const Text("Salva"),
          ),
        ],
      ),
    );
  }

  void _showSubstitutions(
    String day,
    String mealName,
    int index,
    String currentName,
    String cadCode,
  ) {
    var subData = substitutions![cadCode];
    List<dynamic> options = subData['options'] ?? [];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Alternative",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 300,
              child: ListView.separated(
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemCount: options.length,
                itemBuilder: (context, i) {
                  var opt = options[i];
                  return ListTile(
                    title: Text(opt['name']),
                    trailing: Text(opt['qty']),
                    onTap: () {
                      setState(
                        () => activeSwaps["${day}_${mealName}_$index"] =
                            ActiveSwap(name: opt['name'], qty: opt['qty']),
                      );
                      _saveLocalData();
                      Navigator.pop(context);
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
    return Scaffold(
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const UserAccountsDrawerHeader(
              accountName: Text("NutriScan"),
              accountEmail: Text("Gestione Dieta"),
              decoration: BoxDecoration(color: Color(0xFF2E7D32)),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.local_dining, color: Colors.green),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text("Carica Nuova Dieta PDF"),
              onTap: _uploadDietAction,
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Resetta Dati"),
              onTap: () async {
                final p = await SharedPreferences.getInstance();
                await p.clear();
                if (!mounted) return;
                setState(() {
                  dietData = null;
                  pantryItems = [];
                });
                // ignore: use_build_context_synchronously
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            // 1. Sfondo bianco e icone scure per pulizia e contrasto
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 2,
            forceElevated: innerBoxIsScrolled,

            title: Text(
              _currentIndex == 0 ? 'MyDiet' : 'Dispensa',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),

            floating: true,
            pinned: true,

            actions: [
              if (_currentIndex == 0)
                // 2. Sostituito lo Switch con un'Icona cliccabile (più visibile)
                IconButton(
                  icon: Icon(
                    isTranquilMode ? Icons.spa : Icons.spa_outlined,
                    color: isTranquilMode ? Colors.green : Colors.grey,
                    size: 28,
                  ),
                  tooltip: "Modalità Relax",
                  onPressed: () {
                    setState(() => isTranquilMode = !isTranquilMode);

                    // Feedback visivo immediato
                    ScaffoldMessenger.of(context).removeCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isTranquilMode
                              ? "Modalità Relax Attiva 🌿"
                              : "Modalità Standard 🔥",
                        ),
                        duration: const Duration(milliseconds: 800),
                        backgroundColor: isTranquilMode
                            ? Colors.green[700]
                            : Colors.blueGrey,
                      ),
                    );
                  },
                ),
              // Aggiungo un piccolo spazio a destra
              const SizedBox(width: 8),
            ],

            bottom: _currentIndex == 0
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(60),
                    child: Container(
                      height: 55, // Altezza fissa per i tab
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable:
                            true, // Necessario per 7 giorni su schermi piccoli
                        tabAlignment: TabAlignment
                            .start, // Allinea a sinistra per scorrere meglio
                        // 3. Stile "Pillola" migliorato
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: const Color(0xFF2E7D32), // Verde scuro
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor:
                            Colors.transparent, // Rimuove la riga sotto
                        // Colori testo
                        labelColor: Colors.white, // Testo selezionato
                        unselectedLabelColor:
                            Colors.grey[600], // Testo non selezionato
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),

                        // Padding interno ai tab per distanziarli
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),

                        tabs: days
                            .map(
                              (day) => Tab(
                                text: day
                                    .substring(0, 3)
                                    .toUpperCase(), // LUN, MAR...
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  )
                : null,
          ),
        ],
        body: _currentIndex == 0
            ? DietView(
                dietData: dietData,
                isLoading: isLoading,
                tabController: _tabController,
                days: days,
                activeSwaps: activeSwaps,
                substitutions: substitutions,
                pantryItems: pantryItems,
                isTranquilMode: isTranquilMode,
                onConsume: _consumeFood,
                onEdit: _editMealItem,
                onSwap: _showSubstitutions,
              )
            : PantryView(
                pantryItems: pantryItems,
                onAddManual: _addOrUpdatePantry,
                onRemove: (i) {
                  setState(() => pantryItems.removeAt(i));
                  _saveLocalData();
                },
                onScanTap: _scanReceiptAction,
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: Colors.white,
        elevation: 10,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today, color: Colors.green),
            label: 'Piano',
          ),
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            selectedIcon: Icon(Icons.kitchen, color: Colors.green),
            label: 'Frigo',
          ),
        ],
      ),
    );
  }
}
