import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/diet_provider.dart';
import '../models/active_swap.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../constants.dart';
import 'diet_view.dart';
import 'pantry_view.dart';
import 'shopping_list_view.dart';
import 'login_screen.dart';
import 'history_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late TabController _tabController;
  final AuthService _auth = AuthService();

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

    // [MODIFICA] Avvio logica di caricamento sequenziale (Cache -> Cloud)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAppData();
    });
  }

  /// Carica i dati in sequenza: Cache (Offline) e poi Cloud (Sync)
  Future<void> _initAppData() async {
    final provider = context.read<DietProvider>();
    final user = FirebaseAuth.instance.currentUser;

    // 1. CARICAMENTO CACHE (Istantaneo)
    bool hasCache = await provider.loadFromCache();

    // 2. SINCRONIZZAZIONE CLOUD
    if (user != null) {
      // [MODIFICA] Ritardiamo il salvataggio del token di 5 secondi
      // Così non va in conflitto con l'inizializzazione del main.dart
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _saveFCMToken(
            user.uid,
          ).catchError((e) => debugPrint("FCM Error: $e"));
        }
      });

      // Sync in background
      await provider.syncFromFirebase(user.uid);
    } else if (!hasCache) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _saveFCMToken(String uid) async {
    try {
      // 1. Check rapido: se non c'è rete, non provare neanche
      try {
        final result = await InternetAddress.lookup('google.com');
        if (result.isEmpty || result[0].rawAddress.isEmpty) return;
      } catch (_) {
        return; // Offline -> Esci silenziosamente
      }

      // 2. Se siamo online, prova a prendere il token
      final token = await NotificationService().getFCMToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcm_token': token,
        });
      }
    } catch (e) {
      // Silenzia errori "Remote Config" o "Network"
      debugPrint("FCM Token Skip (Offline/Error): $e");
    }
  }

  Future<void> _uploadDiet(BuildContext context) async {
    final provider = context.read<DietProvider>();
    // Salviamo il riferimento allo ScaffoldMessenger PRIMA dell'await
    final messenger = ScaffoldMessenger.of(context);

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    // Controllo mounted obbligatorio
    if (!mounted) return;

    if (result != null && result.files.single.path != null) {
      try {
        await provider.uploadDiet(result.files.single.path!);

        // Controllo mounted dopo il secondo await
        if (!mounted) return;

        messenger.showSnackBar(
          const SnackBar(
            content: Text("Dieta caricata e salvata!"),
            backgroundColor: AppColors.primary,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        String msg = provider.error ?? "Errore sconosciuto";
        messenger.showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
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
        backgroundColor: AppColors.primary,
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
            const SizedBox(height: 8),
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

  Future<void> _openTimeSettings() async {
    final storage = StorageService();
    List<Map<String, dynamic>> alarms = await storage.loadAlarms();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (innerCtx, setDialogState) {
            void addAlarm() {
              setDialogState(() {
                alarms.add({
                  'id': DateTime.now().millisecondsSinceEpoch % 100000,
                  'label': 'Spuntino',
                  'time': '10:00',
                  'body': 'Ricorda il tuo spuntino!',
                });
              });
            }

            void removeAlarm(int index) {
              setDialogState(() {
                alarms.removeAt(index);
              });
            }

            void restoreDefaults() {
              setDialogState(() {
                alarms = [
                  {
                    'id': 10,
                    'label': 'Colazione ☕',
                    'time': '08:00',
                    'body': 'È ora di fare il pieno di energia!',
                  },
                  {
                    'id': 11,
                    'label': 'Pranzo 🥗',
                    'time': '13:00',
                    'body': 'Buon appetito! Segui il piano.',
                  },
                  {
                    'id': 12,
                    'label': 'Cena 🍽️',
                    'time': '20:00',
                    'body': 'Chiudi la giornata con gusto.',
                  },
                ];
              });
            }

            return AlertDialog(
              insetPadding: const EdgeInsets.all(10),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Allarmi"),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore, color: Colors.grey),
                        onPressed: restoreDefaults,
                        tooltip: "Ripristina",
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: AppColors.primary,
                        ),
                        onPressed: addAlarm,
                        tooltip: "Aggiungi",
                      ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: alarms.isEmpty
                    ? const Center(child: Text("Nessun allarme impostato."))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: alarms.length,
                        itemBuilder: (context, index) {
                          final alarm = alarms[index];
                          final time = _parseTime(alarm['time'] ?? "08:00");

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          initialValue: alarm['label'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                          decoration: const InputDecoration(
                                            labelText: "Titolo",
                                            isDense: true,
                                            border: InputBorder.none,
                                          ),
                                          onChanged: (val) =>
                                              alarm['label'] = val,
                                        ),
                                      ),
                                      TextButton.icon(
                                        icon: const Icon(Icons.access_time),
                                        label: Text(
                                          "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        onPressed: () async {
                                          final picked = await showTimePicker(
                                            context: innerCtx,
                                            initialTime: time,
                                          );
                                          if (picked != null) {
                                            setDialogState(() {
                                              alarm['time'] =
                                                  "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
                                            });
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.red,
                                        ),
                                        onPressed: () => removeAlarm(index),
                                      ),
                                    ],
                                  ),
                                  TextFormField(
                                    initialValue: alarm['body'],
                                    decoration: const InputDecoration(
                                      labelText: "Messaggio",
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      border: InputBorder.none,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                    onChanged: (val) => alarm['body'] = val,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Annulla"),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await storage.saveAlarms(alarms);

                    final notifs = NotificationService();
                    await notifs.init();
                    await notifs.requestPermissions();
                    await notifs.scheduleAllMeals();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Allarmi aggiornati!")),
                      );
                    }
                  },
                  child: const Text("Salva"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  TimeOfDay _parseTime(String s) {
    try {
      final parts = s.split(":");
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DietProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text("Kybo"),
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
          drawer: _buildDrawer(
            context,
            _auth.currentUser,
            provider,
            colorScheme,
          ),
          body: _buildBody(provider),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() => _currentIndex = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.calendar_today),
                label: 'Piano',
              ),
              NavigationDestination(
                icon: Icon(Icons.kitchen),
                label: 'Dispensa',
              ),
              NavigationDestination(
                icon: Icon(Icons.shopping_cart),
                label: 'Lista',
              ),
            ],
          ),
        ),
        if (provider.isLoading)
          Container(
            color: Colors.black45,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildDrawer(
    BuildContext drawerCtx,
    User? user,
    DietProvider provider,
    ColorScheme colors,
  ) {
    return StreamBuilder<DocumentSnapshot>(
      stream: user != null
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots()
          : const Stream.empty(),
      builder: (streamCtx, snapshot) {
        String role = 'user';
        if (snapshot.hasData && snapshot.data!.exists) {
          role =
              (snapshot.data!.data() as Map<String, dynamic>)['role'] ?? 'user';
        }

        final bool canUpload = role == 'independent' || role == 'admin';

        return Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              UserAccountsDrawerHeader(
                accountName: const Text("Kybo"),
                accountEmail: Text("${user?.email ?? "Ospite"}\n(Role: $role)"),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 40, color: colors.primary),
                ),
                decoration: BoxDecoration(color: colors.primary),
              ),
              if (user == null)
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text("Accedi / Registrati"),
                  onTap: () {
                    Navigator.pop(drawerCtx);
                    Navigator.pushReplacement(
                      drawerCtx,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text("Cronologia Diete"),
                  onTap: () {
                    Navigator.pop(drawerCtx);
                    Navigator.push(
                      drawerCtx,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    );
                  },
                ),
                // [MODIFICA] Logout con pulizia cache locale
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text("Esci"),
                  onTap: () async {
                    Navigator.pop(drawerCtx);

                    // Pulizia Cache
                    await provider.clearData();

                    await _auth.signOut();
                    if (mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    }
                  },
                ),
              ],
              const Divider(),
              if (canUpload)
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text("Carica Dieta PDF"),
                  onTap: () => _uploadDiet(drawerCtx),
                ),
              ListTile(
                leading: const Icon(Icons.notifications_active),
                title: const Text("Gestisci Allarmi"),
                onTap: () {
                  Navigator.pop(drawerCtx);
                  _openTimeSettings();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Reset Dati Locali"),
                onTap: () {
                  provider.clearData();
                  Navigator.pop(drawerCtx);
                },
              ),
            ],
          ),
        );
      },
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
            if (result != null && result.files.single.path != null) {
              try {
                int count = await provider.scanReceipt(
                  result.files.single.path!,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Aggiunti $count prodotti!"),
                    backgroundColor: AppColors.primary,
                  ),
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Errore: ${provider.error ?? e}"),
                      backgroundColor: Colors.red,
                    ),
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
