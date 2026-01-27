import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';

import '../providers/diet_provider.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../constants.dart';
import '../core/error_handler.dart';
import 'diet_view.dart';
import 'pantry_view.dart';
import 'shopping_list_view.dart';
import 'login_screen.dart';
import 'history_screen.dart';
import 'change_password_screen.dart';
import 'package:permission_handler/permission_handler.dart'; // <--- NUOVO
import '../services/jailbreak_service.dart';

// --- 1. WRAPPER PRINCIPALE ---
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      autoPlay: false,
      blurValue: 1,
      builder: (context) => const MainScreenContent(),
    );
  }
}

// --- 2. CONTENUTO DELLA SCHERMATA ---
class MainScreenContent extends StatefulWidget {
  const MainScreenContent({super.key});

  @override
  State<MainScreenContent> createState() => _MainScreenContentState();
}

class _MainScreenContentState extends State<MainScreenContent>
    with TickerProviderStateMixin {
  int _currentIndex = 1;
  late TabController _tabController;
  final AuthService _auth = AuthService();

  // CHIAVI TUTORIAL
  final GlobalKey _menuKey = GlobalKey();
  final GlobalKey _tranquilKey = GlobalKey();
  final GlobalKey _pantryTabKey = GlobalKey();
  final GlobalKey _shoppingTabKey = GlobalKey();

  String _menuTutorialDescription = 'Qui trovi le impostazioni e lo storico.';

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
    _initialPermissionCheck();
    int today = DateTime.now().weekday - 1;
    _tabController = TabController(
      length: 7,
      initialIndex: today < 0 ? 0 : today,
      vsync: this,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkJailbreak();
      _initAppData();
      _checkTutorial();
    });
  }

  Future<void> _initialPermissionCheck() async {
    var status = await Permission.notification.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      await Permission.notification.request();
    }
  }

  // Dialog "Hard": Spiega e manda alle impostazioni
  void _showForcePermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Notifiche Pasti 🍽️'),
        content: const Text(
          'Per ricordarti i pasti e controllare la dispensa, Kybo ha bisogno delle notifiche.\n\n'
          'Per favore, attivale nelle impostazioni del telefono.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              openAppSettings(); // Apre le impostazioni Android/iOS
              Navigator.pop(context);
            },
            child: const Text('Impostazioni'),
          ),
        ],
      ),
    );
  }

  Future<void> _initAppData() async {
    if (!mounted) return;
    final provider = context.read<DietProvider>();
    await provider.loadFromCache();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      provider.syncFromFirebase(user.uid);
    }

    final storage = StorageService();
    try {
      // FIX: Rimosso check ridondante 'data is List'
      var data = await storage.loadAlarms();
      if (data.isNotEmpty) {
        // NUOVO
        if (mounted) {
          // Chiediamo al provider di rischedulare usando i dati che possiede
          await context.read<DietProvider>().scheduleMealNotifications();
        }
      }
    } catch (_) {}
  }

// Fix #2: Usa direttamente JailbreakService invece di cercare Provider<bool>
  Future<void> _checkJailbreak() async {
    try {
      final jailbreakService = JailbreakService();
      final isJailbroken = await jailbreakService.checkDevice();
      if (isJailbroken && mounted) {
        _showJailbreakWarning();
      }
    } catch (e) {
      // Ignora errore se jailbreak detection non disponibile (es. emulatore)
      debugPrint('Jailbreak check error: $e');
    }
  }

  // --- LOGICA TUTORIAL ---
  Future<void> _checkTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    bool seen = prefs.getBool('seen_tutorial_v10') ?? false;

    if (!seen) {
      _startShowcase();
    }
  }

  Future<void> _startShowcase() async {
    final user = FirebaseAuth.instance.currentUser;
    String role = 'client';

    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) role = doc.data()?['role'] ?? 'client';
      } catch (_) {}
    }

    if (role == 'independent' || role == 'admin') {
      _menuTutorialDescription =
          "Qui puoi:\n• Caricare la tua Dieta\n• Gestire Notifiche\n• Vedere lo Storico";
    } else {
      _menuTutorialDescription =
          "Qui puoi:\n• Gestire le Notifiche\n• Vedere lo Storico delle diete passate";
    }

    if (mounted) {
      ShowCaseWidget.of(
        context,
      ).startShowCase([_menuKey, _tranquilKey, _pantryTabKey, _shoppingTabKey]);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('seen_tutorial_v10', true);
    }
  }

  Future<void> _resetTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_tutorial_v10', false);
    _startShowcase();
  }

  // Helper per mostrare la Privacy Policy (Modale)
  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Privacy Policy"),
        content: const SingleChildScrollView(
          child: Text(
            "Informativa sulla Privacy\n\n"
            "I tuoi dati (email, nome, piano alimentare) sono utilizzati esclusivamente per fornirti il servizio Kybo.\n"
            "I dati sensibili sono protetti e accessibili solo al personale autorizzato per scopi di assistenza tecnica o legale.\n\n"
            "Per richiedere la cancellazione dei dati, contatta l'amministratore.",
            style: TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Chiudi"),
          ),
        ],
      ),
    );
  }

  void _showJailbreakWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.security, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                "Dispositivo Non Sicuro",
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                "Il tuo dispositivo risulta modificato (jailbreak/root).",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                "Questo comporta rischi per la sicurezza dei tuoi dati medici:",
              ),
              SizedBox(height: 8),
              Text("• Malware può accedere ai tuoi dati"),
              Text("• Le chiavi di cifratura potrebbero essere compromesse"),
              Text("• App di terze parti possono intercettare informazioni"),
              SizedBox(height: 16),
              Text(
                "Ti consigliamo vivamente di:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text("• Usare un dispositivo non modificato"),
              Text("• Ripristinare il dispositivo alle impostazioni originali"),
              Text("• Contattare il supporto per assistenza"),
              SizedBox(height: 16),
              Text(
                "Continuando, accetti che i tuoi dati potrebbero non essere completamente protetti.",
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // ✅ Log accettazione warning
              FirebaseAnalytics.instance.logEvent(
                name: 'jailbreak_warning_accepted',
                parameters: {
                  'timestamp': DateTime.now().toIso8601String(),
                },
              );
              Navigator.pop(ctx);
            },
            child: const Text(
              "Ho capito, continua comunque",
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // [FIX 1] Rinominato da dietProvider a provider per coerenza con il resto del codice
    final provider = Provider.of<DietProvider>(context);

    // [FIX 2] Definito user per passarlo al drawer
    final user = FirebaseAuth.instance.currentUser;

    // 2. CONTROLLO REATTIVO: Se serve il permesso, mostra il dialog
    if (provider.needsNotificationPermissions) {
      // Usiamo 'provider' qui
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.resetPermissionFlag();
        _showForcePermissionDialog();
      });
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _currentIndex == 1
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: const Text(
                "Kybo",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              iconTheme: const IconThemeData(color: Colors.black),
              leading: Builder(
                builder: (context) {
                  return Showcase(
                    key: _menuKey,
                    title: 'Menu Principale',
                    description: _menuTutorialDescription,
                    targetShapeBorder: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  );
                },
              ),
              actions: [
                Showcase(
                  key: _tranquilKey,
                  title: 'Modalità Relax',
                  description:
                      'Tocca la foglia per nascondere le calorie\ne ridurre lo stress.',
                  targetShapeBorder: const CircleBorder(),
                  child: IconButton(
                    icon: Icon(
                      provider.isTranquilMode ? Icons.spa : Icons.spa_outlined,
                      color: provider.isTranquilMode
                          ? AppColors.primary
                          : Colors.grey,
                    ),
                    onPressed: provider.toggleTranquilMode,
                  ),
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: AppColors.primary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: days
                    .map((d) => Tab(text: d.substring(0, 3).toUpperCase()))
                    .toList(),
              ),
            )
          : null,
      drawer: _buildDrawer(context, user),
      body: _buildBody(provider),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: AppColors.primary.withValues(alpha: 0.1),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: AppColors.primary);
            }
            return const IconThemeData(color: Colors.grey);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              );
            }
            return const TextStyle(color: Colors.grey, fontSize: 12);
          }),
          backgroundColor: Colors.white,
          elevation: 5,
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: [
            NavigationDestination(
              icon: Showcase(
                key: _pantryTabKey,
                title: 'Dispensa',
                description:
                    'Tieni traccia di ciò che hai in casa.\nScorri per eliminare, + per aggiungere.',
                child: const Icon(Icons.kitchen),
              ),
              label: 'Dispensa',
            ),
            const NavigationDestination(
              icon: Icon(Icons.calendar_today),
              label: 'Piano',
            ),
            NavigationDestination(
              icon: Showcase(
                key: _shoppingTabKey,
                title: 'Lista della Spesa',
                description: 'Generata in automatico dalla tua dieta.',
                child: const Icon(Icons.shopping_cart),
              ),
              label: 'Lista',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(DietProvider provider) {
    switch (_currentIndex) {
      case 0:
        return PantryView(
          pantryItems: provider.pantryItems,
          onAddManual: provider.addPantryItem,
          onRemove: provider.removePantryItem,
          onScanTap: () => _scanReceipt(provider),
        );
      case 1:
        // [FIX] Passiamo dietPlan invece di dietData/substitutions
        return TabBarView(
          controller: _tabController,
          children: days.map((day) {
            return DietView(
              day: day,
              dietPlan: provider.dietPlan, // <--- CAMBIATO QUI
              isLoading: provider.isLoading,
              activeSwaps: provider.activeSwaps,
              // substitutions rimosso
              pantryItems: provider.pantryItems,
              isTranquilMode: provider.isTranquilMode,
            );
          }).toList(),
        );
      case 2:
        return ShoppingListView(
          shoppingList: provider.shoppingList,
          dietPlan:
              provider.dietPlan, // <--- PASSA L'OGGETTO (prima era dietData)
          activeSwaps: provider.activeSwaps,
          pantryItems: provider.pantryItems,
          onUpdateList: provider.updateShoppingList,
          onAddToPantry: provider.addPantryItem,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDrawer(BuildContext drawerCtx, User? user) {
    final String initial = (user?.email != null && user!.email!.isNotEmpty)
        ? user.email![0].toUpperCase()
        : "U";

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
        final bool canUpload = (role == 'independent' || role == 'admin');

        return Drawer(
          backgroundColor: Colors.white,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              UserAccountsDrawerHeader(
                accountName: const Text(
                  "Kybo",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                accountEmail: Text(
                  "${user?.email ?? "Ospite"} ($role)",
                  style: const TextStyle(color: Colors.white70),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 30.0,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                decoration: const BoxDecoration(color: AppColors.primary),
              ),
              if (user != null) ...[
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
                ListTile(
                  leading: const Icon(Icons.lock),
                  title: const Text("Cambia Password"),
                  onTap: () {
                    Navigator.pop(drawerCtx);
                    Navigator.push(
                      drawerCtx,
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                ),
                if (canUpload)
                  ListTile(
                    leading: const Icon(
                      Icons.upload_file,
                      color: Colors.orange,
                    ),
                    title: const Text("Carica Dieta PDF"),
                    onTap: () {
                      Navigator.pop(drawerCtx);
                      _uploadDiet(drawerCtx);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.notifications_active),
                  title: const Text("Gestisci Allarmi"),
                  onTap: () {
                    Navigator.pop(drawerCtx);
                    _openTimeSettings();
                  },
                ),

                // --- PRIVACY POLICY NEL MENU ---
                ListTile(
                  leading: const Icon(
                    Icons.privacy_tip,
                    color: Colors.blueGrey,
                  ),
                  title: const Text("Privacy Policy"),
                  onTap: () {
                    Navigator.pop(drawerCtx);
                    _showPrivacyDialog();
                  },
                ),

                const Divider(),

                // TASTO RESET TUTORIAL
                ListTile(
                  leading: const Icon(
                    Icons.replay_circle_filled,
                    color: Colors.green,
                  ),
                  title: const Text("Riavvia Tutorial"),
                  onTap: () {
                    Navigator.pop(drawerCtx);
                    _resetTutorial();
                  },
                ),

                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text("Esci"),
                  onTap: () async {
                    Navigator.pop(drawerCtx);
                    await context.read<DietProvider>().clearData();
                    await _auth.signOut();
                    if (mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _uploadDiet(BuildContext context) async {
    final provider = Provider.of<DietProvider>(context, listen: false);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.single.path == null) {
        return; // Utente ha annullato
      }

      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;

      // ✅ Mostra dialog con progresso
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text("Caricamento Dieta"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✅ Progress bar reale con Consumer
                  Consumer<DietProvider>(
                    builder: (_, prov, __) {
                      final progress = prov.uploadProgress;
                      final percentage = (progress * 100).toInt();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey[200],
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                            minHeight: 8,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "$percentage%",
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            fileName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),
                          // ✅ Messaggio dinamico basato su progresso
                          Text(
                            percentage < 95
                                ? "Upload in corso..."
                                : "Elaborazione AI...",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // ✅ Esegui upload (progress viene tracciato automaticamente)
      await provider.uploadDiet(filePath);

      // Chiudi dialog
      if (context.mounted) {
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Dieta caricata con successo!"),
            backgroundColor: AppColors.primary,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Chiudi dialog se aperto
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMapper.toUserMessage(e)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _scanReceipt(DietProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        int count = await provider.scanReceipt(result.files.single.path!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Aggiunti $count prodotti!"),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMapper.toUserMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openTimeSettings() async {
    final storage = StorageService();
    List<Map<String, dynamic>> alarms = [];
    try {
      // FIX: Rimosso check ridondante 'data is List'
      var data = await storage.loadAlarms();
      if (data.isNotEmpty) {
        alarms = List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (innerCtx, setDialogState) {
            void addAlarm() => setDialogState(
                  () => alarms.add({
                    'id': DateTime.now().millisecondsSinceEpoch % 100000,
                    'label': 'Spuntino',
                    'time': '10:00',
                    'body': 'Ricorda il tuo spuntino!',
                  }),
                );
            void removeAlarm(int index) =>
                setDialogState(() => alarms.removeAt(index));

            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Gestisci Allarmi"),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore),
                        onPressed: () => setDialogState(
                          () => alarms = [
                            {
                              'id': 10,
                              'label': 'Colazione ☕',
                              'time': '08:00',
                              'body': 'Sveglia!',
                            },
                            {
                              'id': 11,
                              'label': 'Pranzo 🥗',
                              'time': '13:00',
                              'body': 'Buon appetito!',
                            },
                            {
                              'id': 12,
                              'label': 'Cena 🍽️',
                              'time': '20:00',
                              'body': 'Cena time!',
                            },
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.blue),
                        onPressed: addAlarm,
                      ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: alarms.isEmpty
                    ? const Center(child: Text("Nessun allarme."))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: alarms.length,
                        itemBuilder: (context, index) {
                          final alarm = alarms[index];
                          final parts = (alarm['time'] ?? "08:00").split(":");
                          final time = TimeOfDay(
                            hour: int.parse(parts[0]),
                            minute: int.parse(parts[1]),
                          );
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: alarm['label'],
                                          decoration: const InputDecoration(
                                            labelText: "Titolo",
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                          ),
                                          onChanged: (v) => alarm['label'] = v,
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // 1. TASTO ORARIO COMPATTO (No TextButton)
                                      InkWell(
                                        onTap: () async {
                                          final p = await showTimePicker(
                                            context: innerCtx,
                                            initialTime: time,
                                          );
                                          if (p != null) {
                                            setDialogState(
                                              () => alarm['time'] =
                                                  "${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}",
                                            );
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(4),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                          child: Text(
                                            "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // 2. TASTO RIMUOVI COMPATTO (No IconButton)
                                      InkWell(
                                        onTap: () => removeAlarm(index),
                                        borderRadius: BorderRadius.circular(20),
                                        child: const Padding(
                                          padding: EdgeInsets.all(
                                            8.0,
                                          ), // Padding manuale controllato
                                          child: Icon(
                                            Icons.close,
                                            color: Colors.red,
                                            size:
                                                22, // Icona leggermente più piccola
                                          ),
                                        ),
                                      ),
                                    ],
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
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await storage.saveAlarms(alarms);
                    // NUOVO
                    if (mounted) {
                      // Chiediamo al provider di rischedulare usando i dati che possiede
                      await context
                          .read<DietProvider>()
                          .scheduleMealNotifications();
                    }
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
}
