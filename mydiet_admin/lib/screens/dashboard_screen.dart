import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_management_view.dart';
import 'config_view.dart';
import '../widgets/diet_logo.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  String _userName = "Caricamento...";
  String _userRole = "Utente";
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUser();
  }

  Future<void> _fetchCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _userName =
              "${data['first_name'] ?? 'Utente'} ${data['last_name'] ?? ''}";
          _userRole = data['role'] ?? 'user';
          _isAdmin = _userRole == 'admin';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Definiamo le viste disponibili in base al ruolo
    final List<Widget> views = [
      const UserManagementView(),
      if (_isAdmin) const ConfigView(), // Solo gli admin vedono la config
    ];

    // Se un nutrizionista prova ad andare su config (index 1) ma non esiste, resetta a 0
    if (_selectedIndex >= views.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      body: Row(
        children: [
          // --- SIDEBAR ---
          Container(
            width: 260,
            decoration: const BoxDecoration(color: Color(0xFF1F2937)),
            child: Column(
              children: [
                // Logo
                Container(
                  height: 80,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF374151)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const DietLogo(
                        size: 40,
                        isDarkBackground: true,
                      ), // <--- YOUR LOGO
                      const SizedBox(width: 12),
                      const Text(
                        "MYDIET",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Menu Items
                _SidebarItem(
                  icon: Icons.people_alt_outlined,
                  label: "Gestione Utenti",
                  isSelected: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),

                // Mostra "Impostazioni" SOLO se è Admin
                if (_isAdmin)
                  _SidebarItem(
                    icon: Icons.settings_outlined,
                    label: "Impostazioni",
                    isSelected: _selectedIndex == 1,
                    onTap: () => setState(() => _selectedIndex = 1),
                  ),

                const Spacer(),

                // Profilo Utente Dinamico
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF111827),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: _isAdmin ? Colors.purple : Colors.blue,
                        radius: 16,
                        child: Text(
                          _userName.isNotEmpty
                              ? _userName[0].toUpperCase()
                              : "?",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _userName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _userRole
                                  .toUpperCase(), // Mostra il ruolo vero (es. NUTRITIONIST)
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.logout,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        tooltip: "Esci",
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- CONTENT ---
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  alignment: Alignment.centerLeft,
                  color: Colors.white,
                  child: Text(
                    _selectedIndex == 0 ? "Utenti" : "Configurazione",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: views[_selectedIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF374151) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey[400],
                size: 22,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[400],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
