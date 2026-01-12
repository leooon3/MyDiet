import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../admin_repository.dart';

class UserManagementView extends StatefulWidget {
  const UserManagementView({super.key});

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  final AdminRepository _repo = AdminRepository();
  bool _isLoading = false;

  // UI Filters
  String _searchQuery = "";
  String _roleFilter = "all";
  final TextEditingController _searchCtrl = TextEditingController();

  // Current User Data
  String _currentUserId = '';
  String _currentUserRole = '';
  bool _isDataLoaded = false;

  // DATI UTENTI (Ora scaricati via API Secure)
  Future<List<dynamic>>? _usersFuture;

  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
  }

  // UPDATED: Usa i claims del token, zero letture DB!
  Future<void> _checkCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Forza il refresh del token per avere i claims aggiornati
        final tokenResult = await user.getIdTokenResult(true);
        final role = tokenResult.claims?['role'] ?? 'user';

        if (mounted) {
          setState(() {
            _currentUserId = user.uid;
            _currentUserRole = role;
            _isDataLoaded = true;
          });
          _refreshList();
        }
      } catch (e) {
        // Fallback in caso di errore di rete
        if (mounted) setState(() => _isDataLoaded = true);
      }
    }
  }

  void _refreshList() {
    setState(() {
      _usersFuture = _repo.getSecureUsersList();
    });
  }

  // --- ACTIONS ---

  Future<void> _syncUsers() async {
    setState(() => _isLoading = true);
    try {
      String msg = await _repo.syncUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.blue),
        );
        _refreshList(); // Ricarica lista dopo sync
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sync Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteUser(String uid) async {
    if (!mounted) return;
    bool confirm =
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Elimina Utente"),
            content: const Text(
              "Sei sicuro? L'azione è irreversibile e verrà loggata.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text("Annulla"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(c, true),
                child: const Text("Elimina"),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      setState(() => _isLoading = true);
      try {
        await _repo.deleteUser(uid);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Utente eliminato.")));
          _refreshList(); // Ricarica lista
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Errore: $e")));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadDiet(String targetUid) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() => _isLoading = true);
      try {
        await _repo.uploadDietForUser(targetUid, result.files.single);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Dieta caricata!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Errore upload: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadParser(String targetUid) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ParserConfigScreen(targetUid: targetUid),
      ),
    );
  }

  Future<void> _showUserHistory(String targetUid, String userName) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _UserHistoryScreen(targetUid: targetUid, userName: userName),
      ),
    );
  }

  Future<void> _editUser(
    String uid,
    String currentEmail,
    String currentFirst,
    String currentLast,
  ) async {
    final emailCtrl = TextEditingController(text: currentEmail);
    final firstCtrl = TextEditingController(text: currentFirst);
    final lastCtrl = TextEditingController(text: currentLast);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modifica Account"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstCtrl,
              decoration: const InputDecoration(labelText: "Nome"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: lastCtrl,
              decoration: const InputDecoration(labelText: "Cognome"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: "Email"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annulla"),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                await _repo.updateUser(
                  uid,
                  email: emailCtrl.text,
                  firstName: firstCtrl.text,
                  lastName: lastCtrl.text,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Utente aggiornato")),
                  );
                  _refreshList(); // Ricarica
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Errore: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text("Salva"),
          ),
        ],
      ),
    );
  }

  // --- ASSIGNMENT LOGIC ---

  Future<void> _assignUser(
    String targetUid,
    Map<String, String> nutritionists,
  ) async {
    String? selectedNutId;
    if (nutritionists.isNotEmpty) selectedNutId = nutritionists.keys.first;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text("Assegna a Nutrizionista"),
          content: DropdownButtonFormField<String>(
            initialValue: selectedNutId,
            isExpanded: true,
            items: nutritionists.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) => setDialogState(() => selectedNutId = v),
            decoration: const InputDecoration(
              labelText: "Seleziona Nutrizionista",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annulla"),
            ),
            FilledButton(
              onPressed: () async {
                if (selectedNutId == null) return;
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                try {
                  await _repo.assignUserToNutritionist(
                    targetUid,
                    selectedNutId!,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Utente assegnato!")),
                    );
                    _refreshList(); // Ricarica
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Errore: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text("Assegna"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManageAssignmentDialog(
    String targetUid,
    Map<String, String> nutritionists,
  ) async {
    String? selectedNutId;
    if (nutritionists.isNotEmpty) selectedNutId = nutritionists.keys.first;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text("Gestisci Assegnazione"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Sposta utente ad un altro nutrizionista:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              DropdownButtonFormField<String>(
                initialValue: selectedNutId,
                isExpanded: true,
                items: nutritionists.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedNutId = v),
                decoration: const InputDecoration(
                  labelText: "Nuovo Nutrizionista",
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_off, color: Colors.red),
                label: const Text(
                  "Rimuovi Assegnazione",
                  style: TextStyle(color: Colors.red),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  try {
                    await _repo.unassignUser(targetUid);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Assegnazione rimossa.")),
                      );
                      _refreshList(); // Ricarica
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text("Errore: $e")));
                    }
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annulla"),
            ),
            FilledButton(
              onPressed: () async {
                if (selectedNutId == null) return;
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                try {
                  await _repo.assignUserToNutritionist(
                    targetUid,
                    selectedNutId!,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Utente trasferito!")),
                    );
                    _refreshList(); // Ricarica
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("Errore: $e")));
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text("Sposta"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateUserDialog() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final surnameCtrl = TextEditingController();
    String role = 'user';

    List<DropdownMenuItem<String>> allowedRoles = [
      const DropdownMenuItem(value: 'user', child: Text("Cliente")),
    ];

    if (_currentUserRole == 'admin') {
      allowedRoles.addAll([
        const DropdownMenuItem(
          value: 'nutritionist',
          child: Text("Nutrizionista"),
        ),
        const DropdownMenuItem(
          value: 'independent',
          child: Text("Indipendente"),
        ),
        const DropdownMenuItem(value: 'admin', child: Text("Admin")),
      ]);
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text("Nuovo Utente"),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: "Nome"),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: surnameCtrl,
                          decoration: const InputDecoration(
                            labelText: "Cognome",
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  TextField(
                    controller: passCtrl,
                    decoration: const InputDecoration(
                      labelText: "Password Temp",
                      prefixIcon: Icon(Icons.key),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: "Ruolo"),
                    items: allowedRoles,
                    onChanged: (v) => setDialogState(() => role = v!),
                  ),
                ],
              ),
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
                setState(() => _isLoading = true);
                try {
                  await _repo.createUser(
                    email: emailCtrl.text,
                    password: passCtrl.text,
                    role: role,
                    firstName: nameCtrl.text,
                    lastName: surnameCtrl.text,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Utente creato!")),
                    );
                    _refreshList(); // Ricarica
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("Errore: $e")));
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text("Crea"),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.purple;
      case 'nutritionist':
        return Colors.blue;
      case 'independent':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDataLoaded) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        // --- TOP TOOLBAR ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: 0.05,
                ), // Nota: .withValues su Flutter 3.27+, withOpacity su precedenti
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              // 1. BARRA DI RICERCA (Per Tutti)
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: "Cerca utente...",
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                  ),
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.toLowerCase()),
                ),
              ),

              // 2. FILTRO RUOLI (Solo Admin)
              // Il nutrizionista vede solo i suoi, inutile filtrare.
              if (_currentUserRole == 'admin') ...[
                const VerticalDivider(),
                DropdownButton<String>(
                  value: _roleFilter,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text("Tutti i Ruoli"),
                    ),
                    DropdownMenuItem(value: 'user', child: Text("Clienti")),
                    DropdownMenuItem(
                      value: 'nutritionist',
                      child: Text("Nutrizionisti"),
                    ),
                    DropdownMenuItem(
                      value: 'independent',
                      child: Text("Indipendenti"),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text("Admin")),
                  ],
                  onChanged: (val) => setState(() => _roleFilter = val!),
                ),
              ],

              const Spacer(),

              // 3. REFRESH (Per Tutti)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.green),
                tooltip: "Ricarica Lista",
                onPressed: _refreshList,
              ),

              // 4. SYNC DB (Solo Admin - Operazione costosa/sistemistica)
              if (_currentUserRole == 'admin')
                IconButton(
                  icon: const Icon(Icons.sync, color: Colors.blue),
                  tooltip: "Sync DB",
                  onPressed: _isLoading ? null : _syncUsers,
                ),

              const SizedBox(width: 12),

              // 5. TASTO NUOVO UTENTE (Admin E Nutrizionista)
              // [FIX] Ora visibile anche ai Nutrizionisti
              if (_currentUserRole == 'admin' ||
                  _currentUserRole == 'nutritionist')
                FilledButton.icon(
                  onPressed: _isLoading ? null : _showCreateUserDialog,
                  icon: const Icon(Icons.add),
                  label: const Text("NUOVO UTENTE"),
                ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        if (_isLoading) const LinearProgressIndicator(),
        const SizedBox(height: 20),

        // --- CONTENT ---
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: _usersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Errore Caricamento: ${snapshot.error}',
                    style: TextStyle(color: Colors.red),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text(
                    "Nessun utente trovato.",
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              var allUsers = snapshot.data!;
              final nutNameMap = <String, String>{};
              for (var u in allUsers) {
                if (u['role'] == 'nutritionist') {
                  nutNameMap[u['uid']] =
                      "${u['first_name'] ?? ''} ${u['last_name'] ?? ''}".trim();
                  if (nutNameMap[u['uid']]!.isEmpty) {
                    nutNameMap[u['uid']] = u['email'] ?? 'Unknown';
                  }
                }
              }

              final filteredUsers = allUsers.where((user) {
                final role = (user['role'] ?? 'user').toString().toLowerCase();
                final name =
                    "${user['first_name'] ?? ''} ${user['last_name'] ?? ''}"
                        .toLowerCase();
                final email = (user['email'] ?? '').toString().toLowerCase();
                if (_currentUserRole == 'admin' &&
                    _roleFilter != 'all' &&
                    role != _roleFilter) {
                  return false;
                }
                if (_searchQuery.isNotEmpty) {
                  return name.contains(_searchQuery) ||
                      email.contains(_searchQuery);
                }
                return true;
              }).toList();

              if (filteredUsers.isEmpty) {
                return const Center(
                  child: Text(
                    "Nessun utente corrisponde alla ricerca.",
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              if (_currentUserRole == 'admin') {
                return _buildAdminGroupedLayout(filteredUsers, nutNameMap);
              } else {
                return _buildUserGrid(filteredUsers);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUserGrid(List<dynamic> users) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 240,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: users.length,
      itemBuilder: (context, index) {
        return _UserCard(
          user: users[index],
          onDelete: (uid) => _deleteUser(uid),
          onUploadDiet: _uploadDiet,
          onUploadParser: _uploadParser,
          onHistory: (uid) =>
              _showUserHistory(uid, users[index]['first_name'] ?? 'User'),
          onEdit: _editUser,
          onAssign: null,
          currentUserRole: _currentUserRole,
          currentUserId: _currentUserId,
          roleColor: _getRoleColor(users[index]['role'] ?? 'user'),
        );
      },
    );
  }

  Widget _buildAdminGroupedLayout(
    List<dynamic> users,
    Map<String, String> nutNameMap,
  ) {
    final admins = <dynamic>[];
    final independents = <dynamic>[];
    final nutritionistGroups = <String, List<dynamic>>{};
    final nutritionistDocs = <String, dynamic>{};

    for (var user in users) {
      final role = (user['role'] ?? 'user').toString().toLowerCase();
      final parentId =
          user['parent_id'] as String? ?? user['created_by'] as String?;
      final uid = user['uid'] as String;

      if (role == 'admin') {
        admins.add(user);
      } else if (role == 'independent') {
        independents.add(user);
      } else if (role == 'nutritionist') {
        nutritionistDocs[uid] = user;
        if (!nutritionistGroups.containsKey(uid)) nutritionistGroups[uid] = [];
      } else if (role == 'user') {
        if (parentId != null &&
            (nutNameMap.containsKey(parentId) ||
                nutritionistDocs.containsKey(parentId))) {
          if (!nutritionistGroups.containsKey(parentId)) {
            nutritionistGroups[parentId] = [];
          }
          nutritionistGroups[parentId]!.add(user);
        } else {
          independents.add(user);
        }
      }
    }

    return ListView(
      children: [
        ...nutritionistGroups.entries.map((entry) {
          final nutId = entry.key;
          final clients = entry.value;
          final nutName = nutNameMap[nutId] ?? "Nutritionist ID: $nutId";
          final nutDoc = nutritionistDocs[nutId];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.withValues(alpha: 0.2),
                child: const Icon(Icons.health_and_safety, color: Colors.blue),
              ),
              title: Text(
                nutName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text("${clients.length} Clients"),
              children: [
                if (nutDoc != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SizedBox(
                      height: 240,
                      child: _UserCard(
                        user: nutDoc,
                        onDelete: _deleteUser,
                        onUploadDiet: _uploadDiet,
                        onUploadParser: _uploadParser,
                        onHistory: (_) {},
                        onEdit: _editUser,
                        onAssign: null,
                        currentUserRole: _currentUserRole,
                        currentUserId: _currentUserId,
                        roleColor: _getRoleColor('nutritionist'),
                      ),
                    ),
                  ),
                if (clients.isNotEmpty)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 400,
                          mainAxisExtent: 240,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: clients.length,
                    padding: const EdgeInsets.all(10),
                    itemBuilder: (ctx, idx) => _UserCard(
                      user: clients[idx],
                      onDelete: _deleteUser,
                      onUploadDiet: _uploadDiet,
                      onUploadParser: _uploadParser,
                      onHistory: (uid) => _showUserHistory(
                        uid,
                        clients[idx]['first_name'] ?? 'Client',
                      ),
                      onEdit: _editUser,
                      onAssign: (uid) =>
                          _showManageAssignmentDialog(uid, nutNameMap),
                      currentUserRole: _currentUserRole,
                      currentUserId: _currentUserId,
                      roleColor: _getRoleColor('user'),
                    ),
                  ),
              ],
            ),
          );
        }),

        if (independents.isNotEmpty)
          Card(
            color: Colors.orange.shade50,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              leading: const Icon(
                Icons.person_outline,
                color: Colors.orange,
                size: 32,
              ),
              title: const Text(
                "Independent Users",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              subtitle: Text(
                "${independents.length} Users unassigned or independent",
              ),
            ),
          ),
        if (independents.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisExtent: 240,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
            ),
            itemCount: independents.length,
            itemBuilder: (ctx, idx) => _UserCard(
              user: independents[idx],
              onDelete: _deleteUser,
              onUploadDiet: _uploadDiet,
              onUploadParser: _uploadParser,
              onHistory: (uid) => _showUserHistory(
                uid,
                independents[idx]['first_name'] ?? 'User',
              ),
              onEdit: _editUser,
              onAssign: (uid) => _assignUser(uid, nutNameMap),
              currentUserRole: _currentUserRole,
              currentUserId: _currentUserId,
              roleColor: _getRoleColor('independent'),
            ),
          ),

        if (admins.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Administrators",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisExtent: 240,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
            ),
            itemCount: admins.length,
            itemBuilder: (ctx, idx) => _UserCard(
              user: admins[idx],
              onDelete: _deleteUser,
              onUploadDiet: _uploadDiet,
              onUploadParser: _uploadParser,
              onHistory: (_) {},
              onEdit: _editUser,
              onAssign: null,
              currentUserRole: _currentUserRole,
              currentUserId: _currentUserId,
              roleColor: _getRoleColor('admin'),
            ),
          ),
        ],
      ],
    );
  }
}

class _UserCard extends StatefulWidget {
  final Map<String, dynamic> user;
  final Function(String) onDelete;
  final Function(String) onUploadDiet;
  final Function(String) onUploadParser;
  final Function(String) onHistory;
  final Function(String, String, String, String) onEdit;
  final Function(String)? onAssign;
  final String currentUserRole;
  final String currentUserId;
  final Color roleColor;

  const _UserCard({
    required this.user,
    required this.onDelete,
    required this.onUploadDiet,
    required this.onUploadParser,
    required this.onHistory,
    required this.onEdit,
    this.onAssign,
    required this.currentUserRole,
    required this.currentUserId,
    required this.roleColor,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  bool _isUnlocked = false;
  bool _isUnlocking = false;
  final AdminRepository _repo = AdminRepository();

  String _maskEmail(String email) => (email.length <= 4)
      ? "****"
      : "${email.split('@')[0][0]}***@***.${email.split('.').last}";
  String _maskName(String name) =>
      name.split(' ').map((p) => p.isNotEmpty ? "${p[0]}***" : "*").join(' ');

  Future<void> _unlockData() async {
    setState(() => _isUnlocking = true);
    try {
      await _repo.logDataAccess(widget.user['uid']);
      if (mounted) {
        setState(() => _isUnlocked = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Dati sbloccati."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Impossibile sbloccare: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUnlocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.user;
    final uid = data['uid'] as String;
    final role = data['role'] ?? 'user';
    final realName = "${data['first_name'] ?? ''} ${data['last_name'] ?? ''}";
    final realEmail = data['email'] ?? '';

    final bool isAdmin = widget.currentUserRole == 'admin';
    final bool isMyClient =
        widget.currentUserRole == 'nutritionist' &&
        data['parent_id'] == widget.currentUserId;

    // Privacy Logic: Admin maschera se non sbloccato; Nutrizionista maschera se non suo cliente.
    final bool shouldMask =
        !_isUnlocked &&
        ((isAdmin && (role == 'user' || role == 'independent')) ||
            (widget.currentUserRole == 'nutritionist' && !isMyClient));

    final String displayName = shouldMask ? _maskName(realName) : realName;
    final String displayEmail = shouldMask ? _maskEmail(realEmail) : realEmail;
    final requiresPassChange = data['requires_password_change'] == true;

    bool showParser = isAdmin && data['parent_id'] == null;
    bool showDiet = !isAdmin && (role == 'user' || role == 'independent');
    bool canDelete =
        isAdmin ||
        (role == 'user' && data['parent_id'] == widget.currentUserId);
    bool canEdit =
        requiresPassChange &&
        (isAdmin || data['created_by'] == widget.currentUserId);
    bool canAssign =
        (role == 'independent' || role == 'user') && widget.onAssign != null;

    String dateStr = '-';
    if (data['created_at'] != null) {
      try {
        final d = DateTime.tryParse(data['created_at'].toString());
        if (d != null) dateStr = DateFormat('dd MMM yyyy').format(d);
      } catch (e) {
        debugPrint("Date parse error: $e");
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: widget.roleColor.withValues(alpha: 0.2),
                  child: Text(
                    displayName.isNotEmpty && !displayName.startsWith('*')
                        ? displayName[0].toUpperCase()
                        : "?",
                    style: TextStyle(
                      color: widget.roleColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        displayEmail,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isAdmin)
                        Text(
                          "UID: $uid",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                ),
                if (shouldMask)
                  _isUnlocking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.lock_outline,
                            color: Colors.orange,
                          ),
                          tooltip: "Sblocca Dati",
                          onPressed: _unlockData,
                        ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    role.toString().toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: widget.roleColor,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (requiresPassChange)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  "Password Change Pending",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canAssign)
                  IconButton(
                    icon: Icon(
                      role == 'user' ? Icons.manage_accounts : Icons.person_add,
                      color: Colors.blue,
                    ),
                    onPressed: () => widget.onAssign!(uid),
                  ),
                if (showDiet) ...[
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors.teal),
                    onPressed: () => widget.onHistory(uid),
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file, color: Colors.blueGrey),
                    onPressed: () => widget.onUploadDiet(uid),
                  ),
                ],
                if (showParser)
                  IconButton(
                    icon: const Icon(
                      Icons.settings_applications,
                      color: Colors.orange,
                    ),
                    onPressed: () => widget.onUploadParser(uid),
                  ),
                if (canEdit)
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.indigo),
                    onPressed: () => widget.onEdit(
                      uid,
                      realEmail,
                      data['first_name'] ?? '',
                      data['last_name'] ?? '',
                    ),
                  ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => widget.onDelete(uid),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Creato il: $dateStr",
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserHistoryScreen extends StatefulWidget {
  final String targetUid;
  final String userName;
  const _UserHistoryScreen({required this.targetUid, required this.userName});
  @override
  State<_UserHistoryScreen> createState() => _UserHistoryScreenState();
}

class _UserHistoryScreenState extends State<_UserHistoryScreen> {
  final AdminRepository _repo = AdminRepository();
  late Future<List<dynamic>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _repo.getSecureUserHistory(widget.targetUid);
  }

  // UPDATED: Usa l'API sicura per cancellare
  void _deleteDiet(BuildContext context, String dietId) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Elimina Dieta"),
            content: const Text("Questa azione è irreversibile. Confermi?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text("Annulla"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(c, true),
                child: const Text("Elimina"),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      try {
        await _repo.deleteDiet(dietId); // <--- API CALL
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Dieta eliminata")));
          setState(
            () => _historyFuture = _repo.getSecureUserHistory(widget.targetUid),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Errore: $e")));
        }
      }
    }
  }

  void _viewDiet(BuildContext context, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _DietDetailScreen(data: data)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Storico (Secure): ${widget.userName}")),
      body: FutureBuilder<List<dynamic>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Errore Audit Log: ${snapshot.error}",
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final list = snapshot.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Text("Nessuna dieta presente."));
          }

          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (ctx, i) {
              final data = list[i] as Map<String, dynamic>;
              DateTime date =
                  DateTime.tryParse(data['uploadedAt'] ?? '') ?? DateTime.now();
              return ListTile(
                leading: const Icon(Icons.lock_clock, color: Colors.indigo),
                title: Text(data['fileName'] ?? "Dieta Protetta"),
                subtitle: Text(
                  "Caricato il: ${DateFormat('dd MMM yyyy HH:mm').format(date)}",
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility, color: Colors.green),
                      onPressed: () => _viewDiet(context, data),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteDiet(context, data['id']),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DietDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DietDetailScreen({required this.data});

  @override
  Widget build(BuildContext context) {
    final parsedData = data['parsedData'] as Map<String, dynamic>?;
    final plan = parsedData?['plan'] as Map<String, dynamic>?;

    // Lista ordinata per forzare la sequenza corretta
    final orderedDays = [
      "Lunedì",
      "Martedì",
      "Mercoledì",
      "Giovedì",
      "Venerdì",
      "Sabato",
      "Domenica",
    ];

    return Scaffold(
      appBar: AppBar(title: Text(data['fileName'] ?? "Dettaglio")),
      body: plan == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.security, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "Contenuto Protetto",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "Il contenuto non è disponibile o è stato rimosso.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: orderedDays.map((day) {
                // Se il giorno non esiste nel piano (es. dieta di 5 giorni), lo saltiamo
                if (!plan.containsKey(day)) return const SizedBox.shrink();

                final meals = plan[day] as Map<String, dynamic>;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    title: Text(
                      day,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: meals.entries.map((mEntry) {
                      final mealName = mEntry.key;
                      final dishes = mEntry.value as List<dynamic>;
                      return ListTile(
                        title: Text(
                          mealName,
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: dishes
                              .map(
                                (d) => Text(
                                  "• ${d['name'] ?? '-'} ${d['qty'] ?? ''}",
                                ),
                              )
                              .toList(),
                        ),
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _ParserConfigScreen extends StatelessWidget {
  final String targetUid;
  const _ParserConfigScreen({required this.targetUid});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Config Parser Placeholder")),
    );
  }
}
