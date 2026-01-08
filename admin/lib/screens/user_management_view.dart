import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
  }

  Future<void> _checkCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _currentUserId = user.uid;
          _currentUserRole = data['role'] ?? 'user';
          _isDataLoaded = true;
        });
      }
    }
  }

  Stream<QuerySnapshot> _getUsersStream() {
    final usersRef = FirebaseFirestore.instance.collection('users');
    if (_currentUserRole == 'admin') {
      return usersRef.snapshots();
    } else if (_currentUserRole == 'nutritionist') {
      return usersRef
          .where('created_by', isEqualTo: _currentUserId)
          .snapshots();
    } else {
      return const Stream.empty();
    }
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
            content: const Text("Sei sicuro? L'azione è irreversibile."),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Sposta utente ad un altro nutrizionista:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
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
                          const SnackBar(
                            content: Text("Utente rimosso dal nutrizionista."),
                          ),
                        );
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
                ),
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
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passCtrl,
                    decoration: const InputDecoration(
                      labelText: "Password Temp",
                      prefixIcon: Icon(Icons.key),
                    ),
                  ),
                  const SizedBox(height: 24),
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

  // --- HELPERS ---

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

  // --- BUILD METHODS ---

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
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: "Cerca utente...",
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.toLowerCase()),
                ),
              ),
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
              IconButton(
                icon: const Icon(Icons.sync, color: Colors.blue),
                tooltip: "Sync DB",
                onPressed: _isLoading ? null : _syncUsers,
              ),
              const SizedBox(width: 12),
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
          child: StreamBuilder<QuerySnapshot>(
            stream: _getUsersStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('Err: ${snapshot.error}');
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var allDocs = snapshot.data!.docs;

              // Pre-calculate Nutritionist Names for Headers
              final nutNameMap = <String, String>{};
              for (var doc in allDocs) {
                final d = doc.data() as Map<String, dynamic>;
                if (d['role'] == 'nutritionist') {
                  nutNameMap[doc.id] =
                      "${d['first_name'] ?? ''} ${d['last_name'] ?? ''}".trim();
                  if (nutNameMap[doc.id]!.isEmpty) {
                    nutNameMap[doc.id] = d['email'] ?? 'Unknown';
                  }
                }
              }

              // Filter Logic
              final filteredDocs = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final role = (data['role'] ?? 'user').toString().toLowerCase();
                final name =
                    "${data['first_name'] ?? ''} ${data['last_name'] ?? ''}"
                        .toLowerCase();
                final email = (data['email'] ?? '').toString().toLowerCase();

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

              if (filteredDocs.isEmpty) {
                return const Center(
                  child: Text(
                    "Nessun utente trovato.",
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              // Conditional Rendering based on Role
              if (_currentUserRole == 'admin') {
                return _buildAdminGroupedLayout(filteredDocs, nutNameMap);
              } else {
                return _buildUserGrid(filteredDocs);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUserGrid(List<DocumentSnapshot> docs) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 240,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        return _UserCard(
          doc: docs[index],
          onDelete: _deleteUser,
          onUploadDiet: _uploadDiet,
          onUploadParser: _uploadParser,
          onHistory: (uid) => _showUserHistory(
            uid,
            (docs[index].data() as Map)['first_name'] ?? 'User',
          ),
          onEdit: _editUser,
          onAssign: null,
          currentUserRole: _currentUserRole,
          currentUserId: _currentUserId,
          roleColor: _getRoleColor(
            (docs[index].data() as Map<String, dynamic>)['role'] ?? 'user',
          ),
        );
      },
    );
  }

  Widget _buildAdminGroupedLayout(
    List<DocumentSnapshot> docs,
    Map<String, String> nutNameMap,
  ) {
    final admins = <DocumentSnapshot>[];
    final independents = <DocumentSnapshot>[];
    final nutritionistGroups = <String, List<DocumentSnapshot>>{};
    final nutritionistDocs = <String, DocumentSnapshot>{};

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final role = (data['role'] ?? 'user').toString().toLowerCase();
      final createdBy = data['created_by'] as String?;

      if (role == 'admin') {
        admins.add(doc);
      } else if (role == 'independent') {
        independents.add(doc);
      } else if (role == 'nutritionist') {
        nutritionistDocs[doc.id] = doc;
        if (!nutritionistGroups.containsKey(doc.id)) {
          nutritionistGroups[doc.id] = [];
        }
      } else if (role == 'user') {
        if (createdBy != null &&
            (nutNameMap.containsKey(createdBy) ||
                nutritionistDocs.containsKey(createdBy))) {
          if (!nutritionistGroups.containsKey(createdBy)) {
            nutritionistGroups[createdBy] = [];
          }
          nutritionistGroups[createdBy]!.add(doc);
        } else {
          independents.add(doc);
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
                        doc: nutDoc,
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
                      doc: clients[idx],
                      onDelete: _deleteUser,
                      onUploadDiet: _uploadDiet,
                      onUploadParser: _uploadParser,
                      onHistory: (uid) => _showUserHistory(
                        uid,
                        (clients[idx].data() as Map)['first_name'] ?? 'Client',
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
              doc: independents[idx],
              onDelete: _deleteUser,
              onUploadDiet: _uploadDiet,
              onUploadParser: _uploadParser,
              onHistory: (uid) => _showUserHistory(
                uid,
                (independents[idx].data() as Map)['first_name'] ?? 'User',
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
              doc: admins[idx],
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
  final DocumentSnapshot doc;
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
    required this.doc,
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
  // Stato locale: true = vedo i dati in chiaro per questa sessione
  bool _isUnlocked = false;
  bool _isUnlocking = false; // Per lo spinner durante la chiamata al server

  final AdminRepository _repo = AdminRepository();

  String _maskEmail(String email) {
    if (email.length <= 4) return "****";
    final parts = email.split('@');
    if (parts.length != 2) return "****";
    return "${parts[0][0]}***@***.${parts[1].split('.').last}";
  }

  String _maskName(String name) {
    final parts = name.split(' ');
    if (parts.isEmpty) return "***";
    return parts.map((p) => p.isNotEmpty ? "${p[0]}***" : "*").join(' ');
  }

  Future<void> _unlockData() async {
    setState(() => _isUnlocking = true);
    try {
      // 1. Chiamata al server per loggare l'azione (OBBLIGATORIO)
      // Se questa fallisce, l'utente NON vedrà i dati.
      await _repo.logDataAccess(widget.doc.id);

      // 2. Se successo, sblocca localmente
      if (mounted) {
        setState(() {
          _isUnlocked = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Dati sbloccati. Accesso registrato nel log di sicurezza.",
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
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
    final data = widget.doc.data() as Map<String, dynamic>;
    final role = data['role'] ?? 'user';

    final realFirstName = data['first_name'] ?? '';
    final realLastName = data['last_name'] ?? '';
    final realName = "$realFirstName $realLastName";
    final realEmail = data['email'] ?? '';

    // LOGICA PRIVACY:
    // Se sono Admin, di base vedo mascherato.
    // Se clicco il tasto e il server conferma il log, _isUnlocked diventa true e vedo tutto.
    final bool isAdmin = widget.currentUserRole == 'admin';
    final bool isTargetProfessional =
        (role == 'nutritionist' || role == 'admin');

    // Maschera se: Sono Admin AND non è un collega AND non ho sbloccato manualmente
    final bool shouldMask = isAdmin && !isTargetProfessional && !_isUnlocked;

    final String displayName = shouldMask ? _maskName(realName) : realName;
    final String displayEmail = shouldMask ? _maskEmail(realEmail) : realEmail;

    final date = data['created_at'] != null
        ? DateFormat(
            'dd MMM yyyy',
          ).format((data['created_at'] as Timestamp).toDate())
        : '-';
    final createdBy = data['created_by'];
    final requiresPassChange = data['requires_password_change'] == true;

    // Permessi (Invariati)
    bool showParser = isAdmin;
    bool showDiet = !isAdmin && (role == 'user' || role == 'independent');
    bool canDelete =
        isAdmin || (role == 'user' && createdBy == widget.currentUserId);
    bool canEdit =
        requiresPassChange && (isAdmin || createdBy == widget.currentUserId);
    bool canAssign =
        (role == 'independent' || role == 'user') && widget.onAssign != null;

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
                          "UID: ${widget.doc.id}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // --- TASTO SBLOCCO (Solo se mascherato) ---
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
                          tooltip: "Sblocca Dati (Registra Log)",
                          onPressed:
                              _unlockData, // Chiama la funzione con log server-side
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
                    tooltip: "Gestisci Assegnazione",
                    onPressed: () => widget.onAssign!(data['uid']),
                  ),
                if (showDiet) ...[
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors.teal),
                    tooltip: "Storico Diete (Secure)",
                    onPressed: () => widget.onHistory(data['uid']),
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file, color: Colors.blueGrey),
                    tooltip: "Carica Dieta",
                    onPressed: () => widget.onUploadDiet(data['uid']),
                  ),
                ],
                if (showParser)
                  IconButton(
                    icon: const Icon(
                      Icons.settings_applications,
                      color: Colors.orange,
                    ),
                    tooltip: "Configura Parser",
                    onPressed: () => widget.onUploadParser(data['uid']),
                  ),
                if (canEdit)
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.indigo),
                    tooltip: "Modifica",
                    onPressed: () => widget.onEdit(
                      data['uid'],
                      realEmail,
                      realFirstName,
                      realLastName,
                    ),
                  ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: "Elimina",
                    onPressed: () => widget.onDelete(data['uid']),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Creato il: $date",
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}

// [MODIFICATO] Usa la chiamata sicura invece di Firestore diretto
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
        // Poiché usiamo l'API, dobbiamo ricostruire il riferimento o usare una call API.
        // Se le Rules lo permettono, l'admin può cancellare direttamente.
        await FirebaseFirestore.instance
            .collection('diet_history')
            .doc(dietId)
            .delete();

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Dieta eliminata")));
          // Ricarica la lista
          setState(() {
            _historyFuture = _repo.getSecureUserHistory(widget.targetUid);
          });
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Errore: $e"), backgroundColor: Colors.red),
          );
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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Errore Audit Log: ${snapshot.error}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
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
              DateTime date;
              try {
                date = DateTime.parse(data['uploadedAt']);
              } catch (_) {
                date = DateTime.now();
              }

              return ListTile(
                leading: const Icon(
                  Icons.lock_clock, // Icona diversa per indicare Secure
                  color: Colors.indigo,
                ),
                title: Text(data['fileName'] ?? "Dieta Protetta"),
                subtitle: Text(
                  "Caricato il: ${DateFormat('dd MMM yyyy HH:mm').format(date)}",
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility, color: Colors.green),
                      tooltip: "Visualizza Dettagli",
                      onPressed: () => _viewDiet(context, data),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: "Elimina",
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

    return Scaffold(
      appBar: AppBar(title: Text(data['fileName'] ?? "Dettaglio")),
      body: plan == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.security, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    "Contenuto Protetto",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "Il contenuto del piano alimentare è stato rimosso per privacy durante l'audit dell'amministratore.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: plan.entries.map((entry) {
                final day = entry.key;
                final meals = entry.value as Map<String, dynamic>;
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
                          children: dishes.map((d) {
                            final name = d['name'] ?? '-';
                            final qty = d['qty']?.toString() ?? '';
                            return Text(
                              "• $name ${qty.isNotEmpty ? '($qty)' : ''}",
                            );
                          }).toList(),
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

class _ParserConfigScreen extends StatefulWidget {
  final String targetUid;
  const _ParserConfigScreen({required this.targetUid});
  @override
  State<_ParserConfigScreen> createState() => _ParserConfigScreenState();
}

class _ParserConfigScreenState extends State<_ParserConfigScreen> {
  final AdminRepository _repo = AdminRepository();
  bool _isLoading = false;

  Future<void> _uploadNew() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() => _isLoading = true);
      try {
        await _repo.uploadParserConfig(widget.targetUid, result.files.single);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Configurazione aggiornata!")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Errore: $e"), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configurazione Parser")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.upload),
                label: const Text("Carica Nuova Configurazione (.txt)"),
                onPressed: _isLoading ? null : () => _uploadNew(),
              ),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          const Divider(),
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.targetUid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final user = snapshot.data!.data() as Map<String, dynamic>;
                final current = user['custom_parser_prompt'] as String?;

                return DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: "Attuale"),
                          Tab(text: "Cronologia"),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                current ??
                                    "Nessuna configurazione personalizzata attiva (usa default).",
                              ),
                            ),
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(widget.targetUid)
                                  .collection('parser_history')
                                  .orderBy('uploaded_at', descending: true)
                                  .snapshots(),
                              builder: (ctx, histSnap) {
                                if (!histSnap.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                final docs = histSnap.data!.docs;
                                if (docs.isEmpty) {
                                  return const Center(
                                    child: Text("Nessuna cronologia."),
                                  );
                                }
                                return ListView.separated(
                                  itemCount: docs.length,
                                  separatorBuilder: (_, _) => const Divider(),
                                  itemBuilder: (c, i) {
                                    final h =
                                        docs[i].data() as Map<String, dynamic>;
                                    final date =
                                        (h['uploaded_at'] as Timestamp?)
                                            ?.toDate() ??
                                        DateTime.now();
                                    return ListTile(
                                      title: Text(
                                        DateFormat(
                                          'dd MMM yyyy HH:mm',
                                        ).format(date),
                                      ),
                                      subtitle: Text(
                                        "${(h['content'] as String).substring(0, 50)}...",
                                      ),
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text(
                                              "Dettaglio Config",
                                            ),
                                            content: SingleChildScrollView(
                                              child: Text(h['content']),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
